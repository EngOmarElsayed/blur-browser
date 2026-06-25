//
//  Array+Extension.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 25/06/2026.
//

import Foundation

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
