import MapKit

/// 地図の縮尺(1ptあたりのm)。境界線の太さと、ヘッダーのページの自動切り替えの判断に使う。
nonisolated struct BoundaryMapScale: Equatable, Sendable {
    /// 画面の横幅(m)。
    let visibleWidthMeters: Double
    let metersPerPoint: Double

    /// カメラが止まったときの表示範囲(`MapCameraUpdateContext.rect`)と、その範囲を描く地図の横幅(pt)から求める。
    /// 横幅が0(レイアウト前)ならnil。
    init?(visibleRect: MKMapRect, mapWidthPoints: CGFloat) {
        guard mapWidthPoints > 0, visibleRect.width > 0 else { return nil }
        // 中心の緯度で換算する(メルカトル図法なので、同じ幅でも緯度によって実際の距離が変わる)。
        let centerLatitude = MKMapPoint(x: visibleRect.midX, y: visibleRect.midY).coordinate.latitude
        visibleWidthMeters = visibleRect.width / MKMapPointsPerMeterAtLatitude(centerLatitude)
        metersPerPoint = visibleWidthMeters / Double(mapWidthPoints)
    }
}

/// 境界線の太さ(pt)。拡大するほど太く、縮小するほど細くする。
///
/// MapKitの線の太さは画面上のptで固定され、縮尺に追従しない。全国表示に合わせた細さのままだと
/// 県・市区町村まで寄ったときに線が頼りなく、逆に寄ったときの太さのまま引くと小さな県や市区町村が
/// 線で塗りつぶされて潰れる。そこで縮尺の対数に比例して、両端の太さの間を補間する。
nonisolated struct BoundaryLineWidths: Equatable, Sendable {
    /// 県境・海岸線。塗られた都道府県の縁取りも同じ太さにする(下の灰色がはみ出して見えないように)。
    let prefectureBorder: CGFloat
    /// 市区町村のピースの線。
    let municipalityLine: CGFloat
    /// 現在地の市区町村の縁取り。県境の上に重なっても隠れないよう、常に県境より太くする。
    let currentOutline: CGFloat

    /// これより引いた縮尺(全国〜地方)では、最も細い太さにする。
    /// 県境1.2ptは全国表示で線同士が潰れ合わない上限(以前の固定値)。
    static let widestMetersPerPoint = 3_000.0
    /// これより寄った縮尺(市区町村全体が画面に収まる程度)では、最も太い太さにする。
    static let closestMetersPerPoint = 60.0
    /// 太さの段階数。カメラが止まるたびに少しずつ太さが変わると、そのたびに全ピースの描き直しが走るため、
    /// 段階に丸めて変化の回数を抑える。
    static let steps = 8.0

    static let prefectureBorderRange: ClosedRange<CGFloat> = 1.2...4.0
    static let municipalityLineRange: ClosedRange<CGFloat> = 0.6...2.8
    static let currentOutlineRange: ClosedRange<CGFloat> = 2.5...4.2

    /// 演出(`MapAreaEffectTimeline`)の線の太さを書いたときの基準。以前の固定値。
    private static let designedMunicipalityLine: CGFloat = 0.7
    private static let designedOutline: CGFloat = 2.5

    /// 最も引いた縮尺の太さ。縮尺がまだ分からない起動直後に使う(細い方が潰れる心配がない)。
    static let widest = BoundaryLineWidths(closeness: 0)

    init(scale: BoundaryMapScale) {
        self.init(closeness: Self.closeness(metersPerPoint: scale.metersPerPoint))
    }

    /// - Parameter closeness: 0(最も引いた縮尺)〜1(最も寄った縮尺)。
    private init(closeness: Double) {
        prefectureBorder = Self.interpolate(Self.prefectureBorderRange, closeness)
        municipalityLine = Self.interpolate(Self.municipalityLineRange, closeness)
        currentOutline = Self.interpolate(Self.currentOutlineRange, closeness)
    }

    /// 演出の市区町村の線を、今の縮尺に合わせて太らせる倍率。
    var pieceStrokeScale: Double {
        Double(municipalityLine / Self.designedMunicipalityLine)
    }

    /// 演出の縁取り(現在地・都道府県)を、今の縮尺に合わせて太らせる倍率。
    var outlineScale: Double {
        Double(currentOutline / Self.designedOutline)
    }

    /// 縮尺を0(引き)〜1(寄り)に換算し、`steps`段に丸める。
    static func closeness(metersPerPoint: Double) -> Double {
        guard metersPerPoint.isFinite, metersPerPoint > 0 else { return 0 }
        let clamped = min(max(metersPerPoint, closestMetersPerPoint), widestMetersPerPoint)
        let ratio = log(widestMetersPerPoint / clamped) / log(widestMetersPerPoint / closestMetersPerPoint)
        return (ratio * steps).rounded() / steps
    }

    private static func interpolate(_ range: ClosedRange<CGFloat>, _ closeness: Double) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(closeness)
    }
}

/// ユーザーが地図を拡大したときに、ヘッダーのページ(`MapProgressPage`)を市区町村へ切り替えるかの判断。
///
/// 都道府県ページのまま市区町村が見える縮尺まで寄ると、都道府県単位の塗りしか見えず「どこを回ったか」が分からない。
/// そこで、市区町村ページで区域へ寄せる縮尺(`BoundaryFocusRect`。多くの市区町村は数km〜数十km四方)の
/// 付近まで寄ったら、市区町村のパズル表示に切り替える。
nonisolated enum MapProgressPageZoomPolicy {
    /// 画面の横幅がこれ以下になったら市区町村ページにする。
    /// 都道府県ページで県全体へ寄せたとき(最も幅の狭い大阪府でも余白込みで60km前後)より十分狭くし、
    /// 県全体を見ている状態で切り替わらないようにしている。
    static let municipalityPageMaximumVisibleWidthMeters: CLLocationDistance = 40_000

    static func shouldSwitchToMunicipalities(visibleWidthMeters: CLLocationDistance) -> Bool {
        visibleWidthMeters <= municipalityPageMaximumVisibleWidthMeters
    }
}
