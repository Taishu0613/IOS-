//
//  WAGhackTests.swift
//  WAGhackTests
//
//  Created by 若杉泰周 on 2026/08/23.
//

import Testing
import CoreLocation
import Foundation
import SwiftData
@testable import WAGhack

struct WAGhackTests {
    @Test func 住所変換では端末の現在ロケールを使用する() {
        #expect(AddressResolver.preferredLocale.identifier == Locale.current.identifier)
    }

    @Test func savedPlaceが住所と座標を保持する() {
        let place = SavedPlace(
            address: "東京都千代田区千代田1-1",
            latitude: 35.685175,
            longitude: 139.752800
        )

        #expect(place.address == "東京都千代田区千代田1-1")
        #expect(place.coordinate.latitude == 35.685175)
        #expect(place.coordinate.longitude == 139.752800)
    }

    @MainActor
    @Test func CSVマスタを空欄とヘッダー内改行を含めて読み込める() throws {
        let url = try #require(
            Bundle.main.url(
                forResource: MunicipalityMasterImporter.resourceName,
                withExtension: "csv"
            )
        )
        let source = try String(contentsOf: url, encoding: .utf8)

        let records = try MunicipalityMasterImporter().records(from: source)

        #expect(records.count == 1_965)
        let hokkaido = try #require(records.first(where: { $0.code == "01000" }))
        #expect(hokkaido.isPrefecture)
        #expect(hokkaido.municipalityName.isEmpty)
        #expect(hokkaido.historyTrivia.isEmpty)
        #expect(hokkaido.famousThingsTrivia.isEmpty)
    }

    @Test func 市区町村照合では政令指定都市より具体的な区を選ぶ() throws {
        let sapporo = makeMunicipality(
            code: "01100",
            prefectureName: "北海道",
            municipalityName: "札幌市"
        )
        let chuoWard = makeMunicipality(
            code: "01101",
            prefectureName: "北海道",
            municipalityName: "札幌市中央区"
        )

        let matched = MunicipalityMatcher().match(
            japaneseAddress: "〒060-0001 北海道札幌市中央区北一条西2丁目",
            municipalities: [sapporo, chuoWard]
        )

        #expect(matched?.code == "01101")
    }

    @Test func 同名市区町村は行政区域コードの小さい候補を選ぶ() {
        let firstTomari = makeMunicipality(
            code: "01403",
            prefectureName: "北海道",
            municipalityName: "泊村"
        )
        let secondTomari = makeMunicipality(
            code: "01696",
            prefectureName: "北海道",
            municipalityName: "泊村"
        )

        let matched = MunicipalityMatcher().match(
            japaneseAddress: "北海道古宇郡泊村",
            municipalities: [secondTomari, firstTomari]
        )

        #expect(matched?.code == "01403")
    }

    @MainActor
    @Test func 市区町村マスタをSwiftDataへ同期して更新できる() async throws {
        let schema = Schema([Municipality.self, SavedPlace.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let store = MunicipalityMasterStore(modelContainer: container)

        let initialRecords = [
            makeRecord(code: "01101", municipalityName: "札幌市中央区", historyTrivia: "最初の豆知識"),
            makeRecord(code: "01102", municipalityName: "札幌市北区")
        ]
        try await store.synchronize(records: initialRecords)

        let initialContext = ModelContext(container)
        let initialMunicipalities = try initialContext.fetch(FetchDescriptor<Municipality>())
        #expect(initialMunicipalities.count == 2)

        let updatedRecords = [
            makeRecord(code: "01101", municipalityName: "札幌市中央区", historyTrivia: "更新後の豆知識")
        ]
        try await store.synchronize(records: updatedRecords)

        let updatedContext = ModelContext(container)
        let updatedMunicipalities = try updatedContext.fetch(FetchDescriptor<Municipality>())
        #expect(updatedMunicipalities.count == 1)
        #expect(updatedMunicipalities.first?.code == "01101")
        #expect(updatedMunicipalities.first?.historyTrivia == "更新後の豆知識")
    }

    @Test func 住所が取得できない場合は座標を表示できる文字列にする() {
        let location = CLLocation(latitude: 35.685175, longitude: 139.752800)

        let fallback = AddressResolver.coordinateFallback(for: location)

        #expect(fallback == "現在地（35.68518, 139.75280）")
    }

    private func makeMunicipality(
        code: String,
        prefectureName: String,
        municipalityName: String
    ) -> Municipality {
        Municipality(
            code: code,
            prefectureName: prefectureName,
            municipalityName: municipalityName,
            prefectureKana: "",
            municipalityKana: "",
            isPrefecture: false,
            prefectureCode: String(code.prefix(2)),
            historyTrivia: "",
            famousThingsTrivia: ""
        )
    }

    private func makeRecord(
        code: String,
        municipalityName: String,
        historyTrivia: String = ""
    ) -> MunicipalityMasterRecord {
        MunicipalityMasterRecord(
            code: code,
            prefectureName: "北海道",
            municipalityName: municipalityName,
            prefectureKana: "ﾎｯｶｲﾄﾞｳ",
            municipalityKana: "",
            isPrefecture: false,
            prefectureCode: "01",
            historyTrivia: historyTrivia,
            famousThingsTrivia: ""
        )
    }
}
