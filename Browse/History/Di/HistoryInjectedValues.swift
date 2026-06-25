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

    var addNewEntryInHistoryUseCase: Factory<AddNewEntryInHistoryUseCaseProtocol> {
        Factory(self) { AddNewEntryInHistoryUseCase() }
    }

    var deleteHistoryEntryUseCase: Factory<DeleteHistoryEntryUseCaseProtocol> {
        Factory(self) { DeleteHistoryEntryUseCase() }
    }

    var deleteAllHistoryEntryUseCase: Factory<DeleteAllHistoryEntryUseCaseProtocol> {
        Factory(self) { DeleteAllHistoryEntryUseCase() }
    }

    var fetchHistoryWithPredictUseCase: Factory<FetchHistoryWithPredictUseCaseProtocol> {
        Factory(self) { FetchHistoryWithPredictUseCase() }
    }
}
