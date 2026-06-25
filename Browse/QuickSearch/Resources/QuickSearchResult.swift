//
//  QuickSearchResult.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 25/06/2026.
//

import Foundation

struct QuickSearchResult: Identifiable {
    let id = UUID()
    let type: QuickSearchResultType
    let title: String
    let subtitle: String
    let icon: String
    var tabID: UUID?

    init(type: QuickSearchResultType, title: String, subtitle: String, tabID: UUID? = nil) {
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.icon = type.icon
        self.tabID = tabID
    }
}
