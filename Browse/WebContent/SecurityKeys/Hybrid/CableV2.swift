import CommonCrypto
import CoreImage
import CryptoKit
import Foundation

/// caBLE v2, the "hybrid" transport (CTAP 2.2 §11.5): the page's request is
/// served by a phone that scans a QR code. The phone proves it's nearby with
/// an encrypted BLE advert, then both sides meet at a tunnel server over a
/// WebSocket and run a Noise handshake keyed by the QR secret.
///
/// The constants and layouts follow Chromium's implementation
/// (device/fido/cable/v2_handshake.cc), which iOS and Android phones talk to.
enum CableV2 {
    enum DerivedValue: UInt32 {
        case eidKey = 1
        case tunnelID = 2
        case psk = 3
    }

    /// HKDF-SHA-256 with the value type, little-endian, as info.
    static func derive(_ count: Int, secret: Data, salt: Data, _ type: DerivedValue) -> Data {
        var info = type.rawValue.littleEndian
        let infoData = Data(bytes: &info, count: 4)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret), salt: salt, info: infoData, outputByteCount: count)
            .withUnsafeBytes { Data($0) }
    }

    // MARK: Tunnel server domains

    private static let assignedDomains = ["cable.ua5v.com", "cable.auth.com"]

    static func tunnelDomain(_ encoded: UInt16) -> String? {
        if encoded < 256 {
            return Int(encoded) < assignedDomains.count ? assignedDomains[Int(encoded)] : nil
        }
        var input = Data("caBLEv2 tunnel server domain".utf8)
        input += [UInt8(encoded & 0xFF), UInt8(encoded >> 8), 0]
        let digest = [UInt8](SHA256.hash(data: input))
        var value = digest[0..<8].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
        let tlds = ["com", "org", "net", "info"]
        let tld = tlds[Int(value & 3)]
        value >>= 2
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var name = "cable."
        while value != 0 {
            name.append(alphabet[Int(value & 31)])
            value >>= 5
        }
        return name + "." + tld
    }

    // MARK: Adverts

    struct Advert {
        /// The decrypted 16-byte advert; salt for the PSK.
        let plaintext: Data
        let routingID: Data
        let domain: String
    }

    /// Checks the 4-byte HMAC tag and decrypts the single AES block.
    static func decryptAdvert(_ advert: Data, eidKey: Data) -> Advert? {
        guard advert.count == 20 else { return nil }
        let ciphertext = advert.prefix(16)
        let tag = advert.suffix(4)
        let mac = Data(HMAC<SHA256>.authenticationCode(for: ciphertext, using: SymmetricKey(data: eidKey.suffix(32))))
        guard mac.prefix(4) == tag else { return nil }
        guard let plaintext = aesECBDecryptBlock(key: eidKey.prefix(32), Data(ciphertext)), plaintext[plaintext.startIndex] == 0 else {
            return nil
        }
        let bytes = [UInt8](plaintext)
        let encodedDomain = UInt16(bytes[14]) | UInt16(bytes[15]) << 8
        guard let domain = tunnelDomain(encodedDomain) else { return nil }
        return Advert(plaintext: plaintext, routingID: Data(bytes[11..<14]), domain: domain)
    }

    private static func aesECBDecryptBlock(key: Data, _ block: Data) -> Data? {
        let key = Data(key)
        var out = Data(count: 16)
        var moved = 0
        let status = out.withUnsafeMutableBytes { o in
            key.withUnsafeBytes { k in
                block.withUnsafeBytes { b in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                            k.baseAddress, k.count, nil, b.baseAddress, 16, o.baseAddress, 16, &moved)
                }
            }
        }
        return status == kCCSuccess && moved == 16 ? out : nil
    }

    // MARK: QR code

    /// One hybrid attempt: the QR code's secret and identity key.
    struct QRSession {
        let secret: Data
        let identityKey = P256.KeyAgreement.PrivateKey()
        let eidKey: Data
        let tunnelID: Data
        let url: String

        /// `requestType` is "mc" (create) or "ga" (get).
        init(requestType: String) {
            var secret = Data(count: 16)
            _ = secret.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
            self.secret = secret
            eidKey = CableV2.derive(64, secret: secret, salt: Data(), .eidKey)
            tunnelID = CableV2.derive(16, secret: secret, salt: Data(), .tunnelID)
            let contents = CBOR.map([
                (.int(0), .bytes(identityKey.publicKey.compressedRepresentation)),
                (.int(1), .bytes(secret)),
                (.int(2), .int(CableV2.assignedDomains.count)),
                (.int(3), .int(Int(Date().timeIntervalSince1970))),
                (.int(4), .bool(false)),
                (.int(5), .text(requestType)),
            ]).encoded()
            url = "FIDO:/" + CableV2.digitEncode([UInt8](contents))
        }

        func psk(for advert: Advert) -> Data {
            CableV2.derive(32, secret: secret, salt: advert.plaintext, .psk)
        }

        func qrImage(size: CGFloat) -> CGImage? {
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
            filter.setValue(Data(url.utf8), forKey: "inputMessage")
            filter.setValue("L", forKey: "inputCorrectionLevel")
            guard let output = filter.outputImage else { return nil }
            let scale = max(1, (size / output.extent.width).rounded(.down))
            let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            return CIContext().createCGImage(scaled, from: scaled.extent)
        }
    }

    /// Bytes to decimal digits: each 7-byte little-endian chunk becomes 17
    /// digits; a shorter last chunk uses just enough digits.
    static func digitEncode(_ bytes: [UInt8]) -> String {
        let partialDigits = [0, 3, 5, 8, 10, 13, 15]
        var out = ""
        var index = 0
        while index < bytes.count {
            let chunk = bytes[index..<min(index + 7, bytes.count)]
            var value: UInt64 = 0
            for (offset, byte) in chunk.enumerated() { value |= UInt64(byte) << (8 * UInt64(offset)) }
            let width = chunk.count == 7 ? 17 : partialDigits[chunk.count]
            let digits = String(value)
            out += String(repeating: "0", count: max(0, width - digits.count)) + digits
            index += 7
        }
        return out
    }
}

// MARK: - Noise

/// The Noise handshake caBLE uses: KNpsk0 when the phone learned our
/// identity key from the QR code (Noise_KNpsk0_P256_AESGCM_SHA256).
struct CableHandshake {
    private var chainingKey: Data
    private var hash: Data
    private var key = Data()
    private let ephemeral = P256.KeyAgreement.PrivateKey()
    private let identity: P256.KeyAgreement.PrivateKey

    init(psk: Data, identity: P256.KeyAgreement.PrivateKey) {
        self.identity = identity
        var name = Data("Noise_KNpsk0_P256_AESGCM_SHA256".utf8)
        name += Data(count: 32 - name.count)
        chainingKey = name
        hash = name
        mixHash(Data([1])) // QR prologue
        mixHash(identity.publicKey.x963Representation)
        mixKeyAndHash(psk)
    }

    private mutating func mixHash(_ data: Data) {
        hash = Data(SHA256.hash(data: hash + data))
    }

    private static func hkdf(_ salt: Data, _ ikm: Data, _ count: Int) -> Data {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt, info: Data(), outputByteCount: count)
            .withUnsafeBytes { Data($0) }
    }

    private mutating func mixKey(_ ikm: Data) {
        let out = Self.hkdf(chainingKey, ikm, 64)
        chainingKey = out.prefix(32)
        key = out.suffix(32)
    }

    private mutating func mixKeyAndHash(_ ikm: Data) {
        let out = [UInt8](Self.hkdf(chainingKey, ikm, 96))
        chainingKey = Data(out[0..<32])
        mixHash(Data(out[32..<64]))
        key = Data(out[64..<96])
    }

    private static let zeroNonce = try! AES.GCM.Nonce(data: Data(count: 12))

    /// → e (65 bytes) ‖ tag of an empty payload.
    mutating func initialMessage() throws -> Data {
        let point = ephemeral.publicKey.x963Representation
        mixHash(point)
        mixKey(point)
        let sealed = try AES.GCM.seal(Data(), using: SymmetricKey(data: key), nonce: Self.zeroNonce, authenticating: hash)
        let ciphertext = sealed.ciphertext + sealed.tag
        mixHash(ciphertext)
        return point + ciphertext
    }

    /// ← e, ee, se. Returns the traffic crypter.
    mutating func processResponse(_ response: Data) throws -> CableCrypter {
        guard response.count == 65 + 16 else { throw SecurityKeyTransportError.protocolError("bad handshake response") }
        let point = Data(response.prefix(65))
        let ciphertext = Data(response.suffix(16))
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: point)
        mixHash(point)
        mixKey(point)
        mixKey(try ephemeral.sharedSecretFromKeyAgreement(with: peer).withUnsafeBytes { Data($0) })
        mixKey(try identity.sharedSecretFromKeyAgreement(with: peer).withUnsafeBytes { Data($0) })
        let box = try AES.GCM.SealedBox(nonce: Self.zeroNonce, ciphertext: Data(), tag: ciphertext)
        _ = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: hash)
        mixHash(ciphertext)
        let traffic = Self.hkdf(chainingKey, Data(), 64)
        return CableCrypter(writeKey: traffic.prefix(32), readKey: traffic.suffix(32))
    }
}

/// AES-256-GCM for tunnel messages after the handshake, padded to 32 bytes.
struct CableCrypter {
    private let writeKey: SymmetricKey
    private let readKey: SymmetricKey
    private var writeCounter: UInt32 = 0
    private var readCounter: UInt32 = 0
    /// Learned from the phone's first message, then used both ways.
    private var additionalData = Data([2])
    private var nonceInFront = false
    private var calibrated = false

    init(writeKey: Data, readKey: Data) {
        self.writeKey = SymmetricKey(data: writeKey)
        self.readKey = SymmetricKey(data: readKey)
    }

    private static func nonce(_ counter: UInt32, inFront: Bool) -> AES.GCM.Nonce {
        var bytes = [UInt8](repeating: 0, count: 12)
        let offset = inFront ? 0 : 8
        bytes[offset] = UInt8(counter >> 24)
        bytes[offset + 1] = UInt8((counter >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((counter >> 8) & 0xFF)
        bytes[offset + 3] = UInt8(counter & 0xFF)
        return try! AES.GCM.Nonce(data: bytes)
    }

    mutating func encrypt(_ message: Data) throws -> Data {
        var padded = message
        let size = (message.count + 1 + 31) & ~31
        let zeros = size - message.count - 1
        padded += Data(count: zeros)
        padded.append(UInt8(zeros))
        let sealed = try AES.GCM.seal(padded, using: writeKey, nonce: Self.nonce(writeCounter, inFront: nonceInFront),
                                      authenticating: additionalData)
        writeCounter += 1
        return sealed.ciphertext + sealed.tag
    }

    mutating func decrypt(_ ciphertext: Data) throws -> Data {
        guard ciphertext.count >= 16 else { throw SecurityKeyTransportError.protocolError("short tunnel message") }
        let body = ciphertext.prefix(ciphertext.count - 16)
        let tag = ciphertext.suffix(16)
        let attempts: [(Data, Bool)] = calibrated ? [(additionalData, nonceInFront)]
            : [(Data([2]), false), (Data(), false), (Data([2]), true), (Data(), true)]
        for (aad, inFront) in attempts {
            guard let box = try? AES.GCM.SealedBox(nonce: Self.nonce(readCounter, inFront: inFront), ciphertext: body, tag: tag),
                  var plain = try? AES.GCM.open(box, using: readKey, authenticating: aad) else { continue }
            if !calibrated {
                calibrated = true
                additionalData = aad
                nonceInFront = inFront
            }
            readCounter += 1
            guard let padding = plain.last, Int(padding) + 1 <= plain.count else {
                throw SecurityKeyTransportError.protocolError("bad padding")
            }
            plain.removeLast(Int(padding) + 1)
            return plain
        }
        throw SecurityKeyTransportError.protocolError("tunnel decryption failed")
    }
}
