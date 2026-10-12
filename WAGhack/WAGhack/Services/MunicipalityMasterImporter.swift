//
//  MunicipalityMasterImporter.swift
//  WAGhack
//

import Foundation

struct MunicipalityMasterRecord: Equatable, Sendable {
    let code: String
    let prefectureName: String
    let municipalityName: String
    let prefectureKana: String
    let municipalityKana: String
    let isPrefecture: Bool
    let prefectureCode: String
    let historyTrivia: String
    let famousThingsTrivia: String
}

@MainActor
struct MunicipalityMasterImporter {
    static let resourceName = "LocalGovernmentCodeJapan_Knowledge"
    static let expectedColumnCount = 9

    private let parser = CSVParser()

    func records(from source: String) throws -> [MunicipalityMasterRecord] {
        let rows = try parser.parse(source)
        guard let header = rows.first, header.count == Self.expectedColumnCount else {
            throw MunicipalityMasterImportError.invalidHeader
        }

        return try rows.dropFirst().enumerated().map { offset, row in
            guard row.count == Self.expectedColumnCount else {
                throw MunicipalityMasterImportError.invalidColumnCount(row: offset + 2)
            }

            guard !row[0].isEmpty, !row[1].isEmpty else {
                throw MunicipalityMasterImportError.missingRequiredValue(row: offset + 2)
            }

            return MunicipalityMasterRecord(
                code: row[0],
                prefectureName: row[1],
                municipalityName: row[2],
                prefectureKana: row[3],
                municipalityKana: row[4],
                isPrefecture: row[5].uppercased() == "TRUE",
                prefectureCode: row[6],
                historyTrivia: row[7],
                famousThingsTrivia: row[8]
            )
        }
    }

    func records(from data: Data) throws -> [MunicipalityMasterRecord] {
        try records(from: String(decoding: data, as: UTF8.self))
    }

    /// アプリに同梱した市区町村マスタCSVの中身。同期の要否判定(MunicipalityMasterSyncGateの指紋)と
    /// 読み込みの両方が同じ中身を参照するよう、ファイルの場所の解決をここに集める。
    static func sourceData(bundle: Bundle = .main) throws -> Data {
        guard let url = bundle.url(forResource: resourceName, withExtension: "csv") else {
            throw MunicipalityMasterImportError.resourceNotFound
        }
        return try Data(contentsOf: url)
    }
}

enum MunicipalityMasterImportError: LocalizedError {
    case resourceNotFound
    case invalidHeader
    case invalidColumnCount(row: Int)
    case missingRequiredValue(row: Int)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound:
            "市区町村マスタCSVがアプリ内に見つかりません。"
        case .invalidHeader:
            "市区町村マスタCSVのヘッダーが正しくありません。"
        case .invalidColumnCount(let row):
            "市区町村マスタCSVの\(row)行目の列数が正しくありません。"
        case .missingRequiredValue(let row):
            "市区町村マスタCSVの\(row)行目に必須項目がありません。"
        }
    }
}
