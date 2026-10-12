import MapKit
import Testing
@testable import WAGhack

struct MapCameraMoveDurationTests {
    private let base = MKMapRect(x: 1_000_000, y: 1_000_000, width: 10_000, height: 10_000)

    @Test func 今の表示範囲が分からなければ最小の長さにする() {
        #expect(MapCameraMoveDuration.duration(from: nil, to: base) == MapCameraMoveDuration.minimum)
    }

    @Test func 同じ範囲なら最小の長さにする() {
        #expect(MapCameraMoveDuration.duration(from: base, to: base) == MapCameraMoveDuration.minimum)
    }

    @Test func ズーム1段ごとに長くなる() {
        let zoomedOut = MKMapRect(x: base.minX - 5_000, y: base.minY - 5_000, width: 20_000, height: 20_000)

        let duration = MapCameraMoveDuration.duration(from: base, to: zoomedOut)

        #expect(abs(duration - (MapCameraMoveDuration.minimum + MapCameraMoveDuration.secondsPerStep)) < 0.001)
    }

    @Test func 引くときも寄るときも同じ長さになる() {
        let wide = MKMapRect(x: base.minX - 15_000, y: base.minY - 15_000, width: 40_000, height: 40_000)

        #expect(
            abs(MapCameraMoveDuration.duration(from: base, to: wide) - MapCameraMoveDuration.duration(from: wide, to: base)) < 0.001
        )
    }

    @Test func 県全体まで引くような大きな変化でも上限を超えない() {
        let prefecture = MKMapRect(x: base.minX, y: base.minY, width: 2_000_000, height: 2_000_000)

        #expect(MapCameraMoveDuration.duration(from: base, to: prefecture) == MapCameraMoveDuration.maximum)
    }
}
