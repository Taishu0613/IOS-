import Foundation

/// 表示と集計の共通単位。SwiftDataやViewに依存しないため、集計規則を単独で検証できる。
struct ExplorationMunicipality: Identifiable {
    let code: String
    let name: String
    let prefectureCode: String
    let prefectureName: String
    let isPrefecture: Bool

    var id: String { code }
}

struct ExplorationCount {
    let visited: Int
    let total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(visited) / Double(total)
    }

    var percentageText: String {
        fraction.formatted(.percent.precision(.fractionLength(1)))
    }

    var achievementText: String {
        guard visited > 0 else { return "旅のはじまり" }
        if visited == total { return "完全踏破" }
        if fraction >= 0.75 { return "75%達成" }
        if fraction >= 0.5 { return "50%達成" }
        if fraction >= 0.25 { return "25%達成" }
        return "初訪問達成"
    }

    /// 都道府県カード・市区町村カードの両方で使うため、単位を呼び出し側から渡す。
    func nextGoalText(unit: String) -> String {
        guard total > 0 else { return "対象の\(unit)がありません" }
        guard visited > 0 else { return "まずは1つの\(unit)を訪れよう" }
        for percentage in [25, 50, 75, 100] {
            // 切り上げて、目標の割合に実際に到達する訪問数を求める。
            let target = (total * percentage + 99) / 100
            if target > visited {
                return "あと\(target - visited)\(unit)で\(percentage)%達成"
            }
        }
        return "すべての\(unit)を訪れました！"
    }
}

struct PrefectureExploration: Identifiable {
    let code: String
    let name: String
    let municipalities: [ExplorationMunicipality]
    let visitedCodes: Set<String>

    var id: String { code }
    var progress: ExplorationCount {
        ExplorationCount(visited: visitedCodes.count, total: municipalities.count)
    }
    /// 図鑑は集める体験のため、訪問済みの市区町村だけを一覧に出す。
    var visitedMunicipalities: [ExplorationMunicipality] {
        municipalities.filter { visitedCodes.contains($0.code) }
    }
}

struct ExplorationSummary {
    let prefectures: [PrefectureExploration]
    let eligibleCodes: Set<String>

    var progress: ExplorationCount {
        ExplorationCount(
            visited: prefectures.reduce(0) { $0 + $1.progress.visited },
            total: eligibleCodes.count
        )
    }

    var visitedPrefectureCount: Int {
        prefectures.filter { !$0.visitedCodes.isEmpty }.count
    }

    var prefectureProgress: ExplorationCount {
        ExplorationCount(visited: visitedPrefectureCount, total: prefectures.count)
    }

    /// 図鑑は集める体験のため、1件でも訪問済みの都道府県だけを一覧に出す。
    var visitedPrefectures: [PrefectureExploration] {
        prefectures.filter { !$0.visitedCodes.isEmpty }
    }
}

struct ExplorationProgressCalculator {
    func summarize(
        municipalities: [ExplorationMunicipality],
        visitedCodes: Set<String>
    ) -> ExplorationSummary {
        let candidates = municipalities.filter { !$0.isPrefecture && !$0.name.isEmpty }
        let grouped = Dictionary(grouping: candidates, by: \.prefectureCode)
        var prefectures: [PrefectureExploration] = []
        var eligibleCodes: Set<String> = []

        for code in grouped.keys.sorted() {
            guard let members = grouped[code] else { continue }
            // マスタには政令指定都市とその区が併存する。区を持つ市は分母から除き、
            // 市の訪問だけで全区を訪問扱いにしない。東京都の特別区はそのまま対象。
            let citiesWithWards = Set(members.compactMap { municipality -> String? in
                guard municipality.name.hasSuffix("区"),
                      let cityEnd = municipality.name.firstIndex(of: "市") else { return nil }
                return String(municipality.name[...cityEnd])
            })
            let eligible = members.filter { !citiesWithWards.contains($0.name) }
            // 同じ行政区域コードの重複は進捗へ影響させない。
            var unique: [String: ExplorationMunicipality] = [:]
            for municipality in eligible where unique[municipality.code] == nil {
                unique[municipality.code] = municipality
            }
            let sorted = unique.values.sorted { $0.code < $1.code }
            guard let first = sorted.first else { continue }
            let codes = Set(sorted.map(\.code))
            eligibleCodes.formUnion(codes)
            prefectures.append(PrefectureExploration(
                code: code,
                name: first.prefectureName,
                municipalities: sorted,
                visitedCodes: visitedCodes.intersection(codes)
            ))
        }
        return ExplorationSummary(prefectures: prefectures, eligibleCodes: eligibleCodes)
    }
}
