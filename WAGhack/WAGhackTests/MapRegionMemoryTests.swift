import Foundation
import MapKit
import Testing
@testable import WAGhack

struct MapRegionMemoryTests {
    /// テストごとに空の保存先を使い、端末の設定やほかのテストの値に左右されないようにする。
    private let defaults: UserDefaults = {
        let suiteName = "MapRegionMemoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }()

    @Test func 保存していなければ範囲はない() {
        #expect(MapRegionMemory.load(from: defaults) == nil)
    }

    @Test func 保存した範囲をそのまま読み出せる() throws {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.681, longitude: 139.767),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.04)
        )

        MapRegionMemory.save(region, to: defaults)
        let loaded = try #require(MapRegionMemory.load(from: defaults))

        #expect(loaded.center.latitude == 35.681)
        #expect(loaded.center.longitude == 139.767)
        #expect(loaded.span.latitudeDelta == 0.05)
        #expect(loaded.span.longitudeDelta == 0.04)
    }

    @Test func 範囲の大きさが0なら使わない() {
        defaults.set([35.0, 139.0, 0.0, 0.0], forKey: "map.lastRegion")

        #expect(MapRegionMemory.load(from: defaults) == nil)
    }

    @Test func 緯度経度としてありえない値なら使わない() {
        defaults.set([123.0, 139.0, 0.1, 0.1], forKey: "map.lastRegion")

        #expect(MapRegionMemory.load(from: defaults) == nil)
    }

    @Test func 値の数が合わなければ使わない() {
        defaults.set([35.0, 139.0], forKey: "map.lastRegion")

        #expect(MapRegionMemory.load(from: defaults) == nil)
    }
}
