//
//  DeleteHistoryEntryUseCaseProtocol.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 24/06/2026.
//

import Foundation
import FactoryKit

protocol DeleteHistoryEntryUseCaseProtocol: Sendable {
    func callAsFunction(where predicate: Predicate<BrowserHistoryEntry>) async throws
}

// MARK: -DeleteHistoryEntryUseCase
struct DeleteHistoryEntryUseCase {
    @Injected(\.historyRepository) private var historyRepository: HistoryRepositoryProtocol
}

// MARK: - DeleteHistoryEntryUseCaseProtocol Implementation
extension DeleteHistoryEntryUseCase: DeleteHistoryEntryUseCaseProtocol {
    func callAsFunction(where predicate: Predicate<BrowserHistoryEntry>) async throws {
        try await historyRepository.deleteItems(where: predicate)
    }
}
