import Testing
@testable import WAGhack

struct UnvisitedMunicipalityVisibilityTests {
    @Test func 地方全体を見ている縮尺では網目を描かない() {
        #expect(!UnvisitedMunicipalityVisibility.isVisible(current: false, visibleWidthMeters: 170_000))
    }

    @Test func 市区町村が見分けられる縮尺まで寄ったら網目を描く() {
        #expect(UnvisitedMunicipalityVisibility.isVisible(current: false, visibleWidthMeters: 100_000))
    }

    @Test func 描いている間は少し引いただけでは消さない() {
        #expect(UnvisitedMunicipalityVisibility.isVisible(current: true, visibleWidthMeters: 140_000))
    }

    @Test func 描いていない間は少し寄っただけでは描かない() {
        #expect(!UnvisitedMunicipalityVisibility.isVisible(current: false, visibleWidthMeters: 140_000))
    }

    @Test func 描いている間も十分に引いたら消す() {
        #expect(!UnvisitedMunicipalityVisibility.isVisible(current: true, visibleWidthMeters: 160_000))
    }

    @Test func 網目を描くときは必ずLOD2以上の形が読み込まれている() {
        // LOD1→LOD2へ切り替わる幅(manifestのlodTransitions)。これより狭い間はLOD1に戻らない。
        let lod2ZoomInBelowMeters = 180_000.0
        #expect(UnvisitedMunicipalityVisibility.showBelowMeters < lod2ZoomInBelowMeters)
        #expect(UnvisitedMunicipalityVisibility.hideAboveMeters < lod2ZoomInBelowMeters)
    }
}
