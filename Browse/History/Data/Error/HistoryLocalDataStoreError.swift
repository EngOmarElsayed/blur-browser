//
//  HistoryLocalDataStoreError.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 23/06/2026.
//

import Foundation

enum HistoryLocalDataStoreError: Error {
    case modelContextIsNotFound
    case failedToSavedDelete
    case failedToSavedAdd
}
