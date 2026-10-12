import Foundation

/// 未訪問の市区町村(灰色の網目)を描くかを、画面の横幅(m)から決める。
///
/// MapKitはポリゴン1枚ごとに描画を持つため、網目の枚数がそのまま操作の重さになる。網目を描かない間は
/// 県境と訪問済み・現在地のピースだけになり、見た目は「県表示」に近くなる。
///
/// 以前はLOD2(拡大時180km未満・縮小時230km超で切り替え)に入ったら描いていたが、LOD2の広い側では
/// 1画面に最大600枚前後が載って重かった。そこでLODとは別に、もう一段寄ってから描くようにしている。
/// LODと同じく拡大時と縮小時で閾値をずらし(ヒステリシス)、境目でわずかに動かしただけで
/// 網目が出たり消えたりして全ピースの追加・削除が走らないようにしている。
///
/// どちらの閾値もLOD2へ切り替わる幅(180km)より狭いので、網目を描くときは必ずLOD2以上の形が読み込まれている。
nonisolated enum UnvisitedMunicipalityVisibility {
    /// 画面の横幅がこれより狭くなったら網目を描き始める。
    /// 多くの市区町村は数km〜数十km四方で、最も広い市町村(岐阜県高山市など)へ寄せたとき
    /// (`BoundaryFocusRect`の余白込みで100km前後)にも網目が見えるよう、それより少し広くしている。
    static let showBelowMeters = 120_000.0
    /// 画面の横幅がこれより広くなったら網目を描くのをやめる。
    static let hideAboveMeters = 150_000.0

    /// 今描いているか(`isVisible`)と画面の横幅から、次に描くかを返す。
    static func isVisible(current isVisible: Bool, visibleWidthMeters width: Double) -> Bool {
        if isVisible {
            return width <= hideAboveMeters
        }
        return width < showBelowMeters
    }
}
