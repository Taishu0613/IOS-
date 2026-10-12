import CoreLocation

/// 経緯度の矩形。GeoJSONの`bbox`(`[西, 南, 東, 北]`)と同じ並びで扱う。
///
/// 画面に入っているか・十分な大きさがあるかの判定にだけ使うため、日付変更線をまたぐ矩形は考慮しない
/// (日本の行政区域はまたがない)。
nonisolated struct GeoBoundingBox: Equatable, Sendable {
    let minLongitude: Double
    let minLatitude: Double
    let maxLongitude: Double
    let maxLatitude: Double

    /// GeoJSON/manifestの`bbox`配列から作る。要素数が4でなければnil。
    init?(geoJSON values: [Double]) {
        guard values.count == 4 else { return nil }
        self.init(minLongitude: values[0], minLatitude: values[1], maxLongitude: values[2], maxLatitude: values[3])
    }

    init(minLongitude: Double, minLatitude: Double, maxLongitude: Double, maxLatitude: Double) {
        self.minLongitude = minLongitude
        self.minLatitude = minLatitude
        self.maxLongitude = maxLongitude
        self.maxLatitude = maxLatitude
    }

    /// 座標列を囲む最小の矩形。空配列ならnil。
    init?(enclosing coordinates: [CLLocationCoordinate2D]) {
        guard let first = coordinates.first else { return nil }
        var box = (minLongitude: first.longitude, minLatitude: first.latitude,
                   maxLongitude: first.longitude, maxLatitude: first.latitude)
        for coordinate in coordinates.dropFirst() {
            box.minLongitude = min(box.minLongitude, coordinate.longitude)
            box.minLatitude = min(box.minLatitude, coordinate.latitude)
            box.maxLongitude = max(box.maxLongitude, coordinate.longitude)
            box.maxLatitude = max(box.maxLatitude, coordinate.latitude)
        }
        self.init(minLongitude: box.minLongitude, minLatitude: box.minLatitude,
                  maxLongitude: box.maxLongitude, maxLatitude: box.maxLatitude)
    }

    func intersects(_ other: GeoBoundingBox) -> Bool {
        minLongitude <= other.maxLongitude && other.minLongitude <= maxLongitude
            && minLatitude <= other.maxLatitude && other.minLatitude <= maxLatitude
    }

    /// 縦横のうち長い方の辺の長さ(m)。島の大きさを比べる用途の概算なので、中央の緯度で経度方向を補正するだけにしている。
    var longerSideMeters: Double {
        let metersPerDegreeLatitude = 110_540.0
        let centerLatitude = (minLatitude + maxLatitude) / 2
        let metersPerDegreeLongitude = 111_320.0 * cos(centerLatitude * .pi / 180)
        let width = (maxLongitude - minLongitude) * metersPerDegreeLongitude
        let height = (maxLatitude - minLatitude) * metersPerDegreeLatitude
        return max(width, height)
    }
}

/// 穴(飛び地を囲む内側の輪)を含む1つのポリゴン。島ごとに1つ。
nonisolated struct BoundaryPolygon: Sendable {
    let exterior: [CLLocationCoordinate2D]
    let holes: [[CLLocationCoordinate2D]]
    let boundingBox: GeoBoundingBox
}

/// 1つの行政単位(市区町村または都道府県)の境界。島を持つ場合は複数のポリゴンを持つ。
nonisolated struct AdministrativeBoundary: Identifiable, Sendable {
    /// 市区町村なら行政区域コード(5桁、`Municipality.code`と一致)、都道府県なら都道府県コード(2桁)。
    let code: String
    let name: String
    let prefectureCode: String
    /// 大きい順に並べる。先頭は「その行政単位を代表するピース」として、どれだけ縮小しても描く。
    let polygons: [BoundaryPolygon]

    var id: String { code }
}

/// 県境または海岸線の1本の線。県境は隣り合う2県のどちらか一方だけが持つので、同じ線を2回描かない。
nonisolated struct BoundaryLine: Identifiable, Sendable {
    enum Kind: String, Sendable {
        /// 都道府県どうしの境。
        case border
        /// 海岸線(陸地の外周)。島ごとに閉じた線になる。
        case coast
    }

    /// ファイルidとファイル内の番号の組み合わせ。同じファイルを読めば常に同じidになる。
    let id: String
    let kind: Kind
    let coordinates: [CLLocationCoordinate2D]
    let boundingBox: GeoBoundingBox

    /// 始点と終点が同じ(島の海岸線のように一周している)か。
    var isClosed: Bool {
        guard let first = coordinates.first, let last = coordinates.last, coordinates.count > 2 else { return false }
        return first.latitude == last.latitude && first.longitude == last.longitude
    }
}
