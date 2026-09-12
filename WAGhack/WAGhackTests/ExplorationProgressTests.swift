import Testing
import Foundation
import SwiftData
@testable import WAGhack

struct ExplorationProgressTests {
    private let calculator = ExplorationProgressCalculator()

    @Test func 空のマスタでもゼロ除算しない() {
        let summary = calculator.summarize(municipalities: [], visitedCodes: ["13101"])
        #expect(summary.progress.fraction == 0)
        #expect(summary.progress.total == 0)
        #expect(summary.visitedPrefectureCount == 0)
    }

    @Test func 政令市の親と都道府県を除外して特別区は残す() {
        let summary = calculator.summarize(municipalities: [
            entry("01000", "", isPrefecture: true),
            entry("01100", "札幌市"),
            entry("01101", "札幌市中央区"),
            entry("01102", "札幌市北区"),
            entry("13101", "千代田区")
        ], visitedCodes: ["01000", "01100", "01101", "13101", "unknown"])
        #expect(summary.progress.total == 3)
        #expect(summary.progress.visited == 2)
        #expect(summary.visitedPrefectureCount == 2)
        #expect(!summary.eligibleCodes.contains("01100"))
    }

    @Test func 全国は都道府県の率の平均ではなく市区町村の合計で計算する() {
        let summary = calculator.summarize(municipalities: [
            entry("13101", "千代田区"), entry("14101", "横浜市鶴見区"),
            entry("14102", "横浜市神奈川区"), entry("14103", "横浜市西区")
        ], visitedCodes: ["13101"])
        #expect(summary.progress.fraction == 0.25)
        #expect(summary.prefectures.map(\.code) == ["13", "14"])
        #expect(summary.prefectures.last?.progress.visited == 0)
    }

    @Test func 同じコードの重複マスタは一度だけ数える() {
        let municipality = entry("13101", "千代田区")
        let summary = calculator.summarize(municipalities: [municipality, municipality], visitedCodes: ["13101"])
        #expect(summary.progress.total == 1)
        #expect(summary.progress.fraction == 1)
    }

    @Test func 次の目標は切り上げて節目到達後は次へ進む() {
        #expect(ExplorationCount(visited: 1, total: 10).nextGoalText(unit: "市区町村") == "あと2市区町村で25%達成")
        #expect(ExplorationCount(visited: 3, total: 10).nextGoalText(unit: "市区町村") == "あと2市区町村で50%達成")
        #expect(ExplorationCount(visited: 10, total: 10).achievementText == "完全踏破")
        #expect(ExplorationCount(visited: 0, total: 10).achievementText == "旅のはじまり")
        #expect(ExplorationCount(visited: 1, total: 1).nextGoalText(unit: "市区町村") == "すべての市区町村を訪れました！")
        #expect(ExplorationCount(visited: 1, total: 10).nextGoalText(unit: "都道府県") == "あと2都道府県で25%達成")
    }

    @Test func 再集計で削除を反映し訪問済み一覧から外れる() throws {
        let municipalities = [entry("13101", "千代田区"), entry("13102", "中央区")]
        let before = calculator.summarize(municipalities: municipalities, visitedCodes: ["13101"])
        let prefecture = try #require(before.prefectures.first)
        #expect(prefecture.visitedMunicipalities.map(\.code) == ["13101"])
        let after = calculator.summarize(municipalities: municipalities, visitedCodes: [])
        #expect(after.progress.visited == 0)
        #expect(try #require(after.prefectures.first).visitedMunicipalities.isEmpty)
    }

    @Test func 図鑑には1件でも訪問済みの都道府県だけを出す() {
        let summary = calculator.summarize(municipalities: [
            entry("13101", "千代田区"), entry("14101", "横浜市鶴見区")
        ], visitedCodes: ["13101"])
        #expect(summary.visitedPrefectures.map(\.code) == ["13"])
        #expect(summary.prefectureProgress.visited == 1)
        #expect(summary.prefectureProgress.total == 2)
    }

    @MainActor
    @Test func SwiftDataの訪問削除で対象だけを消して進捗を更新する() throws {
        let container = try ModelContainer(
            for: Municipality.self, SavedPlace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let municipality = Municipality(
            code: "13101", prefectureName: "東京都", municipalityName: "千代田区",
            prefectureKana: "", municipalityKana: "", isPrefecture: false,
            prefectureCode: "13", historyTrivia: "", famousThingsTrivia: ""
        )
        context.insert(municipality)
        let visit = SavedPlace(address: "東京都千代田区", latitude: 0, longitude: 0, municipality: municipality)
        let unknown = SavedPlace(address: "旧記録", latitude: 0, longitude: 0)
        context.insert(visit)
        context.insert(unknown)
        try context.save()
        let store = SavedPlacesStore()
        let before = store.summary(municipalities: [municipality], savedPlaces: [visit, unknown])
        #expect(before.progress.visited == 1)
        #expect(store.excludedPlaces([visit, unknown], summary: before).count == 1)
        store.delete([visit], from: context)
        #expect(store.deletionErrorMessage == nil)
        let remaining = try context.fetch(FetchDescriptor<SavedPlace>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.address == "旧記録")
        #expect(store.summary(municipalities: [municipality], savedPlaces: remaining).progress.visited == 0)
    }

    private func entry(_ code: String, _ name: String, isPrefecture: Bool = false) -> ExplorationMunicipality {
        ExplorationMunicipality(
            code: code, name: name, prefectureCode: String(code.prefix(2)),
            prefectureName: String(code.prefix(2)), isPrefecture: isPrefecture
        )
    }
}
