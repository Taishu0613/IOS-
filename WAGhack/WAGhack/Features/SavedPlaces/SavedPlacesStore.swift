import Foundation
import SwiftData
import Observation

/// 永続データの正本はSwiftData。集計結果を保存せず、最新のQuery結果から導出する。
@MainActor
@Observable
final class SavedPlacesStore {
    var deletionErrorMessage: String?

    func summary(municipalities: [Municipality], savedPlaces: [SavedPlace]) -> ExplorationSummary {
        ExplorationProgressCalculator().summarize(models: municipalities, savedPlaces: savedPlaces)
    }

    func excludedPlaces(_ places: [SavedPlace], summary: ExplorationSummary) -> [SavedPlace] {
        places.filter { place in
            guard let code = place.municipality?.code else { return true }
            return !summary.eligibleCodes.contains(code)
        }
    }

    func delete(_ places: [SavedPlace], from context: ModelContext) {
        for place in places {
            context.delete(place)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            deletionErrorMessage = error.localizedDescription
        }
    }
}
