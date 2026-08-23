//
//  MunicipalityMasterStore.swift
//  WAGhack
//

import SwiftData

@ModelActor
actor MunicipalityMasterStore {
    func synchronize(records: [MunicipalityMasterRecord]) throws {
        let existingMunicipalities = try modelContext.fetch(FetchDescriptor<Municipality>())
        var municipalityByCode: [String: Municipality] = [:]
        var duplicateMunicipalities: [Municipality] = []

        for municipality in existingMunicipalities {
            if municipalityByCode[municipality.code] == nil {
                municipalityByCode[municipality.code] = municipality
            } else {
                duplicateMunicipalities.append(municipality)
            }
        }

        let importedCodes = Set(records.map(\.code))
        var hasChanges = !duplicateMunicipalities.isEmpty

        for municipality in duplicateMunicipalities {
            modelContext.delete(municipality)
        }

        for record in records {
            if let municipality = municipalityByCode[record.code] {
                hasChanges = municipality.updateIfNeeded(from: record) || hasChanges
            } else {
                let municipality = Municipality(record: record)
                modelContext.insert(municipality)
                municipalityByCode[record.code] = municipality
                hasChanges = true
            }
        }

        // CSVを唯一のマスタとし、削除されたコードをSwiftData側へ残さない。
        for municipality in existingMunicipalities where !importedCodes.contains(municipality.code) {
            modelContext.delete(municipality)
            hasChanges = true
        }

        guard hasChanges else { return }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

private extension Municipality {
    convenience init(record: MunicipalityMasterRecord) {
        self.init(
            code: record.code,
            prefectureName: record.prefectureName,
            municipalityName: record.municipalityName,
            prefectureKana: record.prefectureKana,
            municipalityKana: record.municipalityKana,
            isPrefecture: record.isPrefecture,
            prefectureCode: record.prefectureCode,
            historyTrivia: record.historyTrivia,
            famousThingsTrivia: record.famousThingsTrivia
        )
    }
}
