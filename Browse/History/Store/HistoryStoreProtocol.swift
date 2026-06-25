//
//  HistoryStoreProtocol.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 13/06/2026.
//

import Foundation

protocol HistoryStoreProtocol {
    func distinctHostsCount(since date: Date) -> Int
    func distinctHosts(since date: Date) -> Set<String>
}
