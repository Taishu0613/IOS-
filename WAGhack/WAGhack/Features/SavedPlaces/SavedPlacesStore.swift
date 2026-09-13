import Foundation
import SwiftData
import Observation

/// 永続データの正本はSwiftData。集計結果を保存せず、最新のQuery結果から導出する。
@MainActor
@Observable
final class SavedPlacesStore {
    var deletionErrorMessage: String?

    private var cachedInputCounts: (municipalities: Int, savedPlaces: Int, visitedPrefectures: Int)?
    private var cachedSummary: ExplorationSummary?

    /// 件数が前回と同じなら計算をやり直さない。再訪問での上書きのように件数が変わらない更新は
    /// 集計結果(市区町村コードの集合)に影響しないため、件数の一致だけで十分。
    func summary(
        municipalities: [Municipality],
        savedPlaces: [SavedPlace],
        visitedPrefectures: [VisitedPrefecture] = []
    ) -> ExplorationSummary {
        let counts = (municipalities.count, savedPlaces.count, visitedPrefectures.count)
        if let cachedSummary, cachedInputCounts.map({ $0 == counts }) == true {
            return cachedSummary
        }
        let summary = ExplorationProgressCalculator().summarize(
            models: municipalities, savedPlaces: savedPlaces, visitedPrefectures: visitedPrefectures
        )
        cachedInputCounts = counts
        cachedSummary = summary
        return summary
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
