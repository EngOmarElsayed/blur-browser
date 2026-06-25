//
//  DeleteAllHistoryEntryUseCaseProtocol.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 24/06/2026.
//

import Foundation
import FactoryKit

protocol DeleteAllHistoryEntryUseCaseProtocol: Sendable {
    func callAsFunction() async throws
}

// MARK: -AddNewEntryInHistoryUseCase
struct DeleteAllHistoryEntryUseCase {
    @Injected(\.historyRepository) private var historyRepository: HistoryRepositoryProtocol
}

// MARK: - AddNewEntryInHistoryUseCaseProtocol Implementation
extension DeleteAllHistoryEntryUseCase: DeleteAllHistoryEntryUseCaseProtocol {
    func callAsFunction() async throws {
        try await historyRepository.deleteAllItems()
    }
}
