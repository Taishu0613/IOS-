import MapKit
import Observation
import os

/// 地図に載せる境界のピース1枚(島1つぶん)。`MKPolygon`は穴(飛び地)を表現するために使う。
struct BoundaryPiece: Identifiable {
    /// LOD・レイヤ・コード・島の番号の組み合わせ。同じ市区町村でも島ごと・LODごとに別のピースになる。
    let id: String
    /// 市区町村のピースなら行政区域コード、県境のピースなら都道府県コード。
    let code: String
    let polygon: MKPolygon
    /// 穴のあるピースの輪郭(外周と各穴)を、それぞれ穴の無いポリゴンにしたもの。穴が無ければnilで、線は`polygon`の縁取りで描く。
    ///
    /// MapKitは穴のあるポリゴンの縁取りを、同じ太さを指定しても穴の無いポリゴンより太くぼやけて描く
    /// (iOS 26.5シミュレータで確認。川越市・小金井市など飛び地を囲む市区町村や、東京都などの境界だけが、
    /// 地図を引いたときに県境のような太い線に見えていた。穴を外すと他と同じ太さになる)。
    /// そのため穴のあるピースは、塗りだけを`polygon`で描き、線はこの輪郭で別に描く(`MunicipalityPuzzleLayer`)。
    /// `MKPolyline`ではなくポリゴンにしているのは、縁取りと同じ階層(`mapOverlayLevel`)に置けるようにするため
    /// (線は`.aboveLabels`に置くと描かれず、既定の階層では灰色の県境の下に隠れることがある)。
    let outlines: [BoundaryOutline]?

    init(id: String, code: String, shape: BoundaryPolygon) {
        self.id = id
        self.code = code
        let holes = shape.holes.map { MKPolygon(coordinates: $0, count: $0.count) }
        polygon = MKPolygon(coordinates: shape.exterior, count: shape.exterior.count, interiorPolygons: holes)
        if shape.holes.isEmpty {
            outlines = nil
        } else {
            let rings = [shape.exterior] + shape.holes
            outlines = rings.enumerated().map { index, ring in
                BoundaryOutline(id: "\(id)/outline/\(index)", polygon: MKPolygon(coordinates: ring, count: ring.count))
            }
        }
    }
}

/// 穴のあるピースの輪郭1つ(外周または穴1つ)。縁取りを描くためだけに使い、塗らない。
struct BoundaryOutline: Identifiable {
    /// ピースのidと輪の番号(0が外周、1以降が穴)の組み合わせ。
    let id: String
    /// 穴を持たないポリゴン。
    let polygon: MKPolygon
}

/// 地図に載せる県境・海岸線1本。
struct BoundaryLinePiece: Identifiable {
    /// LODと線のid(ファイルidとファイル内の番号)の組み合わせ。
    let id: String
    let polyline: MKPolyline
}

/// 地図の表示範囲と表示モードに合わせて、描くべき市区町村のピースと県境を用意する。
///
/// 流れ: 表示範囲 → LOD決定(ヒステリシス付き) → 範囲に重なるファイルを読み込み → 範囲内・十分な大きさのピースだけを残す。
/// 訪問済みかどうかはここでは持たない(SwiftDataの記録が唯一の正)。塗り分けは`MunicipalityPuzzleLayer`が行う。
@Observable
final class MunicipalityPuzzleStore {
    /// 今の表示範囲で描ける市区町村のピース。県境のみの表示モードでは空。
    private(set) var municipalityPieces: [BoundaryPiece] = []
    /// 今の表示範囲の県境と海岸線。1本の県境は1回だけ入っている。
    private(set) var prefectureBorders: [BoundaryLinePiece] = []
    /// 今の表示範囲の都道府県の面。制覇率の塗り専用で、「県境のみ」の読み込みのときだけ用意する(それ以外は空)。
    private(set) var prefectureAreas: [BoundaryPiece] = []
    /// 未訪問の市区町村まで描くか。falseのときは訪問済み・現在地のピースだけを描く。
    private(set) var showsUnvisitedMunicipalities = false
    private(set) var displayMode: BoundaryDisplayMode = .municipalities

    // 描画範囲で省かれる飛び地も含めた、カメラ用の区域全体の範囲。
    @ObservationIgnored private var municipalityFocusBounds: [String: MKMapRect] = [:]
    // 都道府県の面は「県境のみ」の表示で、しかも表示範囲の分しか読み込まれないため、カメラ用に県全体の島を別に持つ。
    // 現在地のある島を選ぶ必要があるので、市区町村と違い外接矩形ではなく島の形のまま持つ。
    @ObservationIgnored private var prefectureFocusIslands: [String: [MKPolygon]] = [:]
    @ObservationIgnored private let repository: BoundaryRepository
    @ObservationIgnored private var manifest: BoundaryManifest?
    @ObservationIgnored private var currentLOD: Int?
    /// 表示モードだけが変わったときに、同じ範囲で読み込み直すために覚えておく。
    @ObservationIgnored private var lastRegion: MKCoordinateRegion?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// `MKPolygon`(と穴のあるピースの輪郭)を作り直すと地図側で同じ形の再描画が走るため、LODが変わるまで使い回す。
    /// 同じLODのまま全国を見て回るとピース数ぶん増えるが、1つあたりは座標の参照程度なので上限は設けていない。
    @ObservationIgnored private var pieceCache: [String: BoundaryPiece] = [:]
    @ObservationIgnored private var polylineCache: [String: MKPolyline] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "com.wakasugi.yorimichi", category: "MunicipalityPuzzle")

    /// 画面の少し外側まで先に用意しておき、ドラッグ中に端が欠けて見えるのを減らす(上下左右それぞれ表示範囲の20%)。
    /// 表示範囲は、ヘッダー・シートの裏も含めた地図のビュー全体(`MapFullFrameRect`)を渡してもらう前提。
    /// 用意する面積は50%で表示範囲の4倍、20%で約2倍になり、描くピースもほぼ面積に比例して増えるため小さめにしている。
    private static let prefetchMarginRatio = 0.2

    /// これより広い範囲(日本が画面の一部にしか映らない縮尺)では境界を描かない。
    /// 線が日本列島を覆って黒い塊に見えるだけで、情報にならないため。全国表示(約2,000km)は含む。
    private static let maximumVisibleWidthMeters = 4_000_000.0

    init(repository: BoundaryRepository = .bundled()) {
        self.repository = repository
    }

    /// 画面外の飛び地も含め、現在地の市区町村全体の範囲を事前に用意する。
    func prepareFocusRect(forMunicipality code: String, prefectureCode: String) async {
        guard municipalityFocusBounds[code] == nil else { return }
        do {
            let manifest = try await repository.loadManifest()
            guard let lod = manifest.lods.map(\.id).max() else { return }
            // 最詳細LODの標準フィルターは0。表示用と同じ条件でキャッシュを共有する。
            let selector = BoundaryLODSelector(transitions: manifest.lodTransitions)
            let boundaries = try await repository.boundaries(
                in: manifest.files(in: .municipalities, lod: lod, prefectureCode: prefectureCode),
                pieceFilter: BoundaryPieceFilter(visibleWidthMeters: selector.minimumVisibleWidthMeters(of: lod))
            )
            try Task.checkCancellation()
            guard let boundary = boundaries.first(where: { $0.code == code }) else { return }
            let polygons = boundary.polygons.map { polygon in
                MKPolygon(coordinates: polygon.exterior, count: polygon.exterior.count)
            }
            municipalityFocusBounds[code] = boundingRect(of: polygons)
        } catch is CancellationError {
            return
        } catch {
            logger.error("市区町村全体の表示範囲を読み込めませんでした: \(String(describing: error), privacy: .public)")
        }
    }

    /// 表示モードや表示範囲によらず、都道府県全体へ寄せられるように県の島を事前に用意する。
    /// カメラの範囲を決めるだけなので、最も粗いLOD(1県あたり数KB)で足りる。
    func prepareFocusRect(forPrefecture code: String) async {
        guard prefectureFocusIslands[code] == nil else { return }
        do {
            let manifest = try await repository.loadManifest()
            // LOD0は全国1ファイルで都道府県コードを持たないため、県単位のファイルがある最も粗いLODを使う。
            let lod = manifest.lods.map(\.id).sorted().first { lod in
                !manifest.files(in: .prefectures, lod: lod, prefectureCode: code).isEmpty
            }
            guard let lod else { return }
            // リポジトリはファイル単位でキャッシュするため、表示用の読み込みと同じフィルターにそろえる
            // (違う条件で先に読むと、表示側がその条件の結果を使い回してしまう)。
            let selector = BoundaryLODSelector(transitions: manifest.lodTransitions)
            let boundaries = try await repository.boundaries(
                in: manifest.files(in: .prefectures, lod: lod, prefectureCode: code),
                pieceFilter: BoundaryPieceFilter(visibleWidthMeters: selector.minimumVisibleWidthMeters(of: lod))
            )
            try Task.checkCancellation()
            guard let boundary = boundaries.first(where: { $0.code == code }) else { return }
            prefectureFocusIslands[code] = boundary.polygons.map { polygon in
                MKPolygon(coordinates: polygon.exterior, count: polygon.exterior.count)
            }
        } catch is CancellationError {
            return
        } catch {
            logger.error("都道府県全体の表示範囲を読み込めませんでした: \(String(describing: error), privacy: .public)")
        }
    }

    /// 地図のカメラが止まるたびに呼ぶ。前回の読み込みが終わっていなければ取り消して、最新の範囲だけを反映する。
    func showRegion(_ region: MKCoordinateRegion) {
        lastRegion = region
        reload()
    }

    func setDisplayMode(_ mode: BoundaryDisplayMode) {
        guard mode != displayMode else { return }
        displayMode = mode
        reload()
    }

    // MARK: - 読み込み済みの形の問い合わせ
    //
    // 市区町村のフォーカスは事前に用意した全域の範囲を優先する。
    // それ以外は描画用のピースを参照するため、画面外や小さい島は含まれない。

    /// 市区町村へ地図を寄せる範囲(`BoundaryFocusRect`参照)。記録時と現在地ボタンで使う。
    func focusRect(forMunicipality code: String, containing coordinate: CLLocationCoordinate2D) -> MKMapRect? {
        guard let bounds = municipalityFocusBounds[code] ?? boundingRect(forMunicipality: code) else { return nil }
        // 広い市町村や離島・飛び地も切り取らず、区域全体を収める。
        return BoundaryFocusRect.rect(enclosing: bounds, including: coordinate, maximumSideMeters: nil)
    }

    /// 都道府県の制覇率の表示で、その都道府県へ地図を寄せる範囲。記録時・現在地ボタン・ピン選択・表示切り替えで使う。
    /// 県全体を収めたいので、市区町村用の長さの上限(100km)は適用しない。
    func focusRect(forPrefecture code: String, containing coordinate: CLLocationCoordinate2D) -> MKMapRect? {
        let islands = prefectureFocusIslands[code] ?? polygons(in: prefectureAreas, code: code)
        return BoundaryFocusRect.rect(islands: islands, containing: coordinate, maximumSideMeters: nil)
    }

    /// 市区町村の読み込み済みのピースすべてを囲む範囲。
    func boundingRect(forMunicipality code: String) -> MKMapRect? {
        boundingRect(of: polygons(in: municipalityPieces, code: code))
    }

    /// 都道府県の読み込み済みの面すべてを囲む範囲。
    func boundingRect(forPrefecture code: String) -> MKMapRect? {
        boundingRect(of: polygons(in: prefectureAreas, code: code))
    }

    private func polygons(in pieces: [BoundaryPiece], code: String) -> [MKPolygon] {
        pieces.filter { $0.code == code }.map(\.polygon)
    }

    private func boundingRect(of polygons: [MKPolygon]) -> MKMapRect? {
        guard let first = polygons.first else { return nil }
        return polygons.dropFirst().reduce(first.boundingMapRect) { $0.union($1.boundingMapRect) }
    }

    private func reload() {
        guard let region = lastRegion else { return }
        let mode = displayMode
        loadTask?.cancel()
        loadTask = Task { await load(region: region, mode: mode) }
    }

    private func load(region: MKCoordinateRegion, mode: BoundaryDisplayMode) async {
        let visibleWidth = region.widthMeters
        guard visibleWidth <= Self.maximumVisibleWidthMeters else {
            prefectureBorders = []
            prefectureAreas = []
            municipalityPieces = []
            return
        }
        do {
            let manifest = try await loadManifestIfNeeded()
            let selector = BoundaryLODSelector(transitions: manifest.lodTransitions)
            let lod = selector.lod(current: currentLOD ?? selector.coarsestLOD, visibleWidthMeters: visibleWidth)
            let searchBox = region.expanded(by: Self.prefetchMarginRatio).boundingBox
            // 読み込み時は「このLODで最も拡大した状態」でも見えない島だけを捨てる。キャッシュを縮尺に依存させないため。
            let loadFilter = BoundaryPieceFilter(visibleWidthMeters: selector.minimumVisibleWidthMeters(of: lod))

            let borderLines = try await repository.lines(
                in: manifest.files(in: .prefectureLines, lod: lod, intersecting: searchBox),
                pieceFilter: loadFilter
            )
            // 県境のみのモードでは、重い市区町村ファイルはそもそも読まない。
            // 代わりに都道府県の面を読む(都道府県の制覇率を塗る表示で使う。47件なので軽い)。
            var municipalities: [AdministrativeBoundary] = []
            var prefectures: [AdministrativeBoundary] = []
            switch mode {
            case .municipalities:
                municipalities = try await repository.boundaries(
                    in: manifest.files(in: .municipalities, lod: lod, intersecting: searchBox),
                    pieceFilter: loadFilter
                )
            case .prefecturesOnly:
                prefectures = try await repository.boundaries(
                    in: manifest.files(in: .prefectures, lod: lod, intersecting: searchBox),
                    pieceFilter: loadFilter
                )
            }
            try Task.checkCancellation()

            if lod != currentLOD {
                pieceCache = [:]
                polylineCache = [:]
                currentLOD = lod
            }
            let drawFilter = BoundaryPieceFilter(visibleWidthMeters: visibleWidth)
            prefectureBorders = makeLinePieces(lod: lod, from: borderLines, within: searchBox, filter: drawFilter)
            prefectureAreas = makePieces(.prefectures, lod: lod, from: prefectures, within: searchBox, filter: drawFilter)
            municipalityPieces = makePieces(.municipalities, lod: lod, from: municipalities, within: searchBox, filter: drawFilter)
            // 広域では網目が細かすぎて見分けられず重いだけなので、県境と訪問済みの市区町村だけを描く。
            let showsUnvisited = UnvisitedMunicipalityVisibility.isVisible(
                current: showsUnvisitedMunicipalities, visibleWidthMeters: visibleWidth
            )
            // 同じ値を書き戻しても観測している地図全体の再評価が走るため、変わったときだけ書き換える。
            if showsUnvisited != showsUnvisitedMunicipalities {
                showsUnvisitedMunicipalities = showsUnvisited
            }
        } catch is CancellationError {
            // 新しい範囲・モードの読み込みに置き換わっただけなので何もしない。
        } catch {
            // 境界は地図の装飾で、無くても記録機能は使える。ユーザーには出さず開発者向けに残す。
            logger.error("行政区域の境界を読み込めませんでした: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadManifestIfNeeded() async throws -> BoundaryManifest {
        if let manifest { return manifest }
        let loaded = try await repository.loadManifest()
        manifest = loaded
        return loaded
    }

    private func makePieces(
        _ layer: BoundaryLayer,
        lod: Int,
        from boundaries: [AdministrativeBoundary],
        within searchBox: GeoBoundingBox,
        filter: BoundaryPieceFilter
    ) -> [BoundaryPiece] {
        var pieces: [BoundaryPiece] = []
        for boundary in boundaries {
            // idとキャッシュのキーに使うので、indexは絞り込む前の並び(大きい順)の番号にする。
            for (index, polygon) in boundary.polygons.enumerated()
            where filter.shouldDraw(polygon, at: index) && polygon.boundingBox.intersects(searchBox) {
                // LODをidに含めること。含めないとLODが変わってもidが同じになり、地図側が古いLODの形を
                // 置き換えずに残す。簡略化の違う2本の線が重なり、境界の一部だけが太い帯に見える不具合が出ていた。
                let id = "lod\(lod)/\(layer.rawValue)/\(boundary.code)/\(index)"
                pieces.append(cachedPiece(id: id, code: boundary.code, for: polygon))
            }
        }
        return pieces
    }

    private func makeLinePieces(
        lod: Int,
        from lines: [BoundaryLine],
        within searchBox: GeoBoundingBox,
        filter: BoundaryPieceFilter
    ) -> [BoundaryLinePiece] {
        var pieces: [BoundaryLinePiece] = []
        for line in lines where filter.shouldDraw(line) && line.boundingBox.intersects(searchBox) {
            // ファイルidにLODも含まれるが、市区町村のピースと形式を揃えるため先頭にも付ける。
            let id = "lod\(lod)/\(line.id)"
            pieces.append(BoundaryLinePiece(id: id, polyline: cachedPolyline(id: id, for: line)))
        }
        return pieces
    }

    private func cachedPolyline(id: String, for line: BoundaryLine) -> MKPolyline {
        if let cached = polylineCache[id] { return cached }
        let made = MKPolyline(coordinates: line.coordinates, count: line.coordinates.count)
        polylineCache[id] = made
        return made
    }

    private func cachedPiece(id: String, code: String, for polygon: BoundaryPolygon) -> BoundaryPiece {
        if let cached = pieceCache[id] { return cached }
        let made = BoundaryPiece(id: id, code: code, shape: polygon)
        pieceCache[id] = made
        return made
    }
}

// MARK: - 表示範囲の換算

private extension MKCoordinateRegion {
    /// 画面の横幅(m)。LODの切替基準。中心の緯度で東西の距離を測る。
    var widthMeters: Double {
        let west = CLLocation(latitude: center.latitude, longitude: center.longitude - span.longitudeDelta / 2)
        let east = CLLocation(latitude: center.latitude, longitude: center.longitude + span.longitudeDelta / 2)
        return west.distance(from: east)
    }

    var boundingBox: GeoBoundingBox {
        GeoBoundingBox(
            minLongitude: center.longitude - span.longitudeDelta / 2,
            minLatitude: center.latitude - span.latitudeDelta / 2,
            maxLongitude: center.longitude + span.longitudeDelta / 2,
            maxLatitude: center.latitude + span.latitudeDelta / 2
        )
    }

    /// 上下左右それぞれ、元の範囲の`ratio`倍ぶん外側へ広げた範囲。
    func expanded(by ratio: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: span.latitudeDelta * (1 + ratio * 2),
                longitudeDelta: span.longitudeDelta * (1 + ratio * 2)
            )
        )
    }
}
