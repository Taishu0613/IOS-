import CoreGraphics
import CoreLocation

/// 踏破率ヘッダーの小さな枠に描く地図。区画(都道府県または市区町村)ごとに形を持ち、訪問済みの区画だけ色を変えられる。
///
/// 座標は枠の左上を原点に、横・縦それぞれ0〜1へ正規化してある(yは下向き)。
/// 枠からはみ出す部分は0〜1を超えることがある(描画側で切り取る)。
nonisolated struct SilhouetteMap: Sendable {
    struct Area: Sendable {
        /// 都道府県コード(2桁)または行政区域コード(5桁)。訪問済みの判定に使う。
        let code: String
        /// 島ごとの外周。始点と終点は同じ点。穴(飛び地)はこの大きさでは見えないので持たない。
        let rings: [[CGPoint]]
    }

    let areas: [Area]
    /// 横÷縦。描画側はこの比率を保ったまま枠に収める。
    let aspectRatio: CGFloat
    /// 本体と縮尺を変えて差し込んだ小窓(日本地図の沖縄)の囲み。無ければnil。
    let insetFrame: CGRect?
}

/// 境界データから、サムネイル用の軽い地図を作る。状態を持たない純粋な計算なので単体テストできる。
///
/// 境界データは数十pt四方に描くには細かすぎる(北海道だけで数千の島がある)ため、
/// 描画サイズ(pt)を基準に「小さい島を捨てる」「頂点を間引く」の2段階で軽くする。
nonisolated struct BoundarySilhouetteBuilder: Sendable {
    /// 想定する描画サイズ(pt)。枠の長い方の辺がこの長さになる前提で、捨てる島の大きさ・間引きの細かさを決める。
    let targetPoints: CGFloat

    /// 頂点を間引くときの許容誤差(pt)。1.5ptでは半島や湾が消えて県の形が分からなくなったため、
    /// 1pt未満に抑えている。それでも1区画あたり数十〜百数十頂点に収まり、描画の負担は小さい。
    static let simplificationTolerance: CGFloat = 0.4
    /// これより小さい島(pt)は描かない。点の粒にしか見えないため。
    static let minimumPieceSize: CGFloat = 1.5
    /// 都道府県の地図で、本土から離れた島を描く最小の大きさ(pt、`targetPoints`基準)。
    /// 小さな離島は省き、佐渡島・淡路島(96ptの地図でそれぞれ約27pt・約33pt)のように県の形の一部と言える島だけを残す。
    static let minimumIslandSize: CGFloat = 10

    /// 日本地図の本体として切り取る範囲。北海道〜九州(対馬・五島を含む)。
    ///
    /// 沖縄まで入れると本州が小さくなりすぎて形が分からないため、沖縄県は左上の小窓に縮尺を変えて描く。
    /// 奄美・小笠原などこの範囲の外にある離島は描かない。
    static let japanMainlandFrame = GeoBoundingBox(minLongitude: 128.5, minLatitude: 30.9, maxLongitude: 146.0, maxLatitude: 45.6)
    /// 小窓に描く都道府県(沖縄県)。
    static let japanInsetPrefectureCode = "47"
    /// 小窓の大きさ(枠の長い辺に対する割合)。沖縄本島が本体の九州と同じくらいの大きさに見える程度。
    static let japanInsetScale: CGFloat = 0.2

    /// 日本地図。沖縄県は左上の小窓に、沖縄本島を枠いっぱいに描く(左上は日本海で本体と重ならない)。
    func japanMap(of prefectures: [AdministrativeBoundary]) -> SilhouetteMap {
        let projection = SilhouetteProjection(frame: Self.japanMainlandFrame, targetPoints: targetPoints)
        var areas = prefectures
            .filter { $0.code != Self.japanInsetPrefectureCode }
            .compactMap { area(of: $0, with: projection, keeping: Self.keepsPieceBySize) }

        var insetFrame: CGRect?
        if let okinawa = prefectures.first(where: { $0.code == Self.japanInsetPrefectureCode }),
           let mainIsland = okinawa.polygons.first {
            let insetProjection = SilhouetteProjection(frame: mainIsland.boundingBox, targetPoints: targetPoints * Self.japanInsetScale)
            // 小窓の囲みと本体の端の間に少し余白を取る。
            let margin: CGFloat = 1.5
            let rings = projectedRings(of: okinawa, with: insetProjection, keeping: Self.keepsPieceBySize).map { ring in
                ring.map { projection.normalized(CGPoint(x: $0.x + margin * 2, y: $0.y + margin * 2)) }
            }
            if !rings.isEmpty {
                areas.append(SilhouetteMap.Area(code: okinawa.code, rings: rings))
                let origin = projection.normalized(CGPoint(x: margin, y: margin))
                let end = projection.normalized(CGPoint(
                    x: insetProjection.width + margin * 3,
                    y: insetProjection.height + margin * 3
                ))
                insetFrame = CGRect(x: origin.x, y: origin.y, width: end.x - origin.x, height: end.y - origin.y)
            }
        }
        return SilhouetteMap(areas: areas, aspectRatio: projection.aspectRatio, insetFrame: insetFrame)
    }

    /// 1つの都道府県を市区町村ごとに分けた地図。都道府県の形が無ければnil。
    ///
    /// 枠は都道府県の最も大きいピース(本土)を囲む範囲にする。東京都は沖ノ鳥島・南鳥島まで含めると範囲が
    /// 太平洋全体に広がり、本土が点になってしまうため。
    /// 描くのは本土に載っているピースと大きな島だけ。小さな離島だけでできた町村は描かない(地図に出てこない)。
    func prefectureMap(of prefecture: AdministrativeBoundary, municipalities: [AdministrativeBoundary]) -> SilhouetteMap? {
        guard let mainland = prefecture.polygons.first else { return nil }
        let projection = SilhouetteProjection(frame: mainland.boundingBox, targetPoints: targetPoints)
        let mainlandPoints = mainland.exterior.map(projection.point)
        // 本土かどうかの判定用。元の頂点数(北海道で数万)のままだと判定が重いので、描画と同じ細かさに間引く。
        let mainlandRing = Self.simplifiedRing(mainlandPoints, tolerance: Self.simplificationTolerance) ?? mainlandPoints
        let areas = municipalities.compactMap { municipality in
            area(of: municipality, with: projection) { ring, _ in
                ring.longerSide >= Self.minimumIslandSize || ring.isOnMainland(mainlandRing)
            }
        }
        guard !areas.isEmpty else { return nil }
        return SilhouetteMap(areas: areas, aspectRatio: projection.aspectRatio, insetFrame: nil)
    }

    /// 1つの市区町村だけの地図。枠はその市区町村の最も大きいピースに合わせ、枠に掛からない離島は描かない。
    func municipalityMap(of municipality: AdministrativeBoundary) -> SilhouetteMap? {
        guard let largest = municipality.polygons.first else { return nil }
        let projection = SilhouetteProjection(frame: largest.boundingBox, targetPoints: targetPoints)
        guard let area = area(of: municipality, with: projection, keeping: Self.keepsPieceBySize) else { return nil }
        return SilhouetteMap(areas: [area], aspectRatio: projection.aspectRatio, insetFrame: nil)
    }

    /// 大きさだけで選ぶ規則(日本地図・市区町村単体の地図)。各行政単位の最大のピースは小さくても必ず残し、
    /// 小さな県が消えて日本地図に穴が空かないようにする。
    private static func keepsPieceBySize(_ ring: [CGPoint], isRepresentative: Bool) -> Bool {
        isRepresentative || ring.longerSide >= minimumPieceSize
    }

    private func area(
        of boundary: AdministrativeBoundary,
        with projection: SilhouetteProjection,
        keeping shouldKeep: ([CGPoint], _ isRepresentative: Bool) -> Bool
    ) -> SilhouetteMap.Area? {
        let rings = projectedRings(of: boundary, with: projection, keeping: shouldKeep)
        guard !rings.isEmpty else { return nil }
        return SilhouetteMap.Area(code: boundary.code, rings: rings.map { $0.map(projection.normalized) })
    }

    /// 枠に掛かるピースを、pt単位の座標にして間引いたもの。残すかどうかは`shouldKeep`で決める
    /// (`isRepresentative`はその行政単位の最大のピースか)。
    private func projectedRings(
        of boundary: AdministrativeBoundary,
        with projection: SilhouetteProjection,
        keeping shouldKeep: ([CGPoint], _ isRepresentative: Bool) -> Bool
    ) -> [[CGPoint]] {
        var rings: [[CGPoint]] = []
        for (index, polygon) in boundary.polygons.enumerated() {
            guard polygon.boundingBox.intersects(projection.frame) else { continue }
            let isRepresentative = index == 0
            let points = polygon.exterior.map(projection.point)
            // 小さすぎて通常の許容誤差では三角形も残らない場合、代表のピースだけは細かく間引き直す。
            let simplified = Self.simplifiedRing(points, tolerance: Self.simplificationTolerance)
                ?? (isRepresentative ? Self.simplifiedRing(points, tolerance: Self.simplificationTolerance / 8) : nil)
            guard let ring = simplified, shouldKeep(ring, isRepresentative) else { continue }
            rings.append(ring)
        }
        return rings
    }

    /// 閉じた輪(始点=終点)をDouglas-Peuckerで間引く。三角形も残らなければnil。
    ///
    /// 閉じた輪は始点と終点が同じ点で基準線が引けないため、始点から最も遠い点で2本に分けてそれぞれを間引く。
    static func simplifiedRing(_ ring: [CGPoint], tolerance: CGFloat) -> [CGPoint]? {
        // 始点=終点を含めて4点(=異なる3点)未満は面にならない。
        guard ring.count >= 4 else { return nil }
        let start = ring[0]
        let farthestIndex = ring.indices.max { start.distance(to: ring[$0]) < start.distance(to: ring[$1]) } ?? 0
        guard farthestIndex > 0, farthestIndex < ring.count - 1 else { return nil }

        let firstHalf = simplifiedLine(Array(ring[...farthestIndex]), tolerance: tolerance)
        let secondHalf = simplifiedLine(Array(ring[farthestIndex...]), tolerance: tolerance)
        let simplified = firstHalf + secondHalf.dropFirst()
        return simplified.count >= 4 ? simplified : nil
    }

    /// 開いた線をDouglas-Peuckerで間引く。始点と終点は必ず残す。
    /// 頂点数の多い海岸線で再帰が深くならないよう、スタックで繰り返す。
    static func simplifiedLine(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keeps = [Bool](repeating: false, count: points.count)
        keeps[0] = true
        keeps[points.count - 1] = true
        var ranges = [(start: 0, end: points.count - 1)]

        while let range = ranges.popLast() {
            guard range.end > range.start + 1 else { continue }
            var farthestIndex = range.start
            var farthestDistance: CGFloat = 0
            for index in (range.start + 1)..<range.end {
                let distance = points[index].distance(toSegmentFrom: points[range.start], to: points[range.end])
                if distance > farthestDistance {
                    farthestIndex = index
                    farthestDistance = distance
                }
            }
            guard farthestDistance > tolerance else { continue }
            keeps[farthestIndex] = true
            ranges.append((range.start, farthestIndex))
            ranges.append((farthestIndex, range.end))
        }
        return points.indices.filter { keeps[$0] }.map { points[$0] }
    }
}

/// 経緯度を、枠の左上を原点とするpt単位の平面座標へ写す。
///
/// 小さなサムネイル用なので正確な地図投影はせず、枠の中央の緯度で経度方向を縮めるだけ(正距円筒図法の補正)にしている。
/// 日本全体でも南北の歪みは見た目で気にならない程度に収まる。
private nonisolated struct SilhouetteProjection {
    let frame: GeoBoundingBox
    /// 経度1度が緯度1度の何倍の長さか(= cos(中央の緯度))。
    private let longitudeScale: Double
    /// 緯度1度あたりのpt。
    private let pointsPerDegree: Double
    /// 枠の大きさ(pt)。
    let width: CGFloat
    let height: CGFloat

    init(frame: GeoBoundingBox, targetPoints: CGFloat) {
        self.frame = frame
        let centerLatitude = (frame.minLatitude + frame.maxLatitude) / 2
        longitudeScale = cos(centerLatitude * .pi / 180)
        let widthDegrees = (frame.maxLongitude - frame.minLongitude) * longitudeScale
        let heightDegrees = frame.maxLatitude - frame.minLatitude
        // 幅・高さが0の枠(点や線)でも割り算が破綻しないよう、ごく小さい値で下支えする。
        pointsPerDegree = Double(targetPoints) / max(widthDegrees, heightDegrees, .ulpOfOne)
        width = max(widthDegrees * pointsPerDegree, .ulpOfOne)
        height = max(heightDegrees * pointsPerDegree, .ulpOfOne)
    }

    var aspectRatio: CGFloat { width / height }

    func point(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        CGPoint(
            x: (coordinate.longitude - frame.minLongitude) * longitudeScale * pointsPerDegree,
            y: (frame.maxLatitude - coordinate.latitude) * pointsPerDegree
        )
    }

    /// pt単位の座標を、枠に対する0〜1の割合にする。
    func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / width, y: point.y / height)
    }

    /// 経緯度の矩形の、長い方の辺の長さ(pt)。
    func longerSide(of box: GeoBoundingBox) -> CGFloat {
        let boxWidth = (box.maxLongitude - box.minLongitude) * longitudeScale * pointsPerDegree
        let boxHeight = (box.maxLatitude - box.minLatitude) * pointsPerDegree
        return max(boxWidth, boxHeight)
    }
}

private nonisolated extension Array where Element == CGPoint {
    /// 点を囲む矩形の、長い方の辺の長さ。
    var longerSide: CGFloat {
        guard let first else { return 0 }
        var minPoint = first
        var maxPoint = first
        for point in dropFirst() {
            minPoint = CGPoint(x: Swift.min(minPoint.x, point.x), y: Swift.min(minPoint.y, point.y))
            maxPoint = CGPoint(x: Swift.max(maxPoint.x, point.x), y: Swift.max(maxPoint.y, point.y))
        }
        return Swift.max(maxPoint.x - minPoint.x, maxPoint.y - minPoint.y)
    }

    /// この輪が本土(`mainland`)の上に載っているか。
    ///
    /// 本土の市区町村は隣の市区町村との境に本土の内側の頂点を必ず持つので、頂点のどれかが本土の内側にあれば本土とみなす。
    /// 海岸線上の頂点は本土の輪の上にあり内外の判定が揺れるため、それだけに頼らない。
    /// 隣が無い小さな区画のために、頂点の平均(おおよその中心)も調べる。離島は頂点も中心も本土の外にある。
    func isOnMainland(_ mainland: [CGPoint]) -> Bool {
        guard !isEmpty else { return false }
        if contains(where: { $0.isInside(mainland) }) { return true }
        let center = CGPoint(
            x: reduce(0) { $0 + $1.x } / CGFloat(count),
            y: reduce(0) { $0 + $1.y } / CGFloat(count)
        )
        return center.isInside(mainland)
    }
}

private nonisolated extension CGPoint {
    /// 閉じた輪の内側にあるか(偶奇規則のレイキャスト)。
    func isInside(_ ring: [CGPoint]) -> Bool {
        var isInside = false
        var previous = ring.last ?? self
        for current in ring {
            if (current.y > y) != (previous.y > y),
               x < (previous.x - current.x) * (y - current.y) / (previous.y - current.y) + current.x {
                isInside.toggle()
            }
            previous = current
        }
        return isInside
    }

    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    /// 線分(start→end)までの最短距離。線分が点に潰れている場合はその点までの距離。
    func distance(toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let segmentX = end.x - start.x
        let segmentY = end.y - start.y
        let lengthSquared = segmentX * segmentX + segmentY * segmentY
        guard lengthSquared > 0 else { return distance(to: start) }
        let projected = ((x - start.x) * segmentX + (y - start.y) * segmentY) / lengthSquared
        let clamped = min(max(projected, 0), 1)
        return distance(to: CGPoint(x: start.x + clamped * segmentX, y: start.y + clamped * segmentY))
    }
}
