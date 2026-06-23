//
//  HistoryInjectedValues.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 23/06/2026.
//

import Foundation
import FactoryKit

extension Container {
    @HistoryLocalDataStoreActor
    var historyLocalDataStore: Factory<HistoryLocalDataStoreProtocol> {
        Factory(self) { HistoryLocalDataStore.shared }
    }
}
