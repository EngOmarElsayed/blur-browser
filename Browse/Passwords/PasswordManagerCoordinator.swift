import AppKit
import Observation
import WebKit
import os

@MainActor
@Observable
final class PasswordManagerCoordinator: NSObject {
    enum PendingCredential: Equatable {
        case save(site: String, username: String, password: String)
        case update(site: String, username: String, password: String, existingId: UUID)
    }

    var pendingSaveCredential: PendingCredential?

    /// Drives the 15s timer pause/resume. WebViewController flips this in
    /// `displayTab` (the single WebViewController swaps WKWebViews on tab
    /// switch — there is no per-tab viewWillAppear/Disappear).
    var isTabActive: Bool = true {
        didSet {
            guard oldValue != isTabActive else { return }
            if isTabActive { resumeSaveTimer() } else { pauseSaveTimer() }
        }
    }

    private let log = Logger(subsystem: "com.browse.app", category: "PasswordManager")
    private let passwordStore: PasswordStore
    private let blocklistStore: BlocklistStore
    weak var webView: WKWebView?

    /// unitId -> snapshot. Includes the URL captured at submission time so the
    /// native side can detect navigation-based success even when the JS-side
    /// `loginLikelySucceeded` message gets dropped during frame unload.
    private struct PendingSubmission {
        let classification: FormClassification
        let username: String
        let password: String
        let capturedURL: URL?
        let capturedAt: Date
    }
    private var lastSubmissionByUnit: [String: PendingSubmission] = [:]
    private let submissionTTL: TimeInterval = 10

    private var saveDeadline: Date?
    private var savePauseTime: Date?
    private var saveTimer: Task<Void, Never>?

    init(passwordStore: PasswordStore, blocklistStore: BlocklistStore) {
        self.passwordStore = passwordStore
        self.blocklistStore = blocklistStore
        super.init()
    }

    // MARK: - Pending state hook

    private func setPendingSaveCredential(_ value: PendingCredential?) {
        // didSet equivalent: mutate first, then start/cancel timer.
        let oldValue = pendingSaveCredential
        pendingSaveCredential = value
        guard oldValue != value else { return }
        if value == nil { cancelSaveTimer() } else { startSaveTimer() }
    }

    // MARK: - Inbound dispatch

    private func handle(_ msg: InboundMessage) {
        switch msg {
        case .scriptReady:
            // Don't wipe the map — cross-origin iframe scriptReadys (Stripe, analytics, etc.)
            // would clobber a real main-frame submission. Instead, evict only stale entries
            // and check whether the main webView has navigated since a recent submission.
            evictStaleSubmissions()
            checkForNavigationSuccess()
        case .formsDetected:
            break // Used in Round 5 (autofill).
        case .fieldFocused, .fieldBlurred, .viewportChanged:
            break // Used in Round 5 (autofill).
        case let .formSubmitted(unitId, classification, username, password):
            lastSubmissionByUnit[unitId] = PendingSubmission(
                classification: classification,
                username: username,
                password: password,
                capturedURL: webView?.url,
                capturedAt: Date()
            )
        case .loginLikelySucceeded(let unitId):
            handleSuccess(unitId: unitId)
        case .loginInconclusive(let unitId):
            lastSubmissionByUnit.removeValue(forKey: unitId)
        }
    }

    /// Drop submissions older than `submissionTTL`. Prevents unbounded growth on long-lived tabs.
    private func evictStaleSubmissions() {
        let now = Date()
        let staleKeys = lastSubmissionByUnit.compactMap { (key, entry) in
            now.timeIntervalSince(entry.capturedAt) > submissionTTL ? key : nil
        }
        for key in staleKeys { lastSubmissionByUnit.removeValue(forKey: key) }
    }

    /// Native-side success detector. Called on scriptReady. If a recent submission's
    /// captured URL has a different host or path than the current webView URL, treat
    /// it as a successful login (the user navigated away from the form).
    /// This is the safety net for the common case where the JS-side
    /// `loginLikelySucceeded` was dropped during frame unload.
    private func checkForNavigationSuccess() {
        guard let currentURL = webView?.url else { return }
        for (unitId, entry) in lastSubmissionByUnit {
            guard let captured = entry.capturedURL else { continue }
            if currentURL.host != captured.host || currentURL.path != captured.path {
                handleSuccess(unitId: unitId)
                // handleSuccess removes the entry; loop will keep going for any others.
            }
        }
    }

    private func handleSuccess(unitId: String) {
        guard let payload = lastSubmissionByUnit.removeValue(forKey: unitId) else { return }
        guard let url = webView?.url, let site = SiteIdentity.key(for: url) else { return }
        if blocklistStore.contains(site) { return }

        let existing = passwordStore.lookup(forSite: site)

        // Same username, same password → no-op (already saved, nothing to update).
        if existing.contains(where: { $0.username == payload.username && $0.password == payload.password }) {
            return
        }

        if let match = existing.first(where: { $0.username == payload.username }) {
            setPendingSaveCredential(.update(site: site,
                                             username: payload.username,
                                             password: payload.password,
                                             existingId: match.id))
        } else {
            setPendingSaveCredential(.save(site: site,
                                           username: payload.username,
                                           password: payload.password))
        }
    }

    // MARK: - Public actions (called from the SavePromptView buttons)

    func acceptPending() {
        guard let pending = pendingSaveCredential else { return }
        switch pending {
        case let .save(site, username, password):
            passwordStore.save(Credential(site: site, username: username, password: password))
        case let .update(_, _, password, existingId):
            passwordStore.update(id: existingId, password: password)
        }
        setPendingSaveCredential(nil)
    }

    func acceptPending(editedUsername: String, editedPassword: String) {
        // The SavePromptView allows the user to edit username / password before saving.
        guard let pending = pendingSaveCredential else { return }
        switch pending {
        case let .save(site, _, _):
            passwordStore.save(Credential(site: site, username: editedUsername, password: editedPassword))
        case let .update(_, _, _, existingId):
            // Username changes on update aren't supported in v1 (would create a separate keychain item).
            // Just save the new password.
            passwordStore.update(id: existingId, password: editedPassword)
        }
        setPendingSaveCredential(nil)
    }

    func declineForever() {
        guard let pending = pendingSaveCredential else { return }
        let site: String
        switch pending {
        case let .save(s, _, _): site = s
        case let .update(s, _, _, _): site = s
        }
        blocklistStore.add(site)
        setPendingSaveCredential(nil)
    }

    func dismissPending() {
        setPendingSaveCredential(nil)
    }

    // MARK: - Timer

    private func startSaveTimer() {
        cancelSaveTimer()
        saveDeadline = Date().addingTimeInterval(15)
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        guard let deadline = saveDeadline else { return }
        let interval = deadline.timeIntervalSinceNow
        saveTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, interval)))
            guard !Task.isCancelled, let self else { return }
            if let d = self.saveDeadline, Date() >= d {
                self.pendingSaveCredential = nil
                self.saveDeadline = nil
            }
        }
    }

    private func pauseSaveTimer() {
        guard saveDeadline != nil else { return }
        savePauseTime = Date()
        saveTimer?.cancel()
        saveTimer = nil
    }

    private func resumeSaveTimer() {
        guard let deadline = saveDeadline, let paused = savePauseTime else { return }
        let pausedFor = Date().timeIntervalSince(paused)
        saveDeadline = deadline.addingTimeInterval(pausedFor)
        savePauseTime = nil
        scheduleExpiry()
    }

    private func cancelSaveTimer() {
        saveTimer?.cancel()
        saveTimer = nil
        saveDeadline = nil
        savePauseTime = nil
    }
}

extension PasswordManagerCoordinator: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        guard let msg = try? JSONDecoder().decode(InboundMessage.self, from: data) else {
            Task { @MainActor in self.log.warning("undecodable message: \(String(describing: body), privacy: .public)") }
            return
        }
        Task { @MainActor in self.handle(msg) }
    }
}
