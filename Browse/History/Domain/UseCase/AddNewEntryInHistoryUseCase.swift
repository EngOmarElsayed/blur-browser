//
//  AddNewEntryInHistoryUseCase.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 24/06/2026.
//

import Foundation
import FactoryKit

protocol AddNewEntryInHistoryUseCaseProtocol: Sendable {
    func callAsFunction(title: String, url: URL, faviconUrl: URL?) async throws
}

// MARK: -AddNewEntryInHistoryUseCase
struct AddNewEntryInHistoryUseCase {
    @Injected(\.historyRepository) private var historyRepository: HistoryRepositoryProtocol
}

// MARK: - AddNewEntryInHistoryUseCaseProtocol Implementation
extension AddNewEntryInHistoryUseCase: AddNewEntryInHistoryUseCaseProtocol {
    func callAsFunction(title: String, url: URL, faviconUrl: URL?) async throws {
        try await historyRepository.addItem(title: title, url: url, faviconUrl: faviconUrl)
    }
}
