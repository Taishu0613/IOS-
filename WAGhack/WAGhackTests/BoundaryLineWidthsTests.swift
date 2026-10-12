import MapKit
import Testing
@testable import WAGhack

struct BoundaryLineWidthsTests {
    /// 東京駅付近を中心に、横幅`widthMeters`を横幅`points`ptの地図で見ているときの縮尺。
    private func makeScale(widthMeters: Double, points: CGFloat = 400) -> BoundaryMapScale? {
        let center = MKMapPoint(CLLocationCoordinate2D(latitude: 35.68, longitude: 139.77))
        let width = widthMeters * MKMapPointsPerMeterAtLatitude(35.68)
        let rect = MKMapRect(x: center.x - width / 2, y: center.y - width, width: width, height: width * 2)
        return BoundaryMapScale(visibleRect: rect, mapWidthPoints: points)
    }

    @Test func 表示範囲の横幅をメートルで求める() throws {
        let scale = try #require(makeScale(widthMeters: 20_000))

        #expect(abs(scale.visibleWidthMeters - 20_000) < 1)
        #expect(abs(scale.metersPerPoint - 50) < 0.01)
    }

    @Test func 地図の横幅が0なら縮尺は求めない() {
        #expect(makeScale(widthMeters: 20_000, points: 0) == nil)
    }

    @Test func 全国表示では以前の細さのままにする() throws {
        let widths = BoundaryLineWidths(scale: try #require(makeScale(widthMeters: 2_500_000)))

        #expect(widths == .widest)
        #expect(widths.prefectureBorder == BoundaryLineWidths.prefectureBorderRange.lowerBound)
    }

    @Test func 市区町村の縮尺では最も太くする() throws {
        let widths = BoundaryLineWidths(scale: try #require(makeScale(widthMeters: 10_000)))

        #expect(widths.prefectureBorder == BoundaryLineWidths.prefectureBorderRange.upperBound)
        #expect(widths.municipalityLine == BoundaryLineWidths.municipalityLineRange.upperBound)
    }

    @Test func 寄るほど太くなる() throws {
        let wide = BoundaryLineWidths(scale: try #require(makeScale(widthMeters: 800_000)))
        let prefecture = BoundaryLineWidths(scale: try #require(makeScale(widthMeters: 100_000)))

        #expect(wide.prefectureBorder < prefecture.prefectureBorder)
        #expect(wide.municipalityLine < prefecture.municipalityLine)
    }

    @Test func 現在地の縁取りはどの縮尺でも県境より太い() {
        for metersPerPoint in [10.0, 60, 250, 1_000, 3_000, 10_000] {
            let widths = BoundaryLineWidths(scale: BoundaryMapScaleStub.scale(metersPerPoint: metersPerPoint))
            #expect(widths.currentOutline > widths.prefectureBorder)
        }
    }

    @Test func 縮尺が少し変わっただけでは太さを変えない() {
        #expect(BoundaryLineWidths.closeness(metersPerPoint: 250) == BoundaryLineWidths.closeness(metersPerPoint: 255))
    }

    @Test func 県全体の縮尺では市区町村ページに切り替えない() {
        #expect(!MapProgressPageZoomPolicy.shouldSwitchToMunicipalities(visibleWidthMeters: 60_000))
    }

    @Test func 市区町村の縮尺まで寄ったら市区町村ページに切り替える() {
        #expect(MapProgressPageZoomPolicy.shouldSwitchToMunicipalities(visibleWidthMeters: 20_000))
    }
}

/// 1ptあたりのmを直接指定した縮尺を作る(横幅400ptの地図で換算)。
private enum BoundaryMapScaleStub {
    static func scale(metersPerPoint: Double) -> BoundaryMapScale {
        let points: CGFloat = 400
        let width = metersPerPoint * Double(points) * MKMapPointsPerMeterAtLatitude(0)
        return BoundaryMapScale(visibleRect: MKMapRect(x: 0, y: MKMapRect.world.midY - width / 2, width: width, height: width), mapWidthPoints: points)!
    }
}
