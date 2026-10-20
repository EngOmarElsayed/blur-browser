import CommonCrypto
import CryptoKit
import Foundation

/// CTAP2 status codes this client reacts to (CTAP 2.1 §8.2).
enum CTAP2Status {
    static let invalidCommand: UInt8 = 0x01
    static let invalidParameter: UInt8 = 0x02
    static let credentialExcluded: UInt8 = 0x19
    static let unsupportedAlgorithm: UInt8 = 0x26
    static let operationDenied: UInt8 = 0x27
    static let keepaliveCancel: UInt8 = 0x2D
    static let noCredentials: UInt8 = 0x2E
    static let userActionTimeout: UInt8 = 0x2F
    static let notAllowed: UInt8 = 0x30
    static let pinInvalid: UInt8 = 0x31
    static let pinBlocked: UInt8 = 0x32
    static let pinAuthInvalid: UInt8 = 0x33
    static let pinAuthBlocked: UInt8 = 0x34
    static let pinNotSet: UInt8 = 0x35
    static let puatRequired: UInt8 = 0x36
    static let pinPolicyViolation: UInt8 = 0x37
    static let keyStoreFull: UInt8 = 0x28
    static let uvBlocked: UInt8 = 0x3C
    static let uvInvalid: UInt8 = 0x3F
    static let unauthorizedPermission: UInt8 = 0x40
}

struct CTAP2Error: Error, CustomStringConvertible {
    let status: UInt8
    var description: String { String(format: "CTAP2 error 0x%02X", status) }
}

struct AuthenticatorInfo {
    var versions: [String] = []
    var extensions: [String] = []
    var aaguid = Data(count: 16)
    var options: [String: Bool] = [:]
    var maxMessageSize: Int?
    var pinUvAuthProtocols: [Int] = []
    var maxCredentialCountInList: Int?
    var maxCredentialIdLength: Int?
    var transports: [String] = []

    init() {}

    init(_ cbor: CBOR) {
        versions = cbor[1]?.arrayValue?.compactMap(\.textValue) ?? []
        extensions = cbor[2]?.arrayValue?.compactMap(\.textValue) ?? []
        aaguid = cbor[3]?.bytesValue ?? Data(count: 16)
        for (key, value) in cbor[4]?.mapValue ?? [] {
            if let k = key.textValue, let v = value.boolValue { options[k] = v }
        }
        maxMessageSize = cbor[5]?.intValue
        pinUvAuthProtocols = cbor[6]?.arrayValue?.compactMap(\.intValue) ?? []
        maxCredentialCountInList = cbor[7]?.intValue
        maxCredentialIdLength = cbor[8]?.intValue
        transports = cbor[9]?.arrayValue?.compactMap(\.textValue) ?? []
    }

    var isCTAP2: Bool { versions.contains { $0.hasPrefix("FIDO_2") } }
    var isCTAP21: Bool { versions.contains("FIDO_2_1") || versions.contains("FIDO_2_1_PRE") }
    /// nil: no PIN support; false: supported but not set; true: set.
    var clientPin: Bool? { options["clientPin"] }
    var hasBuiltInUV: Bool { options["uv"] == true }
    var supportsPinUvAuthToken: Bool { options["pinUvAuthToken"] == true }
    var supportsResidentKeys: Bool { options["rk"] == true }
    var makeCredUvNotRequired: Bool { options["makeCredUvNotRqd"] == true }
    var canVerifyUser: Bool { clientPin == true || hasBuiltInUV }

    var preferredPINProtocol: PINProtocol? {
        let supported = pinUvAuthProtocols.isEmpty ? [1] : pinUvAuthProtocols
        return supported.contains(2) ? PINProtocol(version: 2) : supported.contains(1) ? PINProtocol(version: 1) : nil
    }
}

/// A pinUvAuthToken bound to one PIN protocol.
struct PINToken {
    let token: Data
    let pinProtocol: PINProtocol

    func authenticate(_ message: Data) -> Data {
        pinProtocol.authenticate(key: token, message: message)
    }
}

// MARK: - Authenticator

/// Carries CTAP2 messages: USB HID, or the caBLE tunnel to a phone.
@MainActor
protocol CTAPTransport: AnyObject {
    /// Sends `[command] ‖ CBOR` and returns `[status] ‖ CBOR`.
    func cbor(_ request: [UInt8], onKeepalive: @escaping (UInt8) -> Void) async throws -> [UInt8]
}

extension CTAPHIDDevice: CTAPTransport {}

@MainActor
final class CTAP2Authenticator {
    enum Command: UInt8 {
        case makeCredential = 0x01
        case getAssertion = 0x02
        case getInfo = 0x04
        case clientPIN = 0x06
        case getNextAssertion = 0x08
        case selection = 0x0B
    }

    enum Permission {
        static let makeCredential: UInt8 = 0x01
        static let getAssertion: UInt8 = 0x02
    }

    let transport: CTAPTransport
    /// A phone over caBLE rather than a key on USB.
    let isHybrid: Bool
    private(set) var info = AuthenticatorInfo()
    /// Gets CTAPHID keepalive status: 1 processing, 2 waiting for a touch.
    var onKeepalive: (UInt8) -> Void = { _ in }

    init(device: CTAPHIDDevice) {
        transport = device
        isHybrid = false
    }

    init(tunnel: CTAPTransport, info: AuthenticatorInfo?) {
        transport = tunnel
        isHybrid = true
        if let info { self.info = info }
    }

    @discardableResult
    func command(_ command: Command, _ parameters: CBOR? = nil) async throws -> CBOR? {
        var request = [command.rawValue]
        if let parameters { request += parameters.encoded() }
        let keepalive = onKeepalive
        let response = try await transport.cbor(request, onKeepalive: { keepalive($0) })
        guard let status = response.first else { throw SecurityKeyTransportError.protocolError("empty response") }
        if status == CTAP2Status.keepaliveCancel, Task.isCancelled { throw CancellationError() }
        guard status == 0 else { throw CTAP2Error(status: status) }
        guard response.count > 1 else { return nil }
        return try CBOR.decodeAll(Data(response.dropFirst()))
    }

    func loadInfo() async throws {
        guard let response = try await command(.getInfo) else { throw SecurityKeyTransportError.protocolError("no getInfo") }
        info = AuthenticatorInfo(response)
    }

    /// Blinks the key and waits for a touch, to pick one key out of several.
    func waitForTouch() async throws {
        if info.isCTAP21 {
            try await command(.selection)
            return
        }
        // CTAP 2.0 has no selection command. A makeCredential with an empty
        // pinAuth waits for a touch, then fails with PIN_INVALID or
        // PIN_NOT_SET (CTAP 2.0 §5.1 step 6), so either answer means touched.
        let params = CBOR.map([
            (.int(1), .bytes(Data(count: 32))),
            (.int(2), .map([(.text("id"), .text(".dummy"))])),
            (.int(3), .map([(.text("id"), .bytes(Data([1]))), (.text("name"), .text("dummy"))])),
            (.int(4), .array([.map([(.text("alg"), .int(-7)), (.text("type"), .text("public-key"))])])),
            (.int(8), .bytes(Data())),
            (.int(9), .int(1)),
        ])
        do {
            try await command(.makeCredential, params)
        } catch let error as CTAP2Error where [CTAP2Status.pinInvalid, CTAP2Status.pinNotSet, CTAP2Status.pinAuthInvalid].contains(error.status) {
            return
        }
    }

    // MARK: clientPIN

    @discardableResult
    private func clientPIN(_ subCommand: Int, pinProtocol: PINProtocol?, _ extra: [(CBOR, CBOR)] = []) async throws -> CBOR? {
        var pairs: [(CBOR, CBOR)] = [(.int(2), .int(subCommand))]
        if let pinProtocol { pairs.append((.int(1), .int(pinProtocol.version))) }
        return try await command(.clientPIN, .map(pairs + extra))
    }

    func pinRetries() async throws -> Int? {
        try await clientPIN(0x01, pinProtocol: info.preferredPINProtocol)?[3]?.intValue
    }

    private func sharedSecret(_ pinProtocol: PINProtocol) async throws -> (platformKey: CBOR, secret: Data) {
        guard let peer = try await clientPIN(0x02, pinProtocol: pinProtocol)?[1] else {
            throw SecurityKeyTransportError.protocolError("no key agreement")
        }
        return try pinProtocol.encapsulate(peer: peer)
    }

    /// getPinToken (2.0) or getPinUvAuthTokenUsingPinWithPermissions (2.1).
    func pinToken(pin: String, permissions: UInt8, rpId: String) async throws -> PINToken {
        guard let pinProtocol = info.preferredPINProtocol else { throw CTAP2Error(status: CTAP2Status.invalidParameter) }
        let (platformKey, secret) = try await sharedSecret(pinProtocol)
        let pinHash = Data(SHA256.hash(data: Data(pin.precomposedStringWithCanonicalMapping.utf8)).prefix(16))
        var extra: [(CBOR, CBOR)] = [
            (.int(3), platformKey),
            (.int(6), .bytes(try pinProtocol.encrypt(key: secret, pinHash))),
        ]
        let subCommand: Int
        if info.supportsPinUvAuthToken {
            subCommand = 0x09
            extra += [(.int(9), .int(Int(permissions))), (.int(0x0A), .text(rpId))]
        } else {
            subCommand = 0x05
        }
        guard let encrypted = try await clientPIN(subCommand, pinProtocol: pinProtocol, extra)?[2]?.bytesValue else {
            throw SecurityKeyTransportError.protocolError("no token")
        }
        return PINToken(token: try pinProtocol.decrypt(key: secret, encrypted), pinProtocol: pinProtocol)
    }

    /// setPIN, for keys that have none yet.
    func setPIN(_ pin: String) async throws {
        guard let pinProtocol = info.preferredPINProtocol else { throw CTAP2Error(status: CTAP2Status.invalidParameter) }
        var padded = Data(pin.precomposedStringWithCanonicalMapping.utf8)
        guard padded.count >= 4, padded.count <= 63 else { throw CTAP2Error(status: CTAP2Status.pinPolicyViolation) }
        padded += Data(count: 64 - padded.count)
        let (platformKey, secret) = try await sharedSecret(pinProtocol)
        let newPinEnc = try pinProtocol.encrypt(key: secret, padded)
        try await clientPIN(0x03, pinProtocol: pinProtocol, [
            (.int(3), platformKey),
            (.int(4), .bytes(pinProtocol.authenticate(key: secret, message: newPinEnc))),
            (.int(5), .bytes(newPinEnc)),
        ])
        info.options["clientPin"] = true
    }

    /// getPinUvAuthTokenUsingUvWithPermissions: fingerprint keys (2.1).
    func uvToken(permissions: UInt8, rpId: String) async throws -> PINToken {
        guard let pinProtocol = info.preferredPINProtocol else { throw CTAP2Error(status: CTAP2Status.invalidParameter) }
        let (platformKey, secret) = try await sharedSecret(pinProtocol)
        let extra: [(CBOR, CBOR)] = [
            (.int(3), platformKey),
            (.int(9), .int(Int(permissions))),
            (.int(0x0A), .text(rpId)),
        ]
        guard let encrypted = try await clientPIN(0x06, pinProtocol: pinProtocol, extra)?[2]?.bytesValue else {
            throw SecurityKeyTransportError.protocolError("no token")
        }
        return PINToken(token: try pinProtocol.decrypt(key: secret, encrypted), pinProtocol: pinProtocol)
    }
}

// MARK: - PIN/UV auth protocols one and two (CTAP 2.1 §6.5.6, §6.5.7)

struct PINProtocol {
    let version: Int

    /// ECDH with the key's agreement key. Returns our COSE public key and the
    /// shared secret: SHA-256(Z) for v1, HMAC key ‖ AES key for v2.
    func encapsulate(peer: CBOR) throws -> (platformKey: CBOR, secret: Data) {
        guard let x = peer[-2]?.bytesValue, let y = peer[-3]?.bytesValue, x.count == 32, y.count == 32 else {
            throw SecurityKeyTransportError.protocolError("bad key agreement")
        }
        let peerKey = try P256.KeyAgreement.PublicKey(x963Representation: Data([0x04]) + x + y)
        let privateKey = P256.KeyAgreement.PrivateKey()
        let z = try privateKey.sharedSecretFromKeyAgreement(with: peerKey).withUnsafeBytes { Data($0) }
        let raw = privateKey.publicKey.x963Representation
        let platformKey = CBOR.map([
            (.int(1), .int(2)),
            (.int(3), .int(-25)),
            (.int(-1), .int(1)),
            (.int(-2), .bytes(raw[1..<33])),
            (.int(-3), .bytes(raw[33..<65])),
        ])
        let secret: Data
        if version == 1 {
            secret = Data(SHA256.hash(data: z))
        } else {
            let salt = Data(count: 32)
            func hkdf(_ info: String) -> Data {
                HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: z), salt: salt, info: Data(info.utf8), outputByteCount: 32)
                    .withUnsafeBytes { Data($0) }
            }
            secret = hkdf("CTAP2 HMAC key") + hkdf("CTAP2 AES key")
        }
        return (platformKey, secret)
    }

    func encrypt(key: Data, _ plaintext: Data) throws -> Data {
        if version == 1 {
            return try Self.aesCBC(encrypt: true, key: key, iv: Data(count: 16), plaintext)
        }
        var iv = Data(count: 16)
        _ = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return iv + (try Self.aesCBC(encrypt: true, key: key.suffix(32), iv: iv, plaintext))
    }

    func decrypt(key: Data, _ ciphertext: Data) throws -> Data {
        if version == 1 {
            return try Self.aesCBC(encrypt: false, key: key, iv: Data(count: 16), ciphertext)
        }
        guard ciphertext.count > 16 else { throw SecurityKeyTransportError.protocolError("short ciphertext") }
        return try Self.aesCBC(encrypt: false, key: key.suffix(32), iv: ciphertext.prefix(16), ciphertext.dropFirst(16))
    }

    /// HMAC-SHA-256; v1 keeps the first 16 bytes. A 64-byte v2 shared secret
    /// uses only its HMAC half; a pinUvAuthToken is used whole.
    func authenticate(key: Data, message: Data) -> Data {
        let hmacKey = version == 2 && key.count > 32 ? key.prefix(32) : key
        let mac = Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: hmacKey)))
        return version == 1 ? mac.prefix(16) : mac
    }

    private static func aesCBC(encrypt: Bool, key: Data, iv: Data, _ input: Data) throws -> Data {
        guard input.count % 16 == 0 else { throw SecurityKeyTransportError.protocolError("unaligned AES input") }
        let key = Data(key), iv = Data(iv), input = Data(input)
        var output = Data(count: input.count)
        var moved = 0
        let status = output.withUnsafeMutableBytes { out in
            key.withUnsafeBytes { k in
                iv.withUnsafeBytes { v in
                    input.withUnsafeBytes { i in
                        CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0,
                                k.baseAddress, k.count, v.baseAddress, i.baseAddress, i.count,
                                out.baseAddress, out.count, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw SecurityKeyTransportError.protocolError("AES failed \(status)") }
        return output.prefix(moved)
    }
}
