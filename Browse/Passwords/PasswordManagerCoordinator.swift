import AppKit
import Observation
import WebKit
import os

@MainActor
@Observable
final class PasswordManagerCoordinator: NSObject {
    private let log = Logger(subsystem: "com.browse.app", category: "PasswordManager")
    private let passwordStore: PasswordStore
    private let blocklistStore: BlocklistStore
    weak var webView: WKWebView?

    init(passwordStore: PasswordStore, blocklistStore: BlocklistStore) {
        self.passwordStore = passwordStore
        self.blocklistStore = blocklistStore
        super.init()
    }
}

extension PasswordManagerCoordinator: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        let body = message.body
        Task { @MainActor in
            self.log.info("inbound: \(String(describing: body), privacy: .public)")
        }
    }
}
