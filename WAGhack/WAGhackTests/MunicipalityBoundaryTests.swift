import CoreLocation
import Foundation
import MapKit
import Testing
@testable import WAGhack

struct BoundaryLODSelectorTests {
    /// manifest.json(buildRevision 2)と同じ切替距離。
    private let selector = BoundaryLODSelector(transitions: [
        BoundaryLODTransition(coarseLOD: 0, fineLOD: 1, zoomInBelowMeters: 700_000, zoomOutAboveMeters: 900_000),
        BoundaryLODTransition(coarseLOD: 1, fineLOD: 2, zoomInBelowMeters: 180_000, zoomOutAboveMeters: 230_000),
        BoundaryLODTransition(coarseLOD: 2, fineLOD: 3, zoomInBelowMeters: 45_000, zoomOutAboveMeters: 60_000),
    ])

    @Test func 全国表示ではLOD0のまま() {
        #expect(selector.lod(current: 0, visibleWidthMeters: 2_000_000) == 0)
    }

    @Test func 拡大して閾値を下回るとひとつ細かいLODへ進む() {
        #expect(selector.lod(current: 0, visibleWidthMeters: 699_000) == 1)
    }

    @Test func 切替の境目付近では今のLODを保つ() {
        // 700〜900kmの間は、拡大中ならLOD0、縮小中ならLOD1のまま動かない。
        #expect(selector.lod(current: 0, visibleWidthMeters: 800_000) == 0)
        #expect(selector.lod(current: 1, visibleWidthMeters: 800_000) == 1)
    }

    @Test func 一気に拡大しても最も細かいLODまで届く() {
        #expect(selector.lod(current: 0, visibleWidthMeters: 5_000) == 3)
    }

    @Test func 一気に縮小しても最も粗いLODまで戻る() {
        #expect(selector.lod(current: 3, visibleWidthMeters: 3_000_000) == 0)
    }

    @Test func 各LODが表示されうる最小の画面幅() {
        #expect(selector.coarsestLOD == 0)
        #expect(selector.minimumVisibleWidthMeters(of: 0) == 700_000)
        #expect(selector.minimumVisibleWidthMeters(of: 3) == 0)
    }
}

struct BoundaryPieceFilterTests {
    @Test func 画面幅の100分の1未満の島は省くが最大のピースは必ず残す() {
        // 画面幅400km → 4km未満の島は省く。
        let filter = BoundaryPieceFilter(visibleWidthMeters: 400_000)
        let boundary = AdministrativeBoundary(code: "13421", name: "小笠原村", prefectureCode: "13", polygons: [
            square(sideDegrees: 0.005), // 約0.5km: 先頭なので残る
            square(sideDegrees: 0.05),  // 約5.5km: 残る
            square(sideDegrees: 0.02),  // 約2km: 省く
        ])

        let filtered = filter.filtered(boundary)

        #expect(filtered?.polygons.count == 2)
        #expect(filter.shouldDraw(boundary.polygons[0], at: 0))
        #expect(!filter.shouldDraw(boundary.polygons[2], at: 2))
    }

    @Test func ポリゴンを持たない境界はnilになる() {
        let filter = BoundaryPieceFilter(visibleWidthMeters: 400_000)
        let empty = AdministrativeBoundary(code: "00000", name: "", prefectureCode: "00", polygons: [])
        #expect(filter.filtered(empty) == nil)
    }

    private func square(sideDegrees side: Double) -> BoundaryPolygon {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: side, longitude: 0),
            CLLocationCoordinate2D(latitude: side, longitude: side),
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
        ]
        return BoundaryPolygon(exterior: coordinates, holes: [], boundingBox: GeoBoundingBox(enclosing: coordinates)!)
    }
}

struct BoundaryGeoJSONDecoderTests {
    @Test func PolygonとMultiPolygonを読みピースを大きい順に並べる() throws {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"c":"13101","n":"千代田区","p":"13","r":"03"},
           "geometry":{"type":"Polygon","coordinates":[
             [[139.7,35.6],[139.8,35.6],[139.8,35.7],[139.7,35.6]],
             [[139.74,35.64],[139.75,35.64],[139.75,35.65],[139.74,35.64]]
           ]}},
          {"type":"Feature","properties":{"c":"13421","n":"小笠原村","p":"13","r":"03"},
           "geometry":{"type":"MultiPolygon","coordinates":[
             [[[142.1,27.0],[142.11,27.0],[142.11,27.01],[142.1,27.0]]],
             [[[142.1,26.6],[142.3,26.6],[142.3,26.8],[142.1,26.6]]]
           ]}}
        ]}
        """

        let boundaries = try BoundaryGeoJSONDecoder().decode(Data(json.utf8))

        #expect(boundaries.map(\.code) == ["13101", "13421"])
        let chiyoda = boundaries[0]
        #expect(chiyoda.name == "千代田区")
        #expect(chiyoda.prefectureCode == "13")
        #expect(chiyoda.polygons.first?.holes.count == 1)
        // GeoJSONは[経度, 緯度]の順。
        #expect(chiyoda.polygons.first?.exterior.first?.latitude == 35.6)
        #expect(chiyoda.polygons.first?.exterior.first?.longitude == 139.7)
        // 小笠原村は2つ目(大きい方の島)が先頭に来る。
        #expect(boundaries[1].polygons.first?.boundingBox.minLatitude == 26.6)
    }

    @Test func 都道府県レイヤは行政区域コードの代わりに都道府県コードで識別する() throws {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"p":"13","n":"東京都","r":"03"},
           "geometry":{"type":"Polygon","coordinates":[[[139.0,35.5],[139.9,35.5],[139.9,35.9],[139.0,35.5]]]}}
        ]}
        """

        let boundaries = try BoundaryGeoJSONDecoder().decode(Data(json.utf8))

        #expect(boundaries.first?.code == "13")
        #expect(boundaries.first?.name == "東京都")
    }

    @Test func 対応していないジオメトリは読み込みを失敗させる() {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"c":"99999","n":"線","p":"99"},
           "geometry":{"type":"LineString","coordinates":[[0,0],[1,1]]}}
        ]}
        """
        #expect(throws: BoundaryGeoJSONDecoder.DecodingError.unsupportedGeometry(type: "LineString", code: "99999")) {
            try BoundaryGeoJSONDecoder().decode(Data(json.utf8))
        }
    }
}

struct BoundaryLineGeoJSONDecoderTests {
    @Test func MultiLineStringを線ごとに分けファイルidと番号でidを振る() throws {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"p":"13","k":"border"},
           "geometry":{"type":"MultiLineString","coordinates":[
             [[139.0,35.5],[139.2,35.6],[139.4,35.7]],
             [[139.5,35.8],[139.6,35.9]]
           ]}},
          {"type":"Feature","properties":{"p":"13","k":"coast"},
           "geometry":{"type":"LineString","coordinates":[[139.8,35.6],[139.9,35.6],[139.9,35.7],[139.8,35.6]]}}
        ]}
        """

        let lines = try BoundaryLineGeoJSONDecoder().decode(Data(json.utf8), fileID: "prefecture_line_13_lod2")

        #expect(lines.map(\.id) == [
            "prefecture_line_13_lod2/0", "prefecture_line_13_lod2/1", "prefecture_line_13_lod2/2",
        ])
        #expect(lines.map(\.kind) == [.border, .border, .coast])
        // GeoJSONは[経度, 緯度]の順。
        #expect(lines[0].coordinates.first?.latitude == 35.5)
        #expect(lines[0].coordinates.first?.longitude == 139.0)
        #expect(!lines[0].isClosed)
        #expect(lines[2].isClosed)
    }

    @Test func 間引いても残った線のidは変わらない() throws {
        // 1本目は約0.1kmの小島の海岸線(閉じた線)。画面幅400km(4km未満を省く)で読み込み時に捨てる。
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"p":"13","k":"coast"},
           "geometry":{"type":"MultiLineString","coordinates":[
             [[139.0,35.0],[139.001,35.0],[139.001,35.001],[139.0,35.0]],
             [[139.0,34.0],[139.5,34.0],[139.5,34.5],[139.0,34.0]]
           ]}}
        ]}
        """

        let lines = try BoundaryLineGeoJSONDecoder().decode(
            Data(json.utf8), fileID: "f", pieceFilter: BoundaryPieceFilter(visibleWidthMeters: 400_000)
        )

        #expect(lines.map(\.id) == ["f/1"])
    }

    @Test func 開いた県境の線は短くても省かない() throws {
        // 約0.1kmの県境の一区間。省くと県境が途切れて見えるため残す。
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"p":"13","k":"border"},
           "geometry":{"type":"LineString","coordinates":[[139.0,35.0],[139.001,35.0]]}}
        ]}
        """

        let lines = try BoundaryLineGeoJSONDecoder().decode(
            Data(json.utf8), fileID: "f", pieceFilter: BoundaryPieceFilter(visibleWidthMeters: 400_000)
        )

        #expect(lines.count == 1)
    }

    @Test func 未知の線の種類は読み込みを失敗させる() {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"p":"13","k":"river"},
           "geometry":{"type":"LineString","coordinates":[[139.0,35.0],[139.1,35.0]]}}
        ]}
        """
        #expect(throws: BoundaryLineGeoJSONDecoder.DecodingError.unknownKind("river")) {
            try BoundaryLineGeoJSONDecoder().decode(Data(json.utf8), fileID: "f")
        }
    }
}

struct BoundaryPieceTests {
    @Test func 穴の無いピースは輪郭を別に持たずポリゴンの縁取りで描く() {
        let piece = BoundaryPiece(id: "lod2/municipalities/13210/0", code: "13210", shape: polygon(holes: []))

        #expect(piece.outlines == nil)
        #expect(piece.polygon.interiorPolygons?.isEmpty ?? true)
    }

    @Test func 穴のあるピースは塗り用に穴を残し輪郭は外周と穴を穴の無い形で持つ() {
        let hole = ring(minLongitude: 0.04, minLatitude: 0.04, side: 0.02)
        let piece = BoundaryPiece(id: "lod2/municipalities/11201/0", code: "11201", shape: polygon(holes: [hole]))

        // 塗りは飛び地を塗りつぶさないよう、穴を持ったまま。
        #expect(piece.polygon.interiorPolygons?.count == 1)
        // 縁取りは穴のあるポリゴンだと太く描かれるため、外周と穴をそれぞれ穴の無いポリゴンにする。
        let outlines = piece.outlines ?? []
        #expect(outlines.map(\.id) == ["lod2/municipalities/11201/0/outline/0", "lod2/municipalities/11201/0/outline/1"])
        #expect(outlines.allSatisfy { $0.polygon.interiorPolygons?.isEmpty ?? true })
        #expect(outlines.map(\.polygon.pointCount) == [5, hole.count])
    }

    private func polygon(holes: [[CLLocationCoordinate2D]]) -> BoundaryPolygon {
        let exterior = ring(minLongitude: 0, minLatitude: 0, side: 0.1)
        return BoundaryPolygon(exterior: exterior, holes: holes, boundingBox: GeoBoundingBox(enclosing: exterior)!)
    }

    /// 始点と終点が同じ、閉じた正方形の輪(5点)。
    private func ring(minLongitude: Double, minLatitude: Double, side: Double) -> [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: minLatitude, longitude: minLongitude),
            CLLocationCoordinate2D(latitude: minLatitude + side, longitude: minLongitude),
            CLLocationCoordinate2D(latitude: minLatitude + side, longitude: minLongitude + side),
            CLLocationCoordinate2D(latitude: minLatitude, longitude: minLongitude + side),
            CLLocationCoordinate2D(latitude: minLatitude, longitude: minLongitude),
        ]
    }
}

struct BoundaryManifestTests {
    @Test func 指定LODの市区町村ファイルのうち表示範囲に重なるものだけを選ぶ() throws {
        let json = """
        {"schemaVersion":2,"lods":[{"id":0,"intervalMeters":2000},{"id":1,"intervalMeters":500}],
         "lodTransitions":[{"coarseLOD":0,"fineLOD":1,"zoomInBelowMeters":700000,"zoomOutAboveMeters":900000}],
         "files":[
          {"id":"municipality_jp_lod0","layer":"municipalities","lod":0,"prefectureCode":null,
           "path":"municipalities/lod0_2000m/municipality_jp_lod0.geojson","bbox":[122.9,20.4,154.0,45.6]},
          {"id":"municipality_01_lod1","layer":"municipalities","lod":1,"prefectureCode":"01",
           "path":"municipalities/lod1_500m/municipality_01_lod1.geojson","bbox":[139.3,41.3,148.9,45.6]},
          {"id":"municipality_47_lod1","layer":"municipalities","lod":1,"prefectureCode":"47",
           "path":"municipalities/lod1_500m/municipality_47_lod1.geojson","bbox":[122.9,24.0,131.3,27.9]},
          {"id":"prefecture_47_lod1","layer":"prefectures","lod":1,"prefectureCode":"47",
           "path":"prefectures/lod1_500m/prefecture_47_lod1.geojson","bbox":[122.9,24.0,131.3,27.9]},
          {"id":"prefecture_line_47_lod1","layer":"prefectureLines","lod":1,"prefectureCode":"47",
           "path":"prefectureLines/lod1_500m/prefecture_line_47_lod1.geojson","bbox":[122.9,24.0,131.3,27.9]}
         ]}
        """
        let manifest = try JSONDecoder().decode(BoundaryManifest.self, from: Data(json.utf8))
        let naha = GeoBoundingBox(minLongitude: 127.5, minLatitude: 26.0, maxLongitude: 127.9, maxLatitude: 26.4)

        #expect(manifest.files(in: .municipalities, lod: 1, intersecting: naha).map(\.id) == ["municipality_47_lod1"])
        #expect(manifest.files(in: .municipalities, lod: 0, intersecting: naha).map(\.id) == ["municipality_jp_lod0"])
        #expect(manifest.files(in: .prefectures, lod: 1, intersecting: naha).map(\.id) == ["prefecture_47_lod1"])
        #expect(manifest.files(in: .prefectureLines, lod: 1, intersecting: naha).map(\.id) == ["prefecture_line_47_lod1"])
    }
}

struct PrefectureConquestLevelTests {
    /// 市区町村を`total`件持ち、そのうち先頭`visited`件を訪れた都道府県。
    private func prefecture(visited: Int, total: Int, isExplicitlyVisited: Bool = false) -> PrefectureExploration {
        let municipalities = (0..<total).map { index in
            ExplorationMunicipality(
                code: String(format: "13%03d", index), name: "市\(index)",
                prefectureCode: "13", prefectureName: "東京都", isPrefecture: false
            )
        }
        return PrefectureExploration(
            code: "13", name: "東京都", municipalities: municipalities,
            visitedCodes: Set(municipalities.prefix(visited).map(\.code)),
            isExplicitlyVisited: isExplicitlyVisited
        )
    }

    @Test func 記録が無い都道府県は未訪問() {
        #expect(PrefectureConquestLevel(prefecture(visited: 0, total: 8)) == .unvisited)
    }

    @Test func 都道府県単独の記録だけでも訪問済みの最初の段階になる() {
        #expect(PrefectureConquestLevel(prefecture(visited: 0, total: 8, isExplicitlyVisited: true)) == .started)
    }

    @Test func 達成バッジと同じ25パーセント刻みで段階が上がる() {
        #expect(PrefectureConquestLevel(prefecture(visited: 1, total: 8)) == .started)
        #expect(PrefectureConquestLevel(prefecture(visited: 2, total: 8)) == .quarter)
        #expect(PrefectureConquestLevel(prefecture(visited: 4, total: 8)) == .half)
        #expect(PrefectureConquestLevel(prefecture(visited: 6, total: 8)) == .threeQuarters)
        #expect(PrefectureConquestLevel(prefecture(visited: 7, total: 8)) == .threeQuarters)
    }

    @Test func すべての市区町村を訪れると完全踏破() {
        #expect(PrefectureConquestLevel(prefecture(visited: 8, total: 8)) == .complete)
    }
}
