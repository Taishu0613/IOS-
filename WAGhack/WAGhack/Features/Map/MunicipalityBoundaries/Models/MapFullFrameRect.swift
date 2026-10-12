import MapKit

/// セーフエリアを除いた表示範囲から、地図のビュー全体(ヘッダーやシートの裏も含む)に映る範囲を求める。
///
/// 地図は上下のセーフエリアをヘッダー・シートの分だけ広げているため、`MapCameraUpdateContext`の範囲は
/// その内側しか含まない。これを基準に境界を読み込むと、半透明のヘッダーやシートの裏でピースが途切れて見える。
nonisolated enum MapFullFrameRect {
    /// - Parameters:
    ///   - visibleRect: セーフエリアを除いた表示範囲(`MapCameraUpdateContext.rect`)。
    ///   - mapHeight: 地図のビュー全体の高さ(pt)。
    ///   - topInset: 上に広げたセーフエリア(pt)。
    ///   - bottomInset: 下に広げたセーフエリア(pt)。
    /// セーフエリアを除いた高さが0以下(レイアウト前など)なら、換算できないので`visibleRect`をそのまま返す。
    static func rect(visibleRect: MKMapRect, mapHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> MKMapRect {
        let visibleHeightPoints = Double(mapHeight - topInset - bottomInset)
        guard visibleHeightPoints > 0, visibleRect.height > 0 else { return visibleRect }
        let mapPointsPerPoint = visibleRect.height / visibleHeightPoints
        let top = Double(topInset) * mapPointsPerPoint
        let bottom = Double(bottomInset) * mapPointsPerPoint
        return MKMapRect(
            x: visibleRect.minX,
            y: visibleRect.minY - top,
            width: visibleRect.width,
            height: visibleRect.height + top + bottom
        )
    }
}
