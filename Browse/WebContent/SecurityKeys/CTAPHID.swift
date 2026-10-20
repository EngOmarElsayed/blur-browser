import Foundation
import IOKit.hid
import OSLog

/// CTAPHID (FIDO's USB HID framing, CTAP 2.1 §11.2) over IOKit.
///
/// Every callback is scheduled on the main run loop, so the transport lives on
/// the main actor. Messages are tiny (a few hundred bytes), and the slow part,
/// waiting for a touch, is an `await`, not a blocked thread.

enum CTAPHIDCommand: UInt8 {
    case ping = 0x01
    case msg = 0x03
    case initialize = 0x06
    case wink = 0x08
    case cbor = 0x10
    case cancel = 0x11
    case keepalive = 0x3B
    case error = 0x3F
}

enum SecurityKeyTransportError: Error {
    case deviceGone
    case ioFailure(IOReturn)
    case timeout
    case protocolError(String)
    case hidError(UInt8)
}

let securityKeyLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Blur-Browser", category: "SecurityKeys")

// MARK: - Device

@MainActor
final class CTAPHIDDevice {
    static let broadcastCID: UInt32 = 0xFFFF_FFFF
    private static let capabilityCBOR: UInt8 = 0x04

    let device: IOHIDDevice
    let reportSize: Int
    let productName: String
    // Only touched by IOKit on the main run loop and freed in deinit.
    nonisolated(unsafe) private let buffer: UnsafeMutablePointer<UInt8>
    private var isOpen = false
    private(set) var isGone = false

    private var channel: UInt32 = broadcastCID
    private(set) var capabilities: UInt8 = 0
    var supportsCBOR: Bool { capabilities & Self.capabilityCBOR != 0 }

    private var pending: [[UInt8]] = []
    private var waiter: CheckedContinuation<[UInt8], Error>?
    private var waiterToken = 0
    private var cancelRequested = false

    init(device: IOHIDDevice) {
        self.device = device
        let size = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64
        reportSize = size > 0 ? size : 64
        productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Security key"
        buffer = .allocate(capacity: reportSize)
    }

    deinit {
        buffer.deallocate()
    }

    func open() throws {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw SecurityKeyTransportError.ioFailure(result) }
        isOpen = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, reportSize, { context, _, _, _, _, report, length in
            guard let context else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated {
                Unmanaged<CTAPHIDDevice>.fromOpaque(context).takeUnretainedValue().received(bytes)
            }
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        IOHIDDeviceRegisterInputReportCallback(device, buffer, reportSize, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        fail(SecurityKeyTransportError.deviceGone)
    }

    func markGone() {
        isGone = true
        fail(SecurityKeyTransportError.deviceGone)
        close()
    }

    // MARK: Packets

    private func received(_ bytes: [UInt8]) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: bytes)
        } else {
            pending.append(bytes)
        }
    }

    private func fail(_ error: Error) {
        guard let waiter else { return }
        self.waiter = nil
        waiter.resume(throwing: error)
    }

    private func readPacket(timeout: Duration?) async throws -> [UInt8] {
        if !pending.isEmpty { return pending.removeFirst() }
        if isGone { throw SecurityKeyTransportError.deviceGone }
        waiterToken += 1
        let token = waiterToken
        if let timeout {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, self.waiterToken == token else { return }
                self.fail(SecurityKeyTransportError.timeout)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
        }
    }

    private func writePacket(_ packet: [UInt8]) throws {
        guard !isGone else { throw SecurityKeyTransportError.deviceGone }
        var report = packet
        report += [UInt8](repeating: 0, count: max(0, reportSize - report.count))
        let result = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, reportSize)
        }
        guard result == kIOReturnSuccess else { throw SecurityKeyTransportError.ioFailure(result) }
    }

    private static func cidBytes(_ cid: UInt32) -> [UInt8] {
        [UInt8(cid >> 24), UInt8((cid >> 16) & 0xFF), UInt8((cid >> 8) & 0xFF), UInt8(cid & 0xFF)]
    }

    private func send(_ command: CTAPHIDCommand, _ payload: [UInt8], cid: UInt32) throws {
        guard payload.count <= 7609 else { throw SecurityKeyTransportError.protocolError("message too long") }
        let cidBytes = Self.cidBytes(cid)
        let firstChunk = reportSize - 7
        var packet = cidBytes + [0x80 | command.rawValue, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
        packet += payload.prefix(firstChunk)
        try writePacket(packet)
        var offset = firstChunk
        var sequence: UInt8 = 0
        while offset < payload.count {
            let end = min(payload.count, offset + reportSize - 5)
            try writePacket(cidBytes + [sequence] + payload[offset..<end])
            offset = end
            sequence += 1
        }
    }

    /// Reads one whole message on `cid`, skipping other channels.
    private func receive(cid: UInt32, timeout: Duration?, onKeepalive: (UInt8) -> Void) async throws -> (UInt8, [UInt8]) {
        while true {
            let packet = try await readPacket(timeout: cancelRequested ? .seconds(2) : timeout)
            guard packet.count >= 7 else { continue }
            let packetCID = UInt32(packet[0]) << 24 | UInt32(packet[1]) << 16 | UInt32(packet[2]) << 8 | UInt32(packet[3])
            guard packetCID == cid, packet[4] & 0x80 != 0 else { continue }
            let command = packet[4] & 0x7F
            let length = Int(packet[5]) << 8 | Int(packet[6])
            if command == CTAPHIDCommand.keepalive.rawValue {
                onKeepalive(packet[7])
                continue
            }
            var data = Array(packet[7..<min(packet.count, 7 + length)])
            var sequence: UInt8 = 0
            while data.count < length {
                let next = try await readPacket(timeout: .seconds(2))
                guard next.count >= 5,
                      Array(next[0..<4]) == Self.cidBytes(cid),
                      next[4] == sequence else {
                    throw SecurityKeyTransportError.protocolError("bad continuation packet")
                }
                data += next[5..<min(next.count, 5 + length - data.count)]
                sequence += 1
            }
            if command == CTAPHIDCommand.error.rawValue {
                throw SecurityKeyTransportError.hidError(data.first ?? 0)
            }
            return (command, data)
        }
    }

    // MARK: Commands

    /// CTAPHID_INIT: allocates a channel and reads the capability flags.
    func initialize() async throws {
        var nonce = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce)
        pending.removeAll()
        try send(.initialize, nonce, cid: Self.broadcastCID)
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            let (command, data) = try await receive(cid: Self.broadcastCID, timeout: .seconds(3)) { _ in }
            guard command == CTAPHIDCommand.initialize.rawValue, data.count >= 17, Array(data[0..<8]) == nonce else { continue }
            channel = UInt32(data[8]) << 24 | UInt32(data[9]) << 16 | UInt32(data[10]) << 8 | UInt32(data[11])
            capabilities = data[16]
            return
        }
        throw SecurityKeyTransportError.timeout
    }

    /// Sends a CTAP2 command and returns the response (status byte first).
    /// `onKeepalive` gets 1 (processing) or 2 (waiting for a touch).
    /// Cancelling the task sends CTAPHID_CANCEL, which makes the key answer
    /// right away with CTAP2_ERR_KEEPALIVE_CANCEL.
    func cbor(_ request: [UInt8], onKeepalive: @escaping (UInt8) -> Void) async throws -> [UInt8] {
        try Task.checkCancellation()
        cancelRequested = false
        try send(.cbor, request, cid: channel)
        let cid = channel
        return try await withTaskCancellationHandler {
            let (command, data) = try await receive(cid: cid, timeout: nil, onKeepalive: onKeepalive)
            guard command == CTAPHIDCommand.cbor.rawValue else {
                throw SecurityKeyTransportError.protocolError("unexpected reply \(command)")
            }
            return data
        } onCancel: {
            Task { @MainActor in self.sendCancel(cid: cid) }
        }
    }

    private func sendCancel(cid: UInt32) {
        cancelRequested = true
        try? send(.cancel, [], cid: cid)
        // If the key wasn't busy it won't answer; don't wait forever.
        let token = waiterToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.waiterToken == token else { return }
            self.fail(CancellationError())
        }
    }
}

// MARK: - Discovery

/// Watches for FIDO HID devices (usage page 0xF1D0, usage 0x01) for the
/// length of one WebAuthn request. Devices that answer CTAPHID_INIT show up
/// in `devices`; `changes` yields whenever that list changes.
@MainActor
final class SecurityKeyDiscovery {
    private let manager: IOHIDManager
    private(set) var devices: [CTAPHIDDevice] = []
    private var listeners: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var running = false

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: 0xF1D0,
            kIOHIDDeviceUsageKey as String: 0x01,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    }

    func start() {
        guard !running else { return }
        running = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<SecurityKeyDiscovery>.fromOpaque(context).takeUnretainedValue().added(device)
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<SecurityKeyDiscovery>.fromOpaque(context).takeUnretainedValue().removed(device)
            }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func stop() {
        guard running else { return }
        running = false
        for device in devices { device.close() }
        devices.removeAll()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        for listener in listeners.values { listener.finish() }
        listeners.removeAll()
    }

    /// Yields once now and again on every change, until `stop()`.
    func changes() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        listeners[id] = continuation
        continuation.yield()
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.listeners[id] = nil }
        }
        return stream
    }

    private func notify() {
        for listener in listeners.values { listener.yield() }
    }

    private func added(_ hidDevice: IOHIDDevice) {
        guard running, !devices.contains(where: { $0.device === hidDevice }) else { return }
        let device = CTAPHIDDevice(device: hidDevice)
        Task { @MainActor in
            do {
                try device.open()
                try await device.initialize()
                guard self.running, !device.isGone else { device.close(); return }
                securityKeyLogger.notice("Security key connected: \(device.productName, privacy: .public), CBOR \(device.supportsCBOR)")
                self.devices.append(device)
                self.notify()
            } catch {
                securityKeyLogger.error("Security key \(device.productName, privacy: .public) failed to initialize: \(String(describing: error), privacy: .public)")
                device.close()
            }
        }
    }

    private func removed(_ hidDevice: IOHIDDevice) {
        guard let index = devices.firstIndex(where: { $0.device === hidDevice }) else { return }
        let device = devices.remove(at: index)
        device.markGone()
        notify()
    }
}
