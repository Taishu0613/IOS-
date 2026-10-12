import MapKit
import SwiftUI

/// 市区町村のピースと県境を地図に敷くレイヤ。`Map { }`の中にそのまま置く。
///
/// 形は`MunicipalityPuzzleStore`から、訪問済みかどうかはSwiftDataの記録から受け取り、
/// ここで組み合わせて塗り分けるだけにする(状態は持たない)。
///
/// 重なりの階層(`mapOverlayLevel`):
/// - 下(`.aboveRoads`、地名ラベルより下): 市区町村のピースの塗りと細い線、または都道府県の制覇率の塗り。塗っても地名が読める。
///   県境・海岸線の線(`MapPolyline`)もこの階層に置く(上の階層に置くと描かれないため。理由は描画箇所のコメント参照)。
/// - 上(`.aboveLabels`): 現在地の縁取り。線だけなので地名はほぼ隠れない。
///
/// 記録・脈打ちの演出(`emphasis`)は、該当する区域のスタイルを差し替えるだけで描く。ポリゴンを足したり
/// 消したりしないのは、MapKitがポリゴン1枚ごとに描画を持ち、追加・削除のたびに作り直しが走って重くなるため。
struct MunicipalityPuzzleLayer: MapContent {
    let municipalityPieces: [BoundaryPiece]
    let prefectureBorders: [BoundaryLinePiece]
    /// 都道府県の面。制覇率の塗り(`prefectureConquestLevels`)にだけ使う。
    let prefectureAreas: [BoundaryPiece]
    /// falseのときは、未訪問の市区町村を描かない(広域表示で枚数を抑えるため)。
    let showsUnvisitedMunicipalities: Bool
    let visitedCodes: Set<String>
    /// 現在地の市区町村。「次にはめるピース」として縁取りで目立たせる。
    let currentCode: String?
    /// 都道府県コードごとの塗りの段階。nilでなければ都道府県の制覇率で塗る表示になり、市区町村のピースは描かない。
    /// ストアの読み込みが切り替わるまでの一瞬も古いピースが混ざらないよう、ここで明示的に描き分ける。
    let prefectureConquestLevels: [String: PrefectureConquestLevel]?
    /// 演出中の区域と見た目(`MapAreaEffectController`が持つ)。nilなら全区域が通常の見た目。
    let emphasis: MunicipalityEmphasis?
    /// 今の縮尺での線の太さ。寄るほど太く、引くほど細くする(`BoundaryLineWidths`参照)。
    let lineWidths: BoundaryLineWidths

    var body: some MapContent {
        if let prefectureConquestLevels {
            // 塗りは地名より下の階層に置き、線は下の県境のForEachに任せる(塗りと線で階層を分ける理由は型のコメント参照)。
            ForEach(prefectureAreas) { area in
                let level = prefectureConquestLevels[area.code] ?? .unvisited
                let emphasizedFill = prefectureLook(for: area.code)?.fill
                MapPolygon(area.polygon)
                    .foregroundStyle(emphasizedFill?.color ?? PrefectureConquestStyle.fill(for: level))
                    .mapOverlayLevel(level: .aboveRoads)
            }
        }
        ForEach(visibleMunicipalityPieces) { piece in
            let style = MunicipalityPieceStyle(
                isVisited: visitedCodes.contains(piece.code), lineWidths: lineWidths, emphasis: municipalityLook(for: piece.code)
            )
            MapPolygon(piece.polygon)
                .foregroundStyle(style.fill)
                .stroke(style.stroke, style: style.strokeStyle)
                .mapOverlayLevel(level: .aboveRoads)
        }
        ForEach(prefectureBorders) { border in
            // 線には`mapOverlayLevel(.aboveLabels)`を付けないこと。付けると線が描かれなくなる
            // (iOS 26.5シミュレータで確認。ポリゴンは同じ指定で描ける)。既定の階層でも市区町村の上に見えている。
            MapPolyline(border.polyline)
                .stroke(PrefectureBorderStyle.stroke, style: PrefectureBorderStyle.strokeStyle(lineWidths))
        }
        // 塗られた(訪問済みの)都道府県の縁取り。灰色の県境の上に重ねて、縁も塗りと同じ色にする。
        // 県境の線は隣県と共有の1本なので、そちらの色を変えずに面の縁取りを上の階層に足している。
        // 縁取りだけのポリゴンは`.aboveLabels`でも描ける(現在地の縁取りと同じ方法)。
        ForEach(visitedPrefectureAreas) { area in
            let emphasizedOutline = prefectureLook(for: area.code)?.outline
            MapPolygon(area.polygon)
                .foregroundStyle(.clear)
                .stroke(
                    emphasizedOutline?.paint.color ?? PrefectureConquestStyle.outlineStroke,
                    style: emphasizedOutline?.strokeStyle(scaledBy: lineWidths.outlineScale)
                        ?? PrefectureConquestStyle.outlineStrokeStyle(lineWidths)
                )
                .mapOverlayLevel(level: .aboveLabels)
        }
        // 同じ上の階層の中では県境と前後することがあるが、縁取りの方が太いので隠れない。
        ForEach(currentPieces) { piece in
            let emphasizedOutline = municipalityLook(for: piece.code)?.outline
            MapPolygon(piece.polygon)
                .foregroundStyle(.clear)
                .stroke(
                    emphasizedOutline?.paint.color ?? CurrentMunicipalityOutlineStyle.stroke,
                    style: emphasizedOutline?.strokeStyle(scaledBy: lineWidths.outlineScale)
                        ?? CurrentMunicipalityOutlineStyle.strokeStyle(lineWidths)
                )
                .mapOverlayLevel(level: .aboveLabels)
        }
    }

    /// 縁取りで目立たせる市区町村。誘いシートからの保存中は現在地(`currentCode`)が一旦nilになるため、
    /// 演出中の区域で代わりに縁取りを保ち、保存の途中で縁取りが消えて見えないようにする。
    private var outlinedCode: String? {
        currentCode ?? municipalityEmphasis?.code
    }

    private var municipalityEmphasis: MunicipalityEmphasis? {
        emphasis?.scope == .municipality ? emphasis : nil
    }

    private func municipalityLook(for code: String) -> MapAreaEffectLook? {
        guard let municipalityEmphasis, municipalityEmphasis.code == code else { return nil }
        return municipalityEmphasis.look
    }

    private func prefectureLook(for code: String) -> MapAreaEffectLook? {
        guard let emphasis, emphasis.scope == .prefecture, emphasis.code == code else { return nil }
        return emphasis.look
    }

    /// 塗りを描くピース。広域では訪問済みと現在地(と演出中の区域)だけに絞る。
    private var visibleMunicipalityPieces: [BoundaryPiece] {
        guard prefectureConquestLevels == nil else { return [] }
        let emphasizedCode = municipalityEmphasis?.code
        return municipalityPieces.filter { piece in
            showsUnvisitedMunicipalities || visitedCodes.contains(piece.code)
                || piece.code == currentCode || piece.code == emphasizedCode
        }
    }

    /// 制覇率の表示で塗られる(未訪問以外の)都道府県。
    private var visitedPrefectureAreas: [BoundaryPiece] {
        guard let prefectureConquestLevels else { return [] }
        return prefectureAreas.filter { area in
            let level = prefectureConquestLevels[area.code] ?? .unvisited
            return level != .unvisited
        }
    }

    private var currentPieces: [BoundaryPiece] {
        guard prefectureConquestLevels == nil, let outlinedCode else { return [] }
        return municipalityPieces.filter { $0.code == outlinedCode }
    }
}

/// 市区町村のピースの見た目。集めたピースはテーマ色で埋め、まだのピースは薄い灰色で覆って
/// 「灰色が色に置き換わっていく」感覚を出す。
struct MunicipalityPieceStyle {
    let fill: Color
    let stroke: Color
    let lineWidth: CGFloat

    /// 継ぎ目は丸める(理由は`PrefectureBorderStyle.strokeStyle`と同じ)。
    var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    /// - Parameter emphasis: 演出中の見た目。指定された項目だけ通常の見た目より優先する。
    ///   演出の線の太さは以前の固定値を基準に書かれているため、今の縮尺の太さに合わせて拡大する。
    init(isVisited: Bool, lineWidths: BoundaryLineWidths, emphasis: MapAreaEffectLook? = nil) {
        // 訪問済みの色は、アプリのテーマ色(.teal。進捗カードやタブのtintと同じ)に揃える。
        // 未開拓は薄い灰色で面を塗る。塗りは地名ラベルより下の階層なので、濃くしすぎなければ地名は読める。
        let normalFill: Color = isVisited ? .teal.opacity(0.35) : .gray.opacity(0.22)
        let normalStroke: Color = isVisited ? .teal.opacity(0.9) : .gray.opacity(0.55)
        fill = emphasis?.fill?.color ?? normalFill
        stroke = emphasis?.pieceStroke?.paint.color ?? normalStroke
        // 訪問済みも未訪問と同じ太さ。訪問済みは塗りで分かる。県境より常に細く、県境との区別は太さと色
        // (県境は不透明の灰色、こちらは半透明)の両方で付く。
        lineWidth = emphasis?.pieceStroke.map { CGFloat($0.width * lineWidths.pieceStrokeScale) } ?? lineWidths.municipalityLine
    }
}

/// 都道府県の制覇率の塗り。市区町村のピースと同じく、未訪問は薄い灰色、訪問済みはテーマ色(.teal)にして
/// 「市区町村パズルを県単位で見たもの」と感じられるようにする。段階が上がるほどtealを濃くする(色相は変えない)。
/// 色相を段階ごとに変えないのは、色覚の個人差に左右されず「濃い=たくさん回った」と読めるようにするため。
enum PrefectureConquestStyle {
    static func fill(for level: PrefectureConquestLevel) -> Color {
        fillPaint(for: level).color
    }

    /// 塗りの色を数値のまま返す。記録の演出(`MapAreaEffectTimeline.prefectureLevelUp`)が、
    /// 新しい段階の濃さを基準に一時的に濃くするために使う。
    static func fillPaint(for level: PrefectureConquestLevel) -> MapAreaPaint {
        switch level {
        // 市区町村の未訪問ピース(`MunicipalityPieceStyle`)と同じ灰色。
        case .unvisited: .gray(0.22)
        case .started: .teal(0.15)
        case .quarter: .teal(0.27)
        case .half: .teal(0.39)
        case .threeQuarters: .teal(0.51)
        // 上限は地名ラベルの下とはいえ、道路や地形が読める程度に留める。
        case .complete: .teal(0.65)
        }
    }

    /// 塗られた都道府県の縁の色。段階によらず一定にし、訪問済み市区町村の線(`MunicipalityPieceStyle`)と揃える。
    static let outlineStroke = Color.teal.opacity(0.9)
    /// 太さは灰色の県境(`PrefectureBorderStyle`)と同じにして、下の灰色がはみ出して見えないようにする。
    static func outlineStrokeStyle(_ lineWidths: BoundaryLineWidths) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidths.prefectureBorder, lineCap: .round, lineJoin: .round)
    }
}

/// 現在地の市区町村の縁取り。訪問の有無にかかわらず示す。色は現在地カード・選択中ピンの.tealと揃える。
enum CurrentMunicipalityOutlineStyle {
    static let stroke = Color.teal
    static func strokeStyle(_ lineWidths: BoundaryLineWidths) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidths.currentOutline, lineCap: .round, lineJoin: .round)
    }
}

/// 県境・海岸線の見た目。市区町村の線(半透明の薄いグレー)とは、太さ(市区町村の線の2倍前後)と濃さ(不透明の灰色)で区別する。
/// 濃さで差をつけすぎると地図が重たく見えるため、濃さは控えめにして太さの差を主な手がかりにしている。
enum PrefectureBorderStyle {
    /// 不透明にしておく。県境の線データは1本の県境を1回だけ持つが、線の端どうしはわずかに重なるため、
    /// 半透明だと重なった点だけ濃く見える。値は以前の「`.label`の40%」を地図の背景に重ねた見た目に合わせた灰色。
    static let stroke = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.5, alpha: 1) : UIColor(white: 0.55, alpha: 1)
    })
    /// 継ぎ目は必ず丸める。既定(miter)だと、簡略化で生じた鋭角の頂点から線がトゲ状に長く伸びる。
    /// 太さは縮尺で変える。全国表示の太さ(1.2pt)は線同士が潰れ合わない上限で、これより太いと小さな県が
    /// 黒く塗りつぶされて見える(`BoundaryLineWidths.prefectureBorderRange`)。
    static func strokeStyle(_ lineWidths: BoundaryLineWidths) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidths.prefectureBorder, lineCap: .round, lineJoin: .round)
    }
}

// MARK: - 演出の値からSwiftUIの見た目への変換

extension MapAreaPaint {
    var color: Color {
        switch tint {
        case .teal: .teal.opacity(opacity)
        case .gray: .gray.opacity(opacity)
        }
    }
}

extension MapAreaStroke {
    /// 継ぎ目は丸める(理由は`PrefectureBorderStyle.strokeStyle`と同じ)。
    /// `scale`は縮尺に合わせた倍率(`BoundaryLineWidths.outlineScale`)。
    func strokeStyle(scaledBy scale: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round)
    }
}
