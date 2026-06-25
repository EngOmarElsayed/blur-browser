//
//  AppMangers.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 13/06/2026.
//

import Foundation
import FactoryKit

extension Container {
    @MainActor
    var privacyReportStore: Factory<PrivacyReportStore> { // fix this
        Factory(self) { PrivacyReportStore() }.singleton
    }

    var historyStore: Factory<HistoryStore> {
        Factory(self) { HistoryStore() }.singleton
    }

    @MainActor
    var tabManager: Factory<TabManager> {
        Factory(self) { TabManager() }.singleton
    }

    @MainActor
    var downloadStore: Factory<DownloadStore> {
        Factory(self) { DownloadStore() }.singleton
    }

    @MainActor
    var downloadManager: Factory<DownloadManager> {
        Factory(self) { DownloadManager(store: self.downloadStore()) }.singleton
    }

    @MainActor
    var passwordStore: Factory<PasswordStore> {
        Factory(self) { PasswordStore() }.singleton
    }

    @MainActor
    var blocklistStore: Factory<BlocklistStore> {
        Factory(self) { BlocklistStore() }.singleton
    }
}
