import MapKit
import Testing
@testable import WAGhack

struct BoundaryFocusRectTests {
    /// 東京駅付近。メートルと地図座標(MKMapPoint)の換算はこの緯度で行う。
    private let tokyo = CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)
    private var metersToMapPoints: Double { MKMapPointsPerMeterAtLatitude(tokyo.latitude) }

    @Test func 区域の外接矩形の上下左右に12パーセントずつ余白を足す() {
        let area = square(centeredAt: MKMapPoint(tokyo), sideMeters: 10_000)

        let rect = BoundaryFocusRect.rect(enclosing: area, including: tokyo)

        #expect(isClose(rect.width, area.width * 1.24))
        #expect(isClose(rect.height, area.height * 1.24))
        #expect(isClose(rect.midX, area.midX))
    }

    @Test func 現在地が区域の外にあっても画面に入るよう矩形を広げる() {
        let center = MKMapPoint(tokyo)
        let area = square(centeredAt: MKMapPoint(x: center.x + 8_000 * metersToMapPoints, y: center.y), sideMeters: 10_000)

        let rect = BoundaryFocusRect.rect(enclosing: area, including: tokyo)

        #expect(rect.contains(center))
        #expect(rect.contains(MKMapPoint(x: area.maxX, y: area.midY)))
    }

    @Test func 一辺が1200メートル未満なら1200メートルまで広げる() {
        let area = square(centeredAt: MKMapPoint(tokyo), sideMeters: 200)

        let rect = BoundaryFocusRect.rect(enclosing: area, including: tokyo)

        #expect(isClose(rect.width, 1_200 * metersToMapPoints))
        #expect(isClose(rect.height, 1_200 * metersToMapPoints))
        #expect(isClose(rect.midX, area.midX))
        #expect(isClose(rect.midY, area.midY))
    }

    @Test func 細長い区域は短い辺だけを1200メートルまで広げる() {
        let center = MKMapPoint(tokyo)
        let area = MKMapRect(
            x: center.x - 2_500 * metersToMapPoints, y: center.y - 50 * metersToMapPoints,
            width: 5_000 * metersToMapPoints, height: 100 * metersToMapPoints
        )

        let rect = BoundaryFocusRect.rect(enclosing: area, including: tokyo)

        #expect(isClose(rect.width, area.width * 1.24))
        #expect(isClose(rect.height, 1_200 * metersToMapPoints))
    }

    @Test func 長い辺が100キロメートルを超えたら現在地を中心に100キロメートルで切る() {
        let center = MKMapPoint(tokyo)
        // 東西300km・南北20kmの区域の西端近くに現在地がある。
        let area = MKMapRect(
            x: center.x - 10_000 * metersToMapPoints, y: center.y - 10_000 * metersToMapPoints,
            width: 300_000 * metersToMapPoints, height: 20_000 * metersToMapPoints
        )

        let rect = BoundaryFocusRect.rect(enclosing: area, including: tokyo)

        #expect(isClose(rect.width, 100_000 * metersToMapPoints))
        #expect(isClose(rect.midX, center.x))
        // 100km以内の短い辺は切らずに余白付きのまま残す。
        #expect(isClose(rect.height, area.height * 1.24))
    }

    @Test func 上限にnilを渡すと100キロメートルを超えても区域全体を収める() {
        let center = MKMapPoint(tokyo)
        // 都道府県に寄せる場合を想定。東西300km・南北20kmの区域の西端近くに現在地がある。
        let area = MKMapRect(
            x: center.x - 10_000 * metersToMapPoints, y: center.y - 10_000 * metersToMapPoints,
            width: 300_000 * metersToMapPoints, height: 20_000 * metersToMapPoints
        )

        let rect = BoundaryFocusRect.rect(enclosing: area, including: tokyo, maximumSideMeters: nil)

        #expect(isClose(rect.width, area.width * 1.24))
        #expect(isClose(rect.midX, area.midX))
    }

    @Test func 現在地を含む島があればその島に寄せる() {
        let mainland = polygon(square(centeredAt: MKMapPoint(tokyo), sideMeters: 20_000))
        let islandCenter = MKMapPoint(x: MKMapPoint(tokyo).x, y: MKMapPoint(tokyo).y + 100_000 * metersToMapPoints)
        let island = polygon(square(centeredAt: islandCenter, sideMeters: 3_000))

        let rect = BoundaryFocusRect.rect(islands: [mainland, island], containing: islandCenter.coordinate)

        #expect(rect.map { isClose($0.width, 3_000 * metersToMapPoints * 1.24) } == true)
        #expect(rect?.contains(islandCenter) == true)
    }

    @Test func 現在地を含む島が無ければ最大の島に寄せる() {
        let center = MKMapPoint(tokyo)
        let small = polygon(square(centeredAt: MKMapPoint(x: center.x + 30_000 * metersToMapPoints, y: center.y), sideMeters: 2_000))
        let large = polygon(square(centeredAt: MKMapPoint(x: center.x - 30_000 * metersToMapPoints, y: center.y), sideMeters: 8_000))

        let rect = BoundaryFocusRect.rect(islands: [small, large], containing: tokyo)

        // 最大の島(西)と現在地を囲むので、東の小さな島は含まない。
        #expect(rect?.contains(MKMapPoint(x: large.boundingMapRect.midX, y: large.boundingMapRect.midY)) == true)
        #expect(rect?.contains(MKMapPoint(x: small.boundingMapRect.midX, y: small.boundingMapRect.midY)) == false)
    }

    @Test func 島が無ければnilを返す() {
        #expect(BoundaryFocusRect.rect(islands: [], containing: tokyo) == nil)
    }

    @Test func 穴の中の点は区域の外とみなす() {
        let center = MKMapPoint(tokyo)
        let outer = square(centeredAt: center, sideMeters: 10_000)
        let hole = polygon(square(centeredAt: center, sideMeters: 2_000))
        let withHole = MKPolygon(points: corners(of: outer), count: 4, interiorPolygons: [hole])
        let insideRing = MKMapPoint(x: center.x + 3_000 * metersToMapPoints, y: center.y)

        #expect(!BoundaryFocusRect.contains(withHole, center))
        #expect(BoundaryFocusRect.contains(withHole, insideRing))
    }

    @Test @MainActor func 描画用ピースが無くても飛び地を含む市区町村全域を収める() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = """
        {"schemaVersion":2,"lods":[{"id":3,"intervalMeters":10}],"lodTransitions":[],"files":[
          {"id":"municipalities/3/13","layer":"municipalities","lod":3,"prefectureCode":"13","path":"area.geojson","bbox":[139,35,143,36]}
        ]}
        """
        let geoJSON = """
        {"type":"FeatureCollection","features":[{"type":"Feature","properties":{"c":"13101","n":"テスト区","p":"13"},"geometry":{"type":"MultiPolygon","coordinates":[
          [[[139,35],[140,35],[140,36],[139,36],[139,35]]],
          [[[142.99,35],[143,35],[143,35.01],[142.99,35.01],[142.99,35]]]
        ]}}]}
        """
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("manifest.json"))
        try Data(geoJSON.utf8).write(to: directory.appendingPathComponent("area.geojson"))
        let store = MunicipalityPuzzleStore(repository: BoundaryRepository(baseURL: directory))

        await store.prepareFocusRect(forMunicipality: "13101", prefectureCode: "13")
        let rect = try #require(store.focusRect(forMunicipality: "13101", containing: tokyo))

        #expect(store.municipalityPieces.isEmpty)
        #expect(rect.contains(MKMapPoint(CLLocationCoordinate2D(latitude: 35, longitude: 139))))
        #expect(rect.contains(MKMapPoint(CLLocationCoordinate2D(latitude: 35.01, longitude: 143))))
        #expect(rect.width > 100_000 * metersToMapPoints)
    }

    // MARK: - 補助

    private func square(centeredAt center: MKMapPoint, sideMeters: Double) -> MKMapRect {
        let side = sideMeters * metersToMapPoints
        return MKMapRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    private func corners(of rect: MKMapRect) -> [MKMapPoint] {
        [
            MKMapPoint(x: rect.minX, y: rect.minY), MKMapPoint(x: rect.maxX, y: rect.minY),
            MKMapPoint(x: rect.maxX, y: rect.maxY), MKMapPoint(x: rect.minX, y: rect.maxY),
        ]
    }

    private func polygon(_ rect: MKMapRect) -> MKPolygon {
        MKPolygon(points: corners(of: rect), count: 4)
    }

    /// 地図座標の計算は浮動小数点の丸めを含むため、1m相当未満の差は同じとみなす。
    private func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < metersToMapPoints
    }
}
