import CoreGraphics
import CoreLocation
import Testing
@testable import WAGhack

struct BoundarySilhouetteBuilderTests {
    private let builder = BoundarySilhouetteBuilder(targetPoints: 56)

    @Test func 一直線に並んだ頂点は間引かれる() {
        // 正方形の各辺の中点は、角を結ぶ線上にあるので不要な頂点になる。
        let square = [
            CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 5),
            CGPoint(x: 10, y: 10), CGPoint(x: 5, y: 10), CGPoint(x: 0, y: 10), CGPoint(x: 0, y: 5),
            CGPoint(x: 0, y: 0),
        ]
        let simplified = BoundarySilhouetteBuilder.simplifiedRing(square, tolerance: 1)
        #expect(simplified == [
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10), CGPoint(x: 0, y: 0),
        ])
    }

    @Test func 許容誤差より小さい輪は面にならずnilになる() {
        let tiny = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0, y: 0)]
        #expect(BoundarySilhouetteBuilder.simplifiedRing(tiny, tolerance: 1) == nil)
    }

    @Test func 都道府県の枠は本土に合わせ遠い離島の町村は描かない() {
        // 東京都のように、本土と遠く離れた島だけでできた村を持つ県。
        let mainland = makePolygon(minLongitude: 139.0, minLatitude: 35.5, maxLongitude: 140.0, maxLatitude: 36.0)
        let farIsland = makePolygon(minLongitude: 153.9, minLatitude: 24.2, maxLongitude: 154.0, maxLatitude: 24.3)
        let prefecture = AdministrativeBoundary(code: "13", name: "東京都", prefectureCode: "13", polygons: [mainland, farIsland])
        let municipalities = [
            makeMunicipality("13101", minLongitude: 139.0, maxLongitude: 139.5, minLatitude: 35.5, maxLatitude: 36.0),
            makeMunicipality("13102", minLongitude: 139.5, maxLongitude: 140.0, minLatitude: 35.5, maxLatitude: 36.0),
            makeMunicipality("13421", minLongitude: 153.9, maxLongitude: 154.0, minLatitude: 24.2, maxLatitude: 24.3),
        ]

        let map = builder.prefectureMap(of: prefecture, municipalities: municipalities)

        #expect(map?.areas.map(\.code) == ["13101", "13102"])
        // 本土が枠いっぱいに広がる(0〜1に収まり、右端が1になる)。
        let points = map?.areas.flatMap(\.rings).flatMap { $0 } ?? []
        let tolerance = 1e-9
        #expect(points.allSatisfy { $0.x > -tolerance && $0.x < 1 + tolerance && $0.y > -tolerance && $0.y < 1 + tolerance })
        #expect(points.contains { abs($0.x - 1) < tolerance })
    }

    @Test func 都道府県の地図では小さな離島の町村を省き大きな島と本土の区画は残す() {
        // 本土は左下半分の三角形。右上半分は枠の中の海になる(56ptの枠で緯度1度≒28pt)。
        let mainlandExterior = [(139.0, 35.0), (141.0, 35.0), (139.0, 37.0), (139.0, 35.0)]
            .map { CLLocationCoordinate2D(latitude: $0.1, longitude: $0.0) }
        let mainland = BoundaryPolygon(
            exterior: mainlandExterior,
            holes: [],
            boundingBox: GeoBoundingBox(minLongitude: 139.0, minLatitude: 35.0, maxLongitude: 141.0, maxLatitude: 37.0)
        )
        let prefecture = AdministrativeBoundary(code: "15", name: "新潟県", prefectureCode: "15", polygons: [mainland])
        let municipalities = [
            AdministrativeBoundary(code: "15101", name: "本土", prefectureCode: "15", polygons: [mainland]),
            // 本土に載っているごく小さな区(約1pt)。小さくても本土なので残る。
            makeMunicipality("15102", minLongitude: 139.3, maxLongitude: 139.34, minLatitude: 35.3, maxLatitude: 35.34),
            // 海に浮かぶ小さな島(約3pt)。
            makeMunicipality("15586", minLongitude: 140.5, maxLongitude: 140.6, minLatitude: 36.5, maxLatitude: 36.6),
            // 佐渡島のような大きな島(約17pt)。
            makeMunicipality("15224", minLongitude: 140.3, maxLongitude: 140.9, minLatitude: 36.3, maxLatitude: 36.9),
        ]

        let codes = builder.prefectureMap(of: prefecture, municipalities: municipalities)?.areas.map(\.code)

        #expect(codes == ["15101", "15102", "15224"])
    }

    @Test func 市区町村単体の地図は最大のピースを枠いっぱいに描き枠の外の島は描かない() {
        let mainland = makePolygon(minLongitude: 139.0, minLatitude: 35.0, maxLongitude: 139.1, maxLatitude: 35.1)
        let farIsland = makePolygon(minLongitude: 139.5, minLatitude: 34.5, maxLongitude: 139.55, maxLatitude: 34.55)
        let municipality = AdministrativeBoundary(code: "13101", name: "千代田区", prefectureCode: "13", polygons: [mainland, farIsland])

        let map = builder.municipalityMap(of: municipality)

        #expect(map?.areas.map(\.code) == ["13101"])
        #expect(map?.areas.first?.rings.count == 1)
    }

    @Test func 枠の中でも小さすぎる島は描かない() {
        let mainland = makePolygon(minLongitude: 139.0, minLatitude: 35.0, maxLongitude: 141.0, maxLatitude: 37.0)
        // 本土の約1/1000の大きさで、56ptの枠では0.1pt未満になる。
        let islet = makePolygon(minLongitude: 140.0, minLatitude: 36.0, maxLongitude: 140.002, maxLatitude: 36.002)
        let prefecture = AdministrativeBoundary(code: "08", name: "茨城県", prefectureCode: "08", polygons: [mainland])
        let municipality = AdministrativeBoundary(code: "08201", name: "水戸市", prefectureCode: "08", polygons: [mainland, islet])

        #expect(builder.prefectureMap(of: prefecture, municipalities: [municipality])?.areas.first?.rings.count == 1)
    }

    @Test func 縦横比は中央の緯度で経度方向を縮めて求める() {
        // 緯度60度では経度1度の長さが緯度1度の半分になるので、経度2度×緯度1度の範囲は正方形になる。
        let polygon = makePolygon(minLongitude: 10, minLatitude: 59.5, maxLongitude: 12, maxLatitude: 60.5)
        let prefecture = AdministrativeBoundary(code: "99", name: "テスト", prefectureCode: "99", polygons: [polygon])

        let aspectRatio = builder.prefectureMap(of: prefecture, municipalities: [prefecture])?.aspectRatio ?? 0
        #expect(abs(aspectRatio - 1) < 0.01)
    }

    @Test func 日本地図には範囲に掛かる都道府県だけが入り小さな県も消えない() {
        let honshu = makePolygon(minLongitude: 135, minLatitude: 34, maxLongitude: 140, maxLatitude: 38)
        // 範囲に対して1pt程度の小さな県。代表のピースなので残る。
        let small = makePolygon(minLongitude: 134.0, minLatitude: 34.2, maxLongitude: 134.3, maxLatitude: 34.5)
        // 奄美のように本体の範囲外にある島だけの県(架空)。
        let outside = makePolygon(minLongitude: 129.2, minLatitude: 28.0, maxLongitude: 129.6, maxLatitude: 28.5)
        let boundaries = [
            AdministrativeBoundary(code: "13", name: "本州", prefectureCode: "13", polygons: [honshu]),
            AdministrativeBoundary(code: "37", name: "小さな県", prefectureCode: "37", polygons: [small]),
            AdministrativeBoundary(code: "98", name: "範囲外", prefectureCode: "98", polygons: [outside]),
        ]

        let map = builder.japanMap(of: boundaries)

        #expect(map.areas.map(\.code) == ["13", "37"])
        #expect(map.insetFrame == nil)
    }

    @Test func 沖縄県は日本地図の左上の小窓に描く() {
        let honshu = makePolygon(minLongitude: 135, minLatitude: 34, maxLongitude: 140, maxLatitude: 38)
        let okinawaMainIsland = makePolygon(minLongitude: 127.6, minLatitude: 26.1, maxLongitude: 128.3, maxLatitude: 26.9)
        let boundaries = [
            AdministrativeBoundary(code: "13", name: "本州", prefectureCode: "13", polygons: [honshu]),
            AdministrativeBoundary(code: "47", name: "沖縄県", prefectureCode: "47", polygons: [okinawaMainIsland]),
        ]

        let map = builder.japanMap(of: boundaries)

        let okinawa = map.areas.first { $0.code == "47" }
        let insetFrame = try? #require(map.insetFrame)
        let points = okinawa?.rings.flatMap { $0 } ?? []
        #expect(!points.isEmpty)
        // 小窓は左上の隅にあり、沖縄県の形は小窓の中に収まる。
        #expect((insetFrame?.maxX ?? 1) < 0.5)
        #expect((insetFrame?.maxY ?? 1) < 0.5)
        #expect(points.allSatisfy { insetFrame?.contains($0) == true })
    }

    private func makeMunicipality(
        _ code: String, minLongitude: Double, maxLongitude: Double, minLatitude: Double, maxLatitude: Double
    ) -> AdministrativeBoundary {
        let polygon = makePolygon(minLongitude: minLongitude, minLatitude: minLatitude, maxLongitude: maxLongitude, maxLatitude: maxLatitude)
        return AdministrativeBoundary(code: code, name: code, prefectureCode: String(code.prefix(2)), polygons: [polygon])
    }

    /// 矩形の外周をなぞる1つのポリゴン。各辺に中間点を置き、実データのように頂点が多い状態にする。
    private func makePolygon(minLongitude: Double, minLatitude: Double, maxLongitude: Double, maxLatitude: Double) -> BoundaryPolygon {
        let midLongitude = (minLongitude + maxLongitude) / 2
        let midLatitude = (minLatitude + maxLatitude) / 2
        let exterior = [
            (minLongitude, maxLatitude), (midLongitude, maxLatitude), (maxLongitude, maxLatitude),
            (maxLongitude, midLatitude), (maxLongitude, minLatitude), (midLongitude, minLatitude),
            (minLongitude, minLatitude), (minLongitude, midLatitude), (minLongitude, maxLatitude),
        ].map { CLLocationCoordinate2D(latitude: $0.1, longitude: $0.0) }
        return BoundaryPolygon(
            exterior: exterior,
            holes: [],
            boundingBox: GeoBoundingBox(minLongitude: minLongitude, minLatitude: minLatitude,
                                        maxLongitude: maxLongitude, maxLatitude: maxLatitude)
        )
    }
}
