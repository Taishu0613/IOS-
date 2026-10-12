import Foundation

/// 隣り合う2つのLODの切替条件。`manifest.json`の`lodTransitions`の1要素。
///
/// 拡大時と縮小時で閾値をずらして(ヒステリシス)、境目付近でわずかに動かしただけで
/// LODが行ったり来たりしてファイルを読み直さないようにしている。
nonisolated struct BoundaryLODTransition: Decodable, Equatable, Sendable {
    let coarseLOD: Int
    let fineLOD: Int
    /// 画面の横幅がこれより狭くなったら細かい方へ切り替える。
    let zoomInBelowMeters: Double
    /// 画面の横幅がこれより広くなったら粗い方へ戻す。
    let zoomOutAboveMeters: Double
}

/// 画面の横幅(m)から、使うLODを決める。状態を持たない純粋な計算なので単体テストできる。
nonisolated struct BoundaryLODSelector: Sendable {
    let transitions: [BoundaryLODTransition]

    /// 最も粗いLOD。初期表示やLODが未確定のときに使う。
    var coarsestLOD: Int {
        transitions.map(\.coarseLOD).min() ?? 0
    }

    /// 現在のLODと画面の横幅から、次に使うLODを返す。
    ///
    /// 全国表示から市区町村表示まで一気にズームした場合も正しいLODへ届くよう、
    /// 条件を満たす間は1段ずつ繰り返し進める。
    func lod(current: Int, visibleWidthMeters width: Double) -> Int {
        var lod = current
        while let finer = transitions.first(where: { $0.coarseLOD == lod }), width < finer.zoomInBelowMeters {
            lod = finer.fineLOD
        }
        while let coarser = transitions.first(where: { $0.fineLOD == lod }), width > coarser.zoomOutAboveMeters {
            lod = coarser.coarseLOD
        }
        return lod
    }

    /// そのLODが表示されうる最小の画面幅(m)。これより拡大されると細かいLODへ切り替わる。
    /// 最も細かいLODは際限なく拡大できるので0を返す。
    func minimumVisibleWidthMeters(of lod: Int) -> Double {
        transitions.first { $0.coarseLOD == lod }?.zoomInBelowMeters ?? 0
    }
}
