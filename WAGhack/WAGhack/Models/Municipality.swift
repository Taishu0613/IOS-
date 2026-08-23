//
//  Municipality.swift
//  WAGhack
//

import SwiftData

@Model
final class Municipality {
    var code: String
    var prefectureName: String
    var municipalityName: String
    var prefectureKana: String
    var municipalityKana: String
    var isPrefecture: Bool
    var prefectureCode: String
    var historyTrivia: String
    var famousThingsTrivia: String

    init(
        code: String,
        prefectureName: String,
        municipalityName: String,
        prefectureKana: String,
        municipalityKana: String,
        isPrefecture: Bool,
        prefectureCode: String,
        historyTrivia: String,
        famousThingsTrivia: String
    ) {
        self.code = code
        self.prefectureName = prefectureName
        self.municipalityName = municipalityName
        self.prefectureKana = prefectureKana
        self.municipalityKana = municipalityKana
        self.isPrefecture = isPrefecture
        self.prefectureCode = prefectureCode
        self.historyTrivia = historyTrivia
        self.famousThingsTrivia = famousThingsTrivia
    }

    @discardableResult
    func updateIfNeeded(from record: MunicipalityMasterRecord) -> Bool {
        guard prefectureName != record.prefectureName
                || municipalityName != record.municipalityName
                || prefectureKana != record.prefectureKana
                || municipalityKana != record.municipalityKana
                || isPrefecture != record.isPrefecture
                || prefectureCode != record.prefectureCode
                || historyTrivia != record.historyTrivia
                || famousThingsTrivia != record.famousThingsTrivia else {
            return false
        }

        prefectureName = record.prefectureName
        municipalityName = record.municipalityName
        prefectureKana = record.prefectureKana
        municipalityKana = record.municipalityKana
        isPrefecture = record.isPrefecture
        prefectureCode = record.prefectureCode
        historyTrivia = record.historyTrivia
        famousThingsTrivia = record.famousThingsTrivia
        return true
    }
}
