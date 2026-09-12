import Foundation

extension ExplorationProgressCalculator {
    @MainActor
    func summarize(models: [Municipality], savedPlaces: [SavedPlace]) -> ExplorationSummary {
        let entries = models.map { municipality in
            ExplorationMunicipality(
                code: municipality.code, name: municipality.municipalityName,
                prefectureCode: municipality.prefectureCode,
                prefectureName: municipality.prefectureName, isPrefecture: municipality.isPrefecture
            )
        }
        return summarize(
            municipalities: entries,
            visitedCodes: Set(savedPlaces.compactMap { $0.municipality?.code })
        )
    }
}
