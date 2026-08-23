//
//  CSVParser.swift
//  WAGhack
//

import Foundation

struct CSVParser {
    func parse(_ source: String) throws -> [[String]] {
        let characters = Array(source)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotedField = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if isInsideQuotedField {
                if character == "\"" {
                    let nextIndex = index + 1
                    if nextIndex < characters.count, characters[nextIndex] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }

                    isInsideQuotedField = false
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    isInsideQuotedField = true
                case ",":
                    row.append(field)
                    field = ""
                // SwiftのCharacterではCRLFが1文字になるため、3種類すべてを扱う。
                case "\n", "\r", "\r\n":
                    row.append(field)
                    appendRowIfNeeded(row, to: &rows)
                    row = []
                    field = ""
                default:
                    field.append(character)
                }
            }

            index += 1
        }

        guard !isInsideQuotedField else {
            throw CSVParserError.unclosedQuotedField
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            appendRowIfNeeded(row, to: &rows)
        }

        if let firstField = rows.first?.first {
            rows[0][0] = firstField.replacingOccurrences(of: "\u{FEFF}", with: "")
        }

        return rows
    }

    private func appendRowIfNeeded(_ row: [String], to rows: inout [[String]]) {
        guard row.contains(where: { !$0.isEmpty }) else { return }
        rows.append(row)
    }
}

enum CSVParserError: LocalizedError {
    case unclosedQuotedField

    var errorDescription: String? {
        switch self {
        case .unclosedQuotedField:
            "CSVの引用符が閉じられていません。"
        }
    }
}
