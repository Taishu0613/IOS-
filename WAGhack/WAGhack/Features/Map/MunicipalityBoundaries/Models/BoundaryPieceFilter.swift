import Foundation

/// 縮尺に対して小さすぎる島(ピース)を省く規則。
///
/// 日本には約12.5万の島があり、すべて地図に載せると描画が破綻する。
/// そこで「画面上で約4pt(画面幅の1/100)未満のピースは描かない」と決めている。
/// 4pt未満の島は輪郭線(1.2pt)を付けると点の塊にしか見えず、海岸沿いに並ぶと線が太い帯のように見えるため。
/// 縮尺に対する割合なので、拡大すれば小さな島も現れる。
/// ただし各行政単位で最大のピースだけは必ず残し、どれだけ縮小しても市区町村・都道府県そのものは消えないようにする。
///
/// データ生成(`BoundaryData`の`prune-and-round`)も同じ規則で、そのLODでは絶対に描かれない島をあらかじめ捨てている
/// (以前はLOD0だけで約12MBあり、起動直後の読み込みが実機で数秒かかっていた)。
/// ここでの絞り込みは、LODの中でさらに縮小したときの分として引き続き必要。
nonisolated struct BoundaryPieceFilter: Sendable {
    /// 画面幅の何分の1未満を「小さすぎる」とみなすか。iPhoneの論理幅(約400pt)で約4ptに当たる。
    /// データ生成の`APP_SCREEN_RESOLUTION`(boundary_tools.mjs)と同じ値にすること。ここだけ大きくして
    /// より小さい島まで描こうとしても、データを作り直さないとその島はファイルに入っていない。
    static let screenResolution = 100.0

    let minimumPieceMeters: Double

    init(visibleWidthMeters: Double) {
        minimumPieceMeters = visibleWidthMeters / Self.screenResolution
    }

    /// `AdministrativeBoundary.polygons`の`index`番目のピースを描くか。先頭(最大のピース)は常に描く。
    func shouldDraw(_ polygon: BoundaryPolygon, at index: Int) -> Bool {
        index == 0 || polygon.boundingBox.longerSideMeters >= minimumPieceMeters
    }

    /// 県境・海岸線を描くか。省くのは一周している小さな島の海岸線だけ。
    /// 開いた線は長い県境の一区間であることがあり、短くても省くと県境が途切れて見えるため必ず描く。
    func shouldDraw(_ line: BoundaryLine) -> Bool {
        !line.isClosed || line.boundingBox.longerSideMeters >= minimumPieceMeters
    }

    /// ピースを省いた境界を返す。1つもピースがなければnil。
    func filtered(_ boundary: AdministrativeBoundary) -> AdministrativeBoundary? {
        let pieces = boundary.polygons.enumerated()
            .filter { index, polygon in shouldDraw(polygon, at: index) }
            .map(\.element)
        guard !pieces.isEmpty else { return nil }
        return AdministrativeBoundary(
            code: boundary.code, name: boundary.name, prefectureCode: boundary.prefectureCode, polygons: pieces
        )
    }
}
