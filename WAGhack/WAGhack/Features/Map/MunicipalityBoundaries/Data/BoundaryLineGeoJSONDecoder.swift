import CoreLocation
import Foundation

/// 県境・海岸線のGeoJSON(FeatureCollection)を`BoundaryLine`へ変換する。
///
/// 対応するのは`BoundaryData`の`prefectureLines`レイヤの形式だけ(WGS84経緯度、LineString/MultiLineString、
/// properties `{p, k}`。kは`border`/`coast`)。1つのFeatureに同じ種類の線が多数まとめて入っている。
nonisolated struct BoundaryLineGeoJSONDecoder {
    enum DecodingError: Error, Equatable {
        case unsupportedGeometry(type: String)
        case unknownKind(String)
    }

    /// `fileID`は各線のidの接頭辞にする。`pieceFilter`を渡すと、読み込みの時点で小さすぎる島の海岸線を捨てる
    /// (メモリを抑えるため)。idの番号は捨てる前の並びで振るので、フィルタに関係なく同じ線は同じidになる。
    func decode(_ data: Data, fileID: String, pieceFilter: BoundaryPieceFilter? = nil) throws -> [BoundaryLine] {
        let collection = try JSONDecoder().decode(LineFeatureCollection.self, from: data)
        var result: [BoundaryLine] = []
        var index = 0
        for feature in collection.features {
            guard let kind = BoundaryLine.Kind(rawValue: feature.properties.k) else {
                throw DecodingError.unknownKind(feature.properties.k)
            }
            let rawLines: [[[Double]]]
            switch feature.geometry {
            case .lineString(let line):
                rawLines = [line]
            case .multiLineString(let lines):
                rawLines = lines
            case .unsupported(let type):
                throw DecodingError.unsupportedGeometry(type: type)
            }
            for rawLine in rawLines {
                defer { index += 1 }
                guard let line = makeLine(id: "\(fileID)/\(index)", kind: kind, from: rawLine) else { continue }
                if let pieceFilter, !pieceFilter.shouldDraw(line) { continue }
                result.append(line)
            }
        }
        return result
    }

    /// GeoJSONの座標は`[経度, 緯度]`の順。
    private func makeLine(id: String, kind: BoundaryLine.Kind, from positions: [[Double]]) -> BoundaryLine? {
        let coordinates = positions.compactMap { position -> CLLocationCoordinate2D? in
            guard position.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: position[1], longitude: position[0])
        }
        guard coordinates.count >= 2, let boundingBox = GeoBoundingBox(enclosing: coordinates) else { return nil }
        return BoundaryLine(id: id, kind: kind, coordinates: coordinates, boundingBox: boundingBox)
    }
}

// MARK: - GeoJSONの形そのままのデコード用型

private nonisolated struct LineFeatureCollection: Decodable {
    let features: [LineFeature]
}

private nonisolated struct LineFeature: Decodable {
    /// k: 線の種類(`border`=県境 / `coast`=海岸線)。所有する都道府県コード`p`もあるがアプリでは使わない。
    struct Properties: Decodable {
        let k: String
    }

    let properties: Properties
    let geometry: LineGeometry
}

private nonisolated enum LineGeometry: Decodable {
    case lineString([[Double]])
    case multiLineString([[[Double]]])
    case unsupported(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "LineString":
            self = .lineString(try container.decode([[Double]].self, forKey: .coordinates))
        case "MultiLineString":
            self = .multiLineString(try container.decode([[[Double]]].self, forKey: .coordinates))
        default:
            self = .unsupported(type)
        }
    }
}
