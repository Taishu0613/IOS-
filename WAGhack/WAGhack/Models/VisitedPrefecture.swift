//
//  VisitedPrefecture.swift
//  WAGhack
//

import Foundation
import SwiftData

/// 都道府県だけを単独で「記録した」ことを表す。市区町村(SavedPlace)の記録とは完全に独立しており、
/// 市区町村を1件も訪れていない都道府県でも、これがあれば訪問済みとして扱う。
@Model
final class VisitedPrefecture {
    @Attribute(.unique) var code: String
    var name: String
    var visitedAt: Date

    init(code: String, name: String, visitedAt: Date = .now) {
        self.code = code
        self.name = name
        self.visitedAt = visitedAt
    }
}
