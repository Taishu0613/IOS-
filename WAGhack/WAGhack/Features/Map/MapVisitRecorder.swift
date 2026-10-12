import CoreLocation
import Foundation
import SwiftData

struct MapVisitResult {
    let municipalityName: String
    let isFirstVisit: Bool
    let milestone: Int?

    var title: String {
        if let milestone { return "\(milestone)%踏破達成！" }
        if isFirstVisit { return "\(municipalityName)を初訪問！" }
        return "訪問記録を更新しました"
    }

    static func crossedMilestone(before: ExplorationCount, after: ExplorationCount) -> Int? {
        guard after.visited > before.visited, after.total > 0 else { return nil }
        return [25, 50, 75, 100].last { percentage in
            before.fraction < Double(percentage) / 100 && after.fraction >= Double(percentage) / 100
        }
    }
}

/// 保存成功を確認した後だけ、達成結果を返す。失敗時は変更を巻き戻す。
@MainActor
struct MapVisitRecorder {
    func record(_ visit: MunicipalityVisit, municipalities: [Municipality], context: ModelContext) throws -> MapVisitResult {
        let savedPlaces = try context.fetch(FetchDescriptor<SavedPlace>())
        let calculator = ExplorationProgressCalculator()
        let before = calculator.summarize(models: municipalities, savedPlaces: savedPlaces)
        let existing = savedPlaces.first { $0.municipality?.code == visit.municipality.code }
        let isFirstVisit = existing == nil
        var updatedPlaces = savedPlaces
        if let existing {
            existing.update(with: visit)
        } else {
            let place = SavedPlace(
                address: visit.localizedAddress,
                latitude: visit.location.coordinate.latitude,
                longitude: visit.location.coordinate.longitude,
                municipality: visit.municipality
            )
            context.insert(place)
            updatedPlaces.append(place)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        let after = calculator.summarize(models: municipalities, savedPlaces: updatedPlaces)
        let code = visit.municipality.prefectureCode
        let previousProgress = before.prefectures.first { $0.code == code }?.progress
        let currentProgress = after.prefectures.first { $0.code == code }?.progress
        var milestone: Int?
        if let previousProgress, let currentProgress {
            milestone = MapVisitResult.crossedMilestone(before: previousProgress, after: currentProgress)
        }
        return MapVisitResult(municipalityName: visit.municipality.municipalityName,
                              isFirstVisit: isFirstVisit, milestone: milestone)
    }
}
