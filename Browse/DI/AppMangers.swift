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

    var historyStore: Factory<HistoryStoreProtocol> {
        Factory(self) { HistoryStore() }
    }
}
