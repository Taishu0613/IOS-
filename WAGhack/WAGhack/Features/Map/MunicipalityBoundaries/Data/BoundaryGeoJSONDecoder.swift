import CoreLocation
import Foundation

/// 境界GeoJSON(FeatureCollection)を`AdministrativeBoundary`へ変換する。市区町村・都道府県の両レイヤに対応する。
///
/// 対応するのは`BoundaryData`の生成物の形式だけ(WGS84経緯度、Polygon/MultiPolygon、
/// properties は市区町村`{c, n, p}`/都道府県`{p, n}`)。汎用のGeoJSONパーサーにはしない。
nonisolated struct BoundaryGeoJSONDecoder {
    enum DecodingError: Error, Equatable {
        case unsupportedGeometry(type: String, code: String)
    }

    /// `pieceFilter`を渡すと、読み込みの時点で小さすぎる島を捨てる(メモリを抑えるため)。
    func decode(_ data: Data, pieceFilter: BoundaryPieceFilter? = nil) throws -> [AdministrativeBoundary] {
        let collection = try JSONDecoder().decode(FeatureCollection.self, from: data)
        return try collection.features.compactMap { feature in
            let boundary = try makeBoundary(from: feature)
            guard let pieceFilter else { return boundary }
            return pieceFilter.filtered(boundary)
        }
    }

    private func makeBoundary(from feature: Feature) throws -> AdministrativeBoundary {
        let rawPolygons: [[[[Double]]]]
        switch feature.geometry {
        case .polygon(let rings):
            rawPolygons = [rings]
        case .multiPolygon(let polygons):
            rawPolygons = polygons
        case .unsupported(let type):
            throw DecodingError.unsupportedGeometry(type: type, code: feature.properties.code)
        }

        let polygons = rawPolygons
            .compactMap(makePolygon)
            .sorted { $0.boundingBox.longerSideMeters > $1.boundingBox.longerSideMeters }
        return AdministrativeBoundary(
            code: feature.properties.code,
            name: feature.properties.n,
            prefectureCode: feature.properties.p,
            polygons: polygons
        )
    }

    /// GeoJSONのポリゴンは「先頭が外周、2つ目以降が穴」の輪の配列。
    private func makePolygon(from rings: [[[Double]]]) -> BoundaryPolygon? {
        let coordinateRings = rings.map { ring in ring.compactMap(makeCoordinate) }
        guard let exterior = coordinateRings.first,
              let boundingBox = GeoBoundingBox(enclosing: exterior) else { return nil }
        return BoundaryPolygon(exterior: exterior, holes: Array(coordinateRings.dropFirst()), boundingBox: boundingBox)
    }

    /// GeoJSONの座標は`[経度, 緯度]`の順。
    private func makeCoordinate(from position: [Double]) -> CLLocationCoordinate2D? {
        guard position.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: position[1], longitude: position[0])
    }
}

// MARK: - GeoJSONの形そのままのデコード用型

private nonisolated struct FeatureCollection: Decodable {
    let features: [Feature]
}

private nonisolated struct Feature: Decodable {
    /// キー名はファイルサイズ削減のため1文字。c: 行政区域コード / n: 名称 / p: 都道府県コード。
    /// 都道府県レイヤには`c`が無い。
    struct Properties: Decodable {
        let c: String?
        let n: String
        let p: String

        /// そのレイヤでの識別コード。市区町村なら行政区域コード、都道府県なら都道府県コード。
        var code: String { c ?? p }
    }

    let properties: Properties
    let geometry: Geometry
}

private nonisolated enum Geometry: Decodable {
    case polygon([[[Double]]])
    case multiPolygon([[[[Double]]]])
    case unsupported(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Polygon":
            self = .polygon(try container.decode([[[Double]]].self, forKey: .coordinates))
        case "MultiPolygon":
            self = .multiPolygon(try container.decode([[[[Double]]]].self, forKey: .coordinates))
        default:
            self = .unsupported(type)
        }
    }
}
