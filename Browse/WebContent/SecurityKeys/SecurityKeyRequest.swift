import AppKit
import CryptoKit
import Foundation

/// An error the user should read in the sheet before the page hears about it.
struct SecurityKeyFailure: Error {
    let title: String
    let message: String
    var pageError = WebAuthnError.notAllowed()
}

/// One navigator.credentials.create()/get() call driven against a USB
/// security key: find the key, verify the user if needed, run the CTAP2
/// command, and build the PublicKeyCredential the shim hands back.
@MainActor
final class SecurityKeyRequest {
    private enum UVPlan {
        case none
        case builtIn
        case token(PINToken)
    }

    let origin: WebOrigin
    let topOrigin: WebOrigin?
    let sheet = SecurityKeySheet()
    private let discovery = SecurityKeyDiscovery()
    private var site = ""
    private var showingTouch = false
    private var scanner: CableAdvertScanner?
    private var tunnel: CableTunnel?
    private(set) var usingPhone = false

    init(origin: WebOrigin, topOrigin: WebOrigin?) {
        self.origin = origin
        self.topOrigin = topOrigin
    }

    func finish() {
        scanner?.stop()
        tunnel?.close()
        discovery.stop()
        sheet.dismiss()
    }

    // MARK: - create()

    func create(_ options: CreationOptions, hasUserActivation: Bool) async throws -> [String: Any] {
        let rpId = (options.rpId ?? origin.host).lowercased()
        try origin.validateRPID(rpId)
        if options.attachment == "platform" {
            throw WebAuthnError.notAllowed("This browser has no platform authenticator.")
        }
        site = rpId
        try await confirmIfNeeded(hasUserActivation, verb: "create a passkey on your security key for")

        let clientDataJSON = ClientData.json(type: "webauthn.create", challenge: options.challenge, origin: origin, topOrigin: topOrigin)
        let clientDataHash = Data(SHA256.hash(data: clientDataJSON))
        let auth = try await connect(requestType: "mc", purpose: "create a passkey for \(site)")
        let info = auth.info

        let rk: Bool
        switch options.residentKey {
        case "required":
            guard info.supportsResidentKeys else {
                throw SecurityKeyFailure(title: "This security key can't store passkeys",
                                         message: "\(site) needs a passkey stored on the key itself. Try a newer security key.")
            }
            rk = true
        case "preferred": rk = info.supportsResidentKeys && info.canVerifyUser
        default: rk = false
        }

        var extensions: [(CBOR, CBOR)] = []
        let credProtect = options.credProtect ?? (rk ? 2 : nil)
        if let credProtect, credProtect > 1 {
            if info.extensions.contains("credProtect") {
                extensions.append((.text("credProtect"), .int(credProtect)))
            } else if options.enforceCredProtect, options.credProtect != nil {
                throw SecurityKeyFailure(title: "This security key isn't supported",
                                         message: "\(site) needs a feature (credential protection) this key doesn't have.")
            }
        }

        let excluded = auth.isHybrid ? nil : try await matchingCredential(auth, rpId: rpId, clientDataHash: clientDataHash,
                                                    credentials: options.excludeCredentials)
        let excludeList: [CredentialDescriptor]
        if let excluded {
            excludeList = [CredentialDescriptor(id: excluded, transports: [])]
        } else if options.excludeCredentials.count <= (info.maxCredentialCountInList ?? .max) {
            excludeList = options.excludeCredentials
        } else {
            excludeList = []
        }

        let wantsUV = options.userVerification == .required
            || (options.userVerification == .preferred && info.canVerifyUser)
            || (rk && info.canVerifyUser)
            || (info.clientPin == true && !info.makeCredUvNotRequired)
        var plan = try await verifyUser(auth, wanted: wantsUV, required: options.userVerification == .required || (rk && options.residentKey == "required"),
                                        permissions: CTAP2Authenticator.Permission.makeCredential, rpId: rpId)

        var response: CBOR?
        for attempt in 0..<2 {
            var params: [(CBOR, CBOR)] = [
                (.int(1), .bytes(clientDataHash)),
                (.int(2), .map([(.text("id"), .text(rpId))] + (options.rpName.isEmpty ? [] : [(.text("name"), .text(options.rpName))]))),
                (.int(3), .map([
                    (.text("id"), .bytes(options.userId)),
                    (.text("name"), .text(options.userName)),
                    (.text("displayName"), .text(options.userDisplayName)),
                ])),
                (.int(4), .array(options.algorithms.map { .map([(.text("alg"), .int($0)), (.text("type"), .text("public-key"))]) })),
            ]
            if !excludeList.isEmpty { params.append((.int(5), .array(excludeList.map(\.cbor)))) }
            if !extensions.isEmpty { params.append((.int(6), .map(extensions))) }
            var flags: [(CBOR, CBOR)] = []
            if rk { flags.append((.text("rk"), .bool(true))) }
            if case .builtIn = plan { flags.append((.text("uv"), .bool(true))) }
            if !flags.isEmpty { params.append((.int(7), .map(flags))) }
            if case .token(let token) = plan {
                params.append((.int(8), .bytes(token.authenticate(clientDataHash))))
                params.append((.int(9), .int(token.pinProtocol.version)))
            }
            promptTouch("Touch your security key", "to create a passkey for \(site).")
            do {
                response = try await auth.command(.makeCredential, .map(params))
                break
            } catch let error as CTAP2Error where attempt == 0
                        && [CTAP2Status.puatRequired, CTAP2Status.pinAuthInvalid].contains(error.status) && info.canVerifyUser {
                plan = try await verifyUser(auth, wanted: true, required: true,
                                            permissions: CTAP2Authenticator.Permission.makeCredential, rpId: rpId)
            } catch let error as CTAP2Error {
                throw failure(for: error, creating: true)
            }
        }
        guard let response, let fmt = response[1]?.textValue, let authDataBytes = response[2]?.bytesValue,
              let attStmt = response[3] else {
            throw SecurityKeyTransportError.protocolError("bad makeCredential response")
        }

        let authData = AuthenticatorData(authDataBytes)
        let bytes = [UInt8](authDataBytes)
        guard bytes.count > 55 else { throw SecurityKeyTransportError.protocolError("short authData") }
        let idLength = Int(bytes[53]) << 8 | Int(bytes[54])
        guard bytes.count >= 55 + idLength else { throw SecurityKeyTransportError.protocolError("short authData") }
        let credentialId = Data(bytes[55..<55 + idLength])

        let keepAttestation = ["direct", "indirect", "enterprise"].contains(options.attestation)
        let attestationObject = CBOR.map([
            (.text("fmt"), .text(keepAttestation ? fmt : "none")),
            (.text("attStmt"), keepAttestation ? attStmt : .map([])),
            (.text("authData"), .bytes(authDataBytes)),
        ]).encoded()

        var extensionResults: [String: Any] = [:]
        if options.credProps { extensionResults["credProps"] = ["rk": rk] }

        var result: [String: Any] = [
            "id": credentialId.base64URLEncodedString(),
            "rawId": credentialId.base64URLEncodedString(),
            "type": "public-key",
            "authenticatorAttachment": "cross-platform",
            "clientExtensionResults": extensionResults,
        ]
        var responseFields: [String: Any] = [
            "clientDataJSON": clientDataJSON.base64URLEncodedString(),
            "attestationObject": attestationObject.base64URLEncodedString(),
            "authenticatorData": authDataBytes.base64URLEncodedString(),
            "transports": auth.isHybrid ? ["hybrid", "internal"] : transports(info),
        ]
        if let key = authData.credentialPublicKey {
            responseFields["publicKeyAlgorithm"] = key[3]?.intValue ?? 0
            if let spki = COSEKey.spki(key) { responseFields["publicKey"] = spki.base64URLEncodedString() }
        }
        result["response"] = responseFields
        return result
    }

    // MARK: - get()

    func get(_ options: RequestOptions, hasUserActivation: Bool) async throws -> [String: Any] {
        let rpId = (options.rpId ?? origin.host).lowercased()
        try origin.validateRPID(rpId)
        let appid = try options.appid.map { try origin.validateAppID($0) }
        site = rpId
        try await confirmIfNeeded(hasUserActivation, verb: "sign in with your security key to")

        let clientDataJSON = ClientData.json(type: "webauthn.get", challenge: options.challenge, origin: origin, topOrigin: topOrigin)
        let clientDataHash = Data(SHA256.hash(data: clientDataJSON))
        let auth = try await connect(requestType: "ga", purpose: "sign in to \(site)")
        let info = auth.info

        var allowList = options.allowCredentials
        if let maxLength = info.maxCredentialIdLength {
            allowList = allowList.filter { $0.id.count <= maxLength }
            if allowList.isEmpty, !options.allowCredentials.isEmpty {
                throw notRegistered()
            }
        }

        // Work out which rpId (the real one, or the U2F appid) holds one of the
        // allowed credentials, without a touch, before asking for a PIN.
        var effectiveRpId = rpId
        var usedAppID = false
        // A phone shows UI for every request, so it isn't probed.
        if !auth.isHybrid, !allowList.isEmpty, appid != nil || allowList.count > (info.maxCredentialCountInList ?? .max) {
            var found: Data?
            for candidate in [rpId] + (appid.map { [$0] } ?? []) {
                found = try await matchingCredential(auth, rpId: candidate, clientDataHash: clientDataHash, credentials: allowList)
                if let found {
                    effectiveRpId = candidate
                    usedAppID = candidate != rpId
                    allowList = [CredentialDescriptor(id: found, transports: [])]
                    break
                }
            }
            if found == nil {
                allowList = Array(allowList.prefix(info.maxCredentialCountInList ?? allowList.count))
            }
        }

        let wantsUV = options.userVerification == .required
            || (options.userVerification == .preferred && info.canVerifyUser)
            || (allowList.isEmpty && info.canVerifyUser)
        var plan = try await verifyUser(auth, wanted: wantsUV, required: options.userVerification == .required,
                                        permissions: CTAP2Authenticator.Permission.getAssertion, rpId: effectiveRpId)

        var response: CBOR?
        for attempt in 0..<2 {
            var params: [(CBOR, CBOR)] = [
                (.int(1), .text(effectiveRpId)),
                (.int(2), .bytes(clientDataHash)),
            ]
            if !allowList.isEmpty { params.append((.int(3), .array(allowList.map(\.cbor)))) }
            if case .builtIn = plan { params.append((.int(5), .map([(.text("uv"), .bool(true))]))) }
            if case .token(let token) = plan {
                params.append((.int(6), .bytes(token.authenticate(clientDataHash))))
                params.append((.int(7), .int(token.pinProtocol.version)))
            }
            promptTouch("Touch your security key", "to sign in to \(site).")
            do {
                response = try await auth.command(.getAssertion, .map(params))
                break
            } catch let error as CTAP2Error where attempt == 0
                        && [CTAP2Status.puatRequired, CTAP2Status.pinAuthInvalid].contains(error.status) && info.canVerifyUser {
                plan = try await verifyUser(auth, wanted: true, required: true,
                                            permissions: CTAP2Authenticator.Permission.getAssertion, rpId: effectiveRpId)
            } catch let error as CTAP2Error {
                throw failure(for: error, creating: false)
            }
        }
        guard var assertion = response else { throw SecurityKeyTransportError.protocolError("empty getAssertion") }

        // Several discoverable credentials: let the user pick an account.
        if let count = assertion[5]?.intValue, count > 1 {
            var assertions = [assertion]
            for _ in 1..<count {
                if let next = try await auth.command(.getNextAssertion) { assertions.append(next) }
            }
            let names = assertions.enumerated().map { index, a -> String in
                let user = a[4]
                let name = user?["name"]?.textValue ?? ""
                let display = user?["displayName"]?.textValue ?? ""
                if !display.isEmpty, !name.isEmpty, display != name { return "\(display) (\(name))" }
                return !name.isEmpty ? name : !display.isEmpty ? display : "Account \(index + 1)"
            }
            guard let choice = await sheet.chooseAccount("Choose an account", "Your security key has more than one passkey for \(site).", accounts: names) else {
                throw CancellationError()
            }
            assertion = assertions[choice]
        }

        guard let authenticatorData = assertion[2]?.bytesValue, let signature = assertion[3]?.bytesValue,
              let credentialId = assertion[1]?["id"]?.bytesValue ?? (allowList.count == 1 ? allowList[0].id : nil) else {
            throw SecurityKeyTransportError.protocolError("bad getAssertion response")
        }

        var extensionResults: [String: Any] = [:]
        if appid != nil { extensionResults["appid"] = usedAppID }
        var responseFields: [String: Any] = [
            "clientDataJSON": clientDataJSON.base64URLEncodedString(),
            "authenticatorData": authenticatorData.base64URLEncodedString(),
            "signature": signature.base64URLEncodedString(),
        ]
        if let userHandle = assertion[4]?["id"]?.bytesValue {
            responseFields["userHandle"] = userHandle.base64URLEncodedString()
        }
        return [
            "id": credentialId.base64URLEncodedString(),
            "rawId": credentialId.base64URLEncodedString(),
            "type": "public-key",
            "authenticatorAttachment": "cross-platform",
            "clientExtensionResults": extensionResults,
            "response": responseFields,
        ]
    }

    // MARK: - Steps

    /// Without a recent click or key press, ask before touching the key, so a
    /// page can't pop the sheet on its own.
    private func confirmIfNeeded(_ hasUserActivation: Bool, verb: String) async throws {
        guard !hasUserActivation else { return }
        let ok = await sheet.confirm("Use a security key?", "\(origin.host) wants to \(verb) \(site).", button: "Continue")
        guard ok else { throw CancellationError() }
    }

    private enum Found {
        case securityKey
        case phone(CableV2.Advert)
    }

    /// Shows the QR code for a phone and waits for either the phone's BLE
    /// advert or a security key on USB, whichever comes first.
    private func connect(requestType: String, purpose: String) async throws -> CTAP2Authenticator {
        let qr = CableV2.QRSession(requestType: requestType)
        sheet.showChooser("Use your phone or a security key",
                          "Scan this code with your iPhone or Android camera to \(purpose), or insert your security key.",
                          qr: qr.qrImage(size: 360))
        discovery.start()
        let scanner = CableAdvertScanner(eidKey: qr.eidKey)
        self.scanner = scanner
        let (events, continuation) = AsyncStream<Found>.makeStream()
        scanner.onAdvert = { continuation.yield(.phone($0)) }
        scanner.onStatus = { [weak self] status in
            switch status {
            case .poweredOff: self?.sheet.setNote("Turn on Bluetooth to use your phone.")
            case .unauthorized: self?.sheet.setNote("Allow Blur-Browser to use Bluetooth in System Settings › Privacy & Security › Bluetooth to use your phone.")
            case .unsupported: self?.sheet.setNote("This Mac has no Bluetooth, so only security keys work.")
            default: self?.sheet.setNote(nil)
            }
        }
        scanner.start()
        let discovery = self.discovery
        let usbWatcher = Task { @MainActor in
            for await _ in discovery.changes() where !discovery.devices.isEmpty {
                continuation.yield(.securityKey)
                break
            }
        }
        var found: Found?
        for await event in events {
            found = event
            break
        }
        usbWatcher.cancel()
        continuation.finish()
        scanner.stop()
        try Task.checkCancellation()

        switch found {
        case .phone(let advert)?:
            discovery.stop()
            usingPhone = true
            sheet.showStatus("Connecting to your phone…", "Keep your phone nearby with its screen on.")
            let tunnel = CableTunnel()
            self.tunnel = tunnel
            do {
                try await tunnel.open(qr: qr, advert: advert)
            } catch where !Task.isCancelled {
                securityKeyLogger.error("caBLE: tunnel failed: \(String(describing: error), privacy: .public)")
                throw SecurityKeyFailure(title: "Couldn't connect to your phone",
                                         message: "Check that your phone is online and try again.")
            }
            let auth = CTAP2Authenticator(tunnel: tunnel, info: tunnel.info)
            if tunnel.info == nil { try await auth.loadInfo() }
            return auth
        case .securityKey?:
            return try await connectSecurityKey()
        case nil:
            throw CancellationError()
        }
    }

    /// Picks a USB key by touch if several are plugged in, and reads its
    /// getInfo.
    private func connectSecurityKey() async throws -> CTAP2Authenticator {
        sheet.showStatus("Connecting to your security key…", "")
        let devices = discovery.devices
        guard !devices.isEmpty else { throw CancellationError() }

        var device = devices[0]
        if devices.count > 1 {
            sheet.showStatus("Touch the security key you want to use", "More than one key is plugged in.")
            let winner = await withTaskGroup(of: Int?.self) { group -> Int? in
                for index in devices.indices {
                    let candidate = devices[index]
                    group.addTask { await Self.touched(candidate) ? index : nil }
                }
                var winner: Int?
                for await result in group {
                    if let result { winner = result; break }
                }
                group.cancelAll()
                return winner
            }
            try Task.checkCancellation()
            guard let winner else { throw WebAuthnError.notAllowed() }
            device = devices[winner]
        }

        guard device.supportsCBOR else {
            throw SecurityKeyFailure(title: "This security key isn't supported",
                                     message: "\(device.productName) only supports the older U2F protocol. Blur-Browser needs a FIDO2 security key.")
        }
        let auth = CTAP2Authenticator(device: device)
        auth.onKeepalive = { [weak self] status in
            if status == 2 { self?.promptTouch("Touch your security key", "") }
        }
        try await auth.loadInfo()
        guard auth.info.isCTAP2 else {
            throw SecurityKeyFailure(title: "This security key isn't supported",
                                     message: "\(device.productName) only supports the older U2F protocol. Blur-Browser needs a FIDO2 security key.")
        }
        return auth
    }

    private static func touched(_ device: CTAPHIDDevice) async -> Bool {
        let probe = CTAP2Authenticator(device: device)
        do {
            try await probe.loadInfo()
            try await probe.waitForTouch()
            return true
        } catch {
            return false
        }
    }

    private func promptTouch(_ title: String, _ detail: String) {
        guard !showingTouch || !detail.isEmpty else { return }
        showingTouch = true
        if usingPhone {
            sheet.showStatus("Continue on your phone", "Follow the steps on your phone to finish with \(site).")
            return
        }
        sheet.showStatus(title, detail.isEmpty ? "Your security key is waiting for a touch." : detail)
    }

    /// Finds which credential in `credentials` lives on this key for `rpId`,
    /// in batches the key accepts, with up=false so no touch is needed.
    private func matchingCredential(_ auth: CTAP2Authenticator, rpId: String, clientDataHash: Data,
                                    credentials: [CredentialDescriptor]) async throws -> Data? {
        guard !credentials.isEmpty else { return nil }
        let batchSize = max(1, auth.info.maxCredentialCountInList ?? credentials.count)
        for start in stride(from: 0, to: credentials.count, by: batchSize) {
            let batch = Array(credentials[start..<min(start + batchSize, credentials.count)])
            let params = CBOR.map([
                (.int(1), .text(rpId)),
                (.int(2), .bytes(clientDataHash)),
                (.int(3), .array(batch.map(\.cbor))),
                (.int(5), .map([(.text("up"), .bool(false))])),
            ])
            do {
                let response = try await auth.command(.getAssertion, params)
                return response?[1]?["id"]?.bytesValue ?? (batch.count == 1 ? batch[0].id : nil)
            } catch let error as CTAP2Error where error.status == CTAP2Status.noCredentials {
                continue
            } catch is CTAP2Error {
                // Keys that refuse up=false: give up on probing.
                return nil
            }
        }
        return nil
    }

    /// Gets the user verified, by fingerprint or PIN, when the request or the
    /// key calls for it.
    private func verifyUser(_ auth: CTAP2Authenticator, wanted: Bool, required: Bool,
                            permissions: UInt8, rpId: String) async throws -> UVPlan {
        let info = auth.info
        guard wanted else { return .none }
        if info.hasBuiltInUV {
            guard info.supportsPinUvAuthToken else { return .builtIn }
            sheet.showStatus("Verify with your fingerprint", "Touch the fingerprint sensor on your security key.")
            showingTouch = false
            do {
                return .token(try await auth.uvToken(permissions: permissions, rpId: rpId))
            } catch let error as CTAP2Error where info.clientPin == true
                        && [CTAP2Status.uvInvalid, CTAP2Status.uvBlocked, CTAP2Status.operationDenied].contains(error.status) {
                // Fall through to the PIN.
            }
        }
        switch info.clientPin {
        case true?:
            return .token(try await askForPIN(auth, permissions: permissions, rpId: rpId))
        case false?:
            guard required else { return .none }
            guard let pin = await sheet.askPIN("Create a PIN for your security key",
                                                "\(site) needs your security key to have a PIN. Use at least 4 characters.",
                                                error: nil, creating: true) else { throw CancellationError() }
            showingTouch = false
            sheet.showStatus("Setting the PIN…", "")
            do {
                try await auth.setPIN(pin)
            } catch let error as CTAP2Error where error.status == CTAP2Status.pinPolicyViolation {
                throw SecurityKeyFailure(title: "That PIN can't be used", message: "Your security key needs a longer or different PIN.")
            }
            return .token(try await auth.pinToken(pin: pin, permissions: permissions, rpId: rpId))
        case nil:
            guard required else { return .none }
            throw SecurityKeyFailure(title: "This security key can't verify you",
                                     message: "\(site) needs a key that supports a PIN or fingerprint.")
        }
    }

    private func askForPIN(_ auth: CTAP2Authenticator, permissions: UInt8, rpId: String) async throws -> PINToken {
        var error: String?
        let retries = try? await auth.pinRetries()
        if let retries, retries <= 3 { error = "\(retries) attempt\(retries == 1 ? "" : "s") left before the key locks." }
        while true {
            guard let pin = await sheet.askPIN("Enter your security key PIN", "\(site) wants to verify it's you.",
                                                error: error, creating: false) else {
                throw CancellationError()
            }
            showingTouch = false
            if pin.count < 4 {
                error = "The PIN has at least 4 characters."
                continue
            }
            sheet.showStatus("Checking your PIN…", "")
            do {
                return try await auth.pinToken(pin: pin, permissions: permissions, rpId: rpId)
            } catch let ctapError as CTAP2Error {
                switch ctapError.status {
                case CTAP2Status.pinInvalid:
                    let left = try? await auth.pinRetries()
                    error = "Wrong PIN." + (left.map { " \($0) attempt\($0 == 1 ? "" : "s") left." } ?? "")
                case CTAP2Status.pinBlocked:
                    throw SecurityKeyFailure(title: "Your security key is locked",
                                             message: "The wrong PIN was entered too many times. Reset the key to use it again.")
                case CTAP2Status.pinAuthBlocked:
                    throw SecurityKeyFailure(title: "Too many wrong PINs",
                                             message: "Remove your security key, plug it back in, and try again.")
                default:
                    throw ctapError
                }
            }
        }
    }

    private func notRegistered() -> SecurityKeyFailure {
        if usingPhone {
            return SecurityKeyFailure(title: "No passkey on your phone", message: "Your phone has no passkey for \(site).")
        }
        return SecurityKeyFailure(title: "This security key isn't registered", message: "It has no passkey for \(site). Try a different key.")
    }

    private func failure(for error: CTAP2Error, creating: Bool) -> Error {
        switch error.status {
        case CTAP2Status.credentialExcluded:
            return SecurityKeyFailure(title: "This security key is already registered",
                                      message: "You've already set up this key with \(site).", pageError: .invalidState)
        case CTAP2Status.noCredentials:
            return notRegistered()
        case CTAP2Status.unsupportedAlgorithm:
            return SecurityKeyFailure(title: "This security key isn't supported",
                                      message: "It doesn't support the kind of key \(site) asks for.",
                                      pageError: .notSupported("The authenticator doesn't support the requested algorithms."))
        case CTAP2Status.keyStoreFull:
            return SecurityKeyFailure(title: "Your security key is full", message: "Remove a passkey from it to make room.")
        case CTAP2Status.userActionTimeout:
            return SecurityKeyFailure(title: "The security key timed out", message: "It wasn't touched in time. Try again.")
        case CTAP2Status.pinBlocked:
            return SecurityKeyFailure(title: "Your security key is locked",
                                      message: "The wrong PIN was entered too many times. Reset the key to use it again.")
        case CTAP2Status.operationDenied, CTAP2Status.notAllowed:
            return WebAuthnError.notAllowed()
        default:
            return SecurityKeyFailure(title: "Something went wrong",
                                      message: "Your security key reported an error (\(String(format: "0x%02X", error.status))). Try again.")
        }
    }

    private func transports(_ info: AuthenticatorInfo) -> [String] {
        let known = info.transports.filter { ["usb", "nfc", "ble", "hybrid", "internal"].contains($0) }
        return known.isEmpty ? ["usb"] : Array(Set(known + ["usb"])).sorted()
    }
}
