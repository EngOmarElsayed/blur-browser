import CoreBluetooth
import Foundation

/// Listens for the phone's caBLE advert: 20 bytes of service data under the
/// FIDO UUID (0xFFF9, or Google's older 0xFDE2), encrypted with the QR's EID
/// key. Only our own phone's advert decrypts.
@MainActor
final class CableAdvertScanner: NSObject, CBCentralManagerDelegate {
    enum Status { case starting, scanning, poweredOff, unauthorized, unsupported }

    nonisolated(unsafe) private static let serviceUUIDs = [CBUUID(string: "FFF9"), CBUUID(string: "FDE2")]

    private let eidKey: Data
    private var central: CBCentralManager?
    var onStatus: (Status) -> Void = { _ in }
    var onAdvert: (CableV2.Advert) -> Void = { _ in }

    init(eidKey: Data) {
        self.eidKey = eidKey
    }

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func stop() {
        central?.stopScan()
        central?.delegate = nil
        central = nil
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated {
            switch state {
            case .poweredOn:
                // No service filter: phones may list the UUID only in service data.
                self.central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
                onStatus(.scanning)
            case .poweredOff: onStatus(.poweredOff)
            case .unauthorized: onStatus(.unauthorized)
            case .unsupported: onStatus(.unsupported)
            default: onStatus(.starting)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] else { return }
        let candidates = Self.serviceUUIDs.compactMap { serviceData[$0] }.filter { $0.count == 20 }
        guard !candidates.isEmpty else { return }
        MainActor.assumeIsolated {
            for data in candidates {
                if let advert = CableV2.decryptAdvert(data, eidKey: eidKey) {
                    onAdvert(advert)
                    return
                }
            }
        }
    }
}

/// The encrypted WebSocket tunnel to a phone, carrying CTAP2 messages.
@MainActor
final class CableTunnel: NSObject, CTAPTransport {
    private enum MessageType: UInt8 {
        case shutdown = 0
        case ctap = 1
        case update = 2
    }

    private var session: URLSession!
    private var socket: URLSessionWebSocketTask?
    private var crypter: CableCrypter?
    /// getInfo from the phone's post-handshake message.
    private(set) var info: AuthenticatorInfo?

    override init() {
        super.init()
        session = URLSession(configuration: .ephemeral)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    /// Connects to the tunnel server the advert names, runs the handshake and
    /// reads the phone's post-handshake message. Cancelling closes the socket.
    func open(qr: CableV2.QRSession, advert: CableV2.Advert) async throws {
        try await withTaskCancellationHandler {
            try await handshake(qr: qr, advert: advert)
        } onCancel: {
            Task { @MainActor in self.close() }
        }
    }

    private func handshake(qr: CableV2.QRSession, advert: CableV2.Advert) async throws {
        guard let url = URL(string: "wss://\(advert.domain)/cable/connect/\(Self.hex(advert.routingID))/\(Self.hex(qr.tunnelID))") else {
            throw SecurityKeyTransportError.protocolError("bad tunnel URL")
        }
        securityKeyLogger.notice("caBLE: connecting to \(advert.domain, privacy: .public)")
        let socket = session.webSocketTask(with: url, protocols: ["fido.cable"])
        self.socket = socket
        socket.resume()

        var handshake = CableHandshake(psk: qr.psk(for: advert), identity: qr.identityKey)
        try await socket.send(.data(try handshake.initialMessage()))
        let response = try await receiveData()
        var crypter = try handshake.processResponse(response)

        let postHandshake = try crypter.decrypt(try await receiveData())
        self.crypter = crypter
        if let message = try? CBOR.decodeAll(postHandshake), let infoBytes = message[1]?.bytesValue,
           let infoCBOR = try? CBOR.decodeAll(infoBytes) {
            info = AuthenticatorInfo(infoCBOR)
        }
        securityKeyLogger.notice("caBLE: handshake done, getInfo \(self.info != nil)")
    }

    private func receiveData() async throws -> Data {
        guard let socket else { throw SecurityKeyTransportError.deviceGone }
        switch try await socket.receive() {
        case .data(let data): return data
        case .string(let string): return Data(string.utf8)
        @unknown default: throw SecurityKeyTransportError.protocolError("unknown frame")
        }
    }

    func cbor(_ request: [UInt8], onKeepalive: @escaping (UInt8) -> Void) async throws -> [UInt8] {
        guard let socket, var crypter else { throw SecurityKeyTransportError.deviceGone }
        try Task.checkCancellation()
        let encrypted = try crypter.encrypt(Data([MessageType.ctap.rawValue] + request))
        self.crypter = crypter
        return try await withTaskCancellationHandler {
            try await socket.send(.data(encrypted))
            while true {
                let frame = try await receiveData()
                guard var crypter = self.crypter else { throw SecurityKeyTransportError.deviceGone }
                let plaintext = try crypter.decrypt(frame)
                self.crypter = crypter
                guard let type = plaintext.first else { continue }
                switch MessageType(rawValue: type) {
                case .ctap: return [UInt8](plaintext.dropFirst())
                case .shutdown: throw SecurityKeyTransportError.deviceGone
                default: continue // linking updates: not stored
                }
            }
        } onCancel: {
            Task { @MainActor in self.close() }
        }
    }

    func close() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        session.invalidateAndCancel()
    }
}
