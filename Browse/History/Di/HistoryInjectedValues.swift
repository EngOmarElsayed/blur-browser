//
//  HistoryInjectedValues.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 23/06/2026.
//

import Foundation
import FactoryKit

extension Container {
    var historyLocalDataStore: Factory<HistoryLocalDataStoreProtocol> {
        Factory(self) { HistoryLocalDataStore() }.singleton
    }

    var historyRepository: Factory<HistoryRepositoryProtocol> {
        Factory(self) { HistoryRepository() }
    }
}
