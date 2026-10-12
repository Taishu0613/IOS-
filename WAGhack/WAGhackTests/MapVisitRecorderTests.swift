import Testing
import SwiftData
import CoreLocation
@testable import WAGhack

@MainActor
struct MapVisitRecorderTests {
    @Test func 初訪問を保存し再訪問では件数と踏破率を増やさない() throws {
        let container = try ModelContainer(for: Municipality.self, SavedPlace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let municipality = makeMunicipality(code: "13101", name: "千代田区")
        context.insert(municipality)
        let visit = MunicipalityVisit(localizedAddress: "東京都千代田区", location: CLLocation(latitude: 35, longitude: 139), municipality: municipality)
        let recorder = MapVisitRecorder()
        let first = try recorder.record(visit, municipalities: [municipality], context: context)
        #expect(first.isFirstVisit)
        #expect(first.milestone == 100)
        let secondVisit = MunicipalityVisit(localizedAddress: "再訪問", location: CLLocation(latitude: 36, longitude: 140), municipality: municipality)
        let second = try recorder.record(secondVisit, municipalities: [municipality], context: context)
        #expect(!second.isFirstVisit)
        #expect(second.milestone == nil)
        #expect(second.title == "訪問記録を更新しました")
        let records = try context.fetch(FetchDescriptor<SavedPlace>())
        #expect(records.count == 1)
        #expect(records.first?.latitude == 36)
        #expect(records.first?.address == "再訪問")
    }

    @Test func 節目は実際に跨いだ時だけ通知する() {
        #expect(MapVisitResult.crossedMilestone(before: .init(visited: 2, total: 10), after: .init(visited: 3, total: 10)) == 25)
        #expect(MapVisitResult.crossedMilestone(before: .init(visited: 3, total: 10), after: .init(visited: 4, total: 10)) == nil)
        #expect(MapVisitResult.crossedMilestone(before: .init(visited: 5, total: 10), after: .init(visited: 5, total: 10)) == nil)
        #expect(MapVisitResult.crossedMilestone(before: .init(visited: 0, total: 0), after: .init(visited: 0, total: 0)) == nil)
    }

    @Test func 政令市の親を保存しても区の達成演出を出さない() throws {
        let container = try ModelContainer(for: Municipality.self, SavedPlace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let city = makeMunicipality(code: "14100", name: "横浜市")
        let ward = makeMunicipality(code: "14101", name: "横浜市鶴見区")
        context.insert(city)
        context.insert(ward)
        let visit = MunicipalityVisit(localizedAddress: "横浜市", location: CLLocation(latitude: 35, longitude: 139), municipality: city)
        let result = try MapVisitRecorder().record(visit, municipalities: [city, ward], context: context)
        #expect(result.isFirstVisit)
        #expect(result.milestone == nil)
    }

    private func makeMunicipality(code: String, name: String) -> Municipality {
        Municipality(code: code, prefectureName: "都道府県", municipalityName: name,
            prefectureKana: "", municipalityKana: "", isPrefecture: false,
            prefectureCode: String(code.prefix(2)), historyTrivia: "", famousThingsTrivia: "")
    }
}
