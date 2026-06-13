//
//  HistoryStoreProtocol.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 13/06/2026.
//

import Foundation

protocol HistoryStoreProtocol {
    func addEntry(url: URL, title: String, faviconURL: String?)
    func deleteEntry(_ entry: HistoryEntry)
    func clearHistory(olderThan date: Date?)
    func search(query: String) -> [HistoryEntry]

    func distinctHostsCount(since date: Date) -> Int
    func distinctHosts(since date: Date) -> Set<String>
}
