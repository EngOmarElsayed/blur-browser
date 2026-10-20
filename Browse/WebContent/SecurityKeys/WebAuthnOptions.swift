import Foundation

/// PublicKeyCredentialCreationOptions / RequestOptions as the shim sends
/// them: binary fields arrive base64url-encoded.

struct CredentialDescriptor {
    let id: Data
    let transports: [String]

    static func list(_ value: Any?) -> [CredentialDescriptor] {
        (value as? [[String: Any]] ?? []).compactMap { entry in
            guard (entry["type"] as? String ?? "public-key") == "public-key",
                  let idString = entry["id"] as? String,
                  let id = Data(base64URLEncoded: idString) else { return nil }
            return CredentialDescriptor(id: id, transports: entry["transports"] as? [String] ?? [])
        }
    }

    var cbor: CBOR { .map([(.text("id"), .bytes(id)), (.text("type"), .text("public-key"))]) }
}

enum UserVerification: String {
    case required, preferred, discouraged

    init(_ value: Any?) {
        self = (value as? String).flatMap(UserVerification.init(rawValue:)) ?? .preferred
    }
}

/// Timeout in seconds: the page's hint clamped to a sane range, five minutes
/// by default (what Chrome uses).
private func clampedTimeout(_ value: Any?) -> Double {
    guard let ms = (value as? NSNumber)?.doubleValue, ms > 0 else { return 300 }
    return min(max(ms / 1000, 15), 600)
}

private func requireData(_ value: Any?, _ name: String) throws -> Data {
    guard let string = value as? String, let data = Data(base64URLEncoded: string) else {
        throw WebAuthnError.type("\(name) is required.")
    }
    return data
}

struct CreationOptions {
    let rpId: String?
    let rpName: String
    let userId: Data
    let userName: String
    let userDisplayName: String
    let challenge: Data
    let algorithms: [Int]
    let timeout: Double
    let excludeCredentials: [CredentialDescriptor]
    let attachment: String?
    let residentKey: String
    let userVerification: UserVerification
    let attestation: String
    let credProps: Bool
    let credProtect: Int?
    let enforceCredProtect: Bool

    init(_ options: [String: Any]) throws {
        guard let rp = options["rp"] as? [String: Any] else { throw WebAuthnError.type("rp is required.") }
        guard let user = options["user"] as? [String: Any] else { throw WebAuthnError.type("user is required.") }
        rpId = rp["id"] as? String
        rpName = rp["name"] as? String ?? ""
        userId = try requireData(user["id"], "user.id")
        guard (1...64).contains(userId.count) else { throw WebAuthnError.type("user.id must be between 1 and 64 bytes.") }
        userName = user["name"] as? String ?? ""
        userDisplayName = user["displayName"] as? String ?? ""
        challenge = try requireData(options["challenge"], "challenge")

        let params = options["pubKeyCredParams"] as? [[String: Any]] ?? []
        let algs = params.compactMap { p -> Int? in
            (p["type"] as? String) == "public-key" ? (p["alg"] as? NSNumber)?.intValue : nil
        }
        if !params.isEmpty, algs.isEmpty {
            throw WebAuthnError.notSupported("None of the requested algorithms are supported.")
        }
        algorithms = algs.isEmpty ? [-7, -257] : algs
        timeout = clampedTimeout(options["timeout"])
        excludeCredentials = CredentialDescriptor.list(options["excludeCredentials"])

        let selection = options["authenticatorSelection"] as? [String: Any] ?? [:]
        attachment = selection["authenticatorAttachment"] as? String
        if let rk = selection["residentKey"] as? String, ["required", "preferred", "discouraged"].contains(rk) {
            residentKey = rk
        } else {
            residentKey = (selection["requireResidentKey"] as? Bool) == true ? "required" : "discouraged"
        }
        userVerification = UserVerification(selection["userVerification"])
        attestation = options["attestation"] as? String ?? "none"

        let extensions = options["extensions"] as? [String: Any] ?? [:]
        credProps = (extensions["credProps"] as? Bool) == true
        switch extensions["credentialProtectionPolicy"] as? String {
        case "userVerificationOptional": credProtect = 1
        case "userVerificationOptionalWithCredentialIDList": credProtect = 2
        case "userVerificationRequired": credProtect = 3
        default: credProtect = nil
        }
        enforceCredProtect = (extensions["enforceCredentialProtectionPolicy"] as? Bool) == true
    }
}

struct RequestOptions {
    let rpId: String?
    let challenge: Data
    let timeout: Double
    let allowCredentials: [CredentialDescriptor]
    let userVerification: UserVerification
    let appid: String?

    init(_ options: [String: Any]) throws {
        rpId = options["rpId"] as? String
        challenge = try requireData(options["challenge"], "challenge")
        timeout = clampedTimeout(options["timeout"])
        allowCredentials = CredentialDescriptor.list(options["allowCredentials"])
        userVerification = UserVerification(options["userVerification"])
        let extensions = options["extensions"] as? [String: Any] ?? [:]
        appid = extensions["appid"] as? String
    }
}

// MARK: - Results

/// Converts a COSE public key into DER SubjectPublicKeyInfo, which
/// `AuthenticatorAttestationResponse.getPublicKey()` returns.
enum COSEKey {
    static func spki(_ key: CBOR) -> Data? {
        switch (key[1]?.intValue, key[3]?.intValue) {
        case (2, -7):
            guard key[-1]?.intValue == 1, let x = key[-2]?.bytesValue, let y = key[-3]?.bytesValue,
                  x.count == 32, y.count == 32 else { return nil }
            let prefix: [UInt8] = [0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
                                   0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00, 0x04]
            return Data(prefix) + x + y
        case (1, -8):
            guard key[-1]?.intValue == 6, let x = key[-2]?.bytesValue, x.count == 32 else { return nil }
            return Data([0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x03, 0x21, 0x00]) + x
        case (3, -257):
            guard let n = key[-1]?.bytesValue, let e = key[-2]?.bytesValue else { return nil }
            let rsaKey = der(0x30, derInteger(n) + derInteger(e))
            let algorithm = der(0x30, Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]))
            return der(0x30, algorithm + der(0x03, Data([0x00]) + rsaKey))
        default:
            return nil
        }
    }

    private static func derInteger(_ bytes: Data) -> Data {
        var value = Data(bytes.drop(while: { $0 == 0 }))
        if value.isEmpty || value.first! & 0x80 != 0 { value.insert(0, at: 0) }
        return der(0x02, value)
    }

    private static func der(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        let n = content.count
        if n < 0x80 {
            out.append(UInt8(n))
        } else if n <= 0xFF {
            out += [0x81, UInt8(n)]
        } else {
            out += [0x82, UInt8(n >> 8), UInt8(n & 0xFF)]
        }
        return out + content
    }
}

/// Pieces of authenticatorData (§6.1) the client needs.
struct AuthenticatorData {
    let raw: Data
    let credentialPublicKey: CBOR?

    init(_ raw: Data) {
        self.raw = raw
        var key: CBOR?
        let bytes = [UInt8](raw)
        if bytes.count > 55, bytes[32] & 0x40 != 0 {
            let idLength = Int(bytes[53]) << 8 | Int(bytes[54])
            let keyStart = 55 + idLength
            if keyStart < bytes.count {
                key = try? CBOR.decode(Data(bytes[keyStart...])).0
            }
        }
        credentialPublicKey = key
    }
}
