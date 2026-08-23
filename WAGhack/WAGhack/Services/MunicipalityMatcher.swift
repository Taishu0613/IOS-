//
//  MunicipalityMatcher.swift
//  WAGhack
//

import Foundation

struct MunicipalityMatcher {
    func match(japaneseAddress: String, municipalities: [Municipality]) -> Municipality? {
        let normalizedAddress = Self.normalize(japaneseAddress)

        return municipalities
            .filter { municipality in
                guard !municipality.isPrefecture, !municipality.municipalityName.isEmpty else {
                    return false
                }

                return normalizedAddress.contains(Self.normalize(municipality.prefectureName))
                    && normalizedAddress.contains(Self.normalize(municipality.municipalityName))
            }
            .sorted(by: isPreferredMatch)
            .first
    }

    static func normalize(_ value: String) -> String {
        value
            .precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "ヶ", with: "ケ")
            .replacingOccurrences(of: "ヵ", with: "カ")
            .filter { !$0.isWhitespace }
    }

    private func isPreferredMatch(_ lhs: Municipality, _ rhs: Municipality) -> Bool {
        if lhs.municipalityName.count != rhs.municipalityName.count {
            // 政令指定都市名と区名の両方が一致する場合は、より具体的な区を採用する。
            return lhs.municipalityName.count > rhs.municipalityName.count
        }

        // 北海道の「泊村」のような同名候補は行政区域コードの昇順で決定する。
        return lhs.code < rhs.code
    }
}
