//
//  QuickSearchResultType.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 25/06/2026.
//

import Foundation

enum QuickSearchResultType: String, CaseIterable {
    case openTab = "Switch to Tab"
    case history = "History"
    case suggestion = "Search Suggestions"

    var icon: String {
        switch self {
        case .openTab:
            return "square.stack"
        case .history:
            return "clock"
        case .suggestion:
            return "magnifyingglass"
        }
    }
}
