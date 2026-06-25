//
//  FetchHistoryWithPredictUseCaseProtocol.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 24/06/2026.
//

import Foundation
import FactoryKit

protocol FetchHistoryWithPredictUseCaseProtocol: Sendable {
    func callAsFunction(where predict: Predicate<BrowserHistoryEntry>?, batchSize: Int) async throws -> [BrowserHistoryEntry]
}

// MARK: -FetchHistoryWithPredictUseCase
struct FetchHistoryWithPredictUseCase {
    @Injected(\.historyRepository) private var historyRepository: HistoryRepositoryProtocol
}

// MARK: -FetchHistoryWithPredictUseCaseProtocol Implementation
extension FetchHistoryWithPredictUseCase: FetchHistoryWithPredictUseCaseProtocol {
    func callAsFunction(where predict: Predicate<BrowserHistoryEntry>?, batchSize: Int) async throws -> [BrowserHistoryEntry] {
        try await historyRepository
            .fetchItems(
                where: predict,
                sortBy: nil,
                order: nil,
                batchSize: batchSize
            )
    }
}
