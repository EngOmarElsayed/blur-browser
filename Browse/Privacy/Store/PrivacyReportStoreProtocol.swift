//
//  PrivacyReportStoreProtocol.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 13/06/2026.
//

import Foundation

protocol PrivacyReportStoreProtocol {
    @concurrent func refresh() async
    @concurrent func clearAndRefresh() async
}
