import MapKit

/// 記録するときに地図を寄せる範囲の決め方。記録する区域を丸ごと見せ、「ピースがはまる」様子を
/// 区域全体で見届けられるようにする。
///
/// 区域が複数の島に分かれている場合は、現在地のある島だけを収める。島ごと全部を収めると、
/// 離島を持つ市区町村(例: 本土と島嶼部)では区域が画面の中で小さくなりすぎるため。
nonisolated enum BoundaryFocusRect {
    /// 区域の外接矩形の上下左右に足す余白(各辺の長さに対する割合)。縁取りが画面の端に貼り付かないようにする。
    static let marginRatio = 0.12
    /// 一辺の下限(m)。区域が小さくても、従来の「現在地へ寄せる」表示範囲(1,200m四方)より寄りすぎないようにする。
    static let minimumSideMeters: CLLocationDistance = 1_200
    /// 市区町村に寄せる時の長い辺の上限(m)。広い区域(北海道の市町村など)を丸ごと映すと現在地周辺の道路が
    /// 読めなくなるため、これを超えたら現在地を中心に切り取る。
    /// 都道府県に寄せる時は、県の形そのものを見せたいので上限を設けない(呼び出し側がnilを渡す)。
    static let maximumSideMeters: CLLocationDistance = 100_000

    /// 区域の島(`islands`)から、寄せる範囲を決める。
    /// 現在地を含む島があればその島、無ければ最大の島を使う。島が1つも無ければnil(呼び出し側が従来の寄せ方に戻す)。
    /// `maximumSideMeters`がnilなら長い辺を切り取らない。
    static func rect(
        islands: [MKPolygon],
        containing coordinate: CLLocationCoordinate2D,
        maximumSideMeters: CLLocationDistance? = maximumSideMeters
    ) -> MKMapRect? {
        let point = MKMapPoint(coordinate)
        let containingIsland = islands.first { contains($0, point) }
        // 「最大」は外接矩形の面積で比べる。形の面積を求めるほどの精度は要らない(どの島を映すかを選ぶだけ)。
        let largestIsland = islands.max { area(of: $0.boundingMapRect) < area(of: $1.boundingMapRect) }
        guard let island = containingIsland ?? largestIsland else { return nil }
        return rect(enclosing: island.boundingMapRect, including: coordinate, maximumSideMeters: maximumSideMeters)
    }

    /// 区域の外接矩形`area`に現在地を含め、余白・下限・上限を適用した範囲。
    static func rect(
        enclosing area: MKMapRect,
        including coordinate: CLLocationCoordinate2D,
        maximumSideMeters: CLLocationDistance? = maximumSideMeters
    ) -> MKMapRect {
        let point = MKMapPoint(coordinate)
        // 現在地が区域の外(位置の誤差で境界のすぐ外にいる等)でも、自分の居場所が画面から外れないようにする。
        var rect = area.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        rect = rect.insetBy(dx: -rect.width * marginRatio, dy: -rect.height * marginRatio)

        let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        let minimumSide = minimumSideMeters * mapPointsPerMeter
        let widthShortage = max(0, minimumSide - rect.width)
        let heightShortage = max(0, minimumSide - rect.height)
        rect = rect.insetBy(dx: -widthShortage / 2, dy: -heightShortage / 2)

        // 上限を超えた辺だけを、現在地を中心とする長さに置き換える。区域との交わりにしないのは、
        // 現在地が区域の端にあると画面の端に寄ってしまい、自分の居場所の周りが片側しか見えなくなるため。
        guard let maximumSideMeters else { return rect }
        let maximumSide = maximumSideMeters * mapPointsPerMeter
        if rect.width > maximumSide {
            rect = MKMapRect(x: point.x - maximumSide / 2, y: rect.minY, width: maximumSide, height: rect.height)
        }
        if rect.height > maximumSide {
            rect = MKMapRect(x: rect.minX, y: point.y - maximumSide / 2, width: rect.width, height: maximumSide)
        }
        return rect
    }

    /// 点がポリゴンの内側にあるか(穴=飛び地の内側は外とみなす)。
    static func contains(_ polygon: MKPolygon, _ point: MKMapPoint) -> Bool {
        guard polygon.boundingMapRect.contains(point), ringContains(polygon, point) else { return false }
        let holes = polygon.interiorPolygons ?? []
        return !holes.contains { ringContains($0, point) }
    }

    /// 外周の輪1本についての内外判定(偶奇規則)。`MKPolygonRenderer`のpathを使う方法もあるが、
    /// 描画用のオブジェクトを判定のためだけに作らずに済むよう、座標列を直接たどる。
    private static func ringContains(_ polygon: MKPolygon, _ point: MKMapPoint) -> Bool {
        let points = UnsafeBufferPointer(start: polygon.points(), count: polygon.pointCount)
        guard points.count >= 3 else { return false }
        var isInside = false
        var previous = points[points.count - 1]
        for current in points {
            let crossesHorizontalLine = (current.y > point.y) != (previous.y > point.y)
            if crossesHorizontalLine {
                let crossingX = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
                if point.x < crossingX {
                    isInside.toggle()
                }
            }
            previous = current
        }
        return isInside
    }

    private static func area(of rect: MKMapRect) -> Double {
        rect.width * rect.height
    }
}
