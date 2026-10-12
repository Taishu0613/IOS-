import Foundation
import Observation
import os

/// 踏破率の表示に添える小さな地図(日本地図・都道府県を市区町村に分けた地図・市区町村単体の地図)を用意する。
///
/// - 日本地図: 全国の都道府県ファイル(LOD0)を1回だけ読んで作る。
/// - 都道府県の地図: その県の市区町村ファイル(LOD1)だけを、必要になったときに読んで作る。
/// - 市区町村の地図: 詳細画面で大きく描くため、その県の最も細かい市区町村ファイル(LOD3)から作る。
///
/// 作った地図は小さい(数百〜数千点)ので保持し、同じ県・市区町村に戻ったときは読み直さない。
/// 訪問済みかどうかはここでは持たない(塗り分けは描画側が`ExplorationSummary`から決める)。
/// `MapScreen`が所有し、シート内の画面へはenvironmentで渡す。
@Observable
final class SilhouetteMapStore {
    private(set) var japanMap: SilhouetteMap?
    /// 都道府県コード(2桁)ごとの、市区町村に分けた地図。
    private(set) var prefectureMaps: [String: SilhouetteMap] = [:]
    /// 行政区域コード(5桁)ごとの、市区町村単体の地図。
    private(set) var municipalityMaps: [String: SilhouetteMap] = [:]

    @ObservationIgnored private var loadingKeys: Set<String> = []
    @ObservationIgnored private let logger = Logger(subsystem: "com.wakasugi.yorimichi", category: "SilhouetteMap")

    /// 踏破率ヘッダーでの描画サイズ(pt)。
    static let headerMapSize: CGFloat = 56
    /// 旅の記録・都道府県画面の進捗の隣での描画サイズ(pt)。
    static let progressMapSize: CGFloat = 96
    /// 日本地図・都道府県の地図を間引く基準の大きさ(pt)。ヘッダーより大きい進捗の隣でも粗く見えないよう、大きい方に合わせる。
    private static let areaMapResolution = progressMapSize
    /// 市区町村の詳細画面で大きく描くときの基準の大きさ(pt)。画面幅いっぱいに描いても粗く見えない細かさ。
    private static let municipalityMapResolution: CGFloat = 320

    /// 都道府県の地図に使うLOD。LOD0(2km間引き)では小さな県の市区町村が潰れるため、1段細かいLOD1(500m)にする。
    /// 1県1ファイルで最大でも約1MB。
    private static let prefectureLOD = 1
    /// 市区町村の地図に使うLOD。5km四方ほどの区を画面幅で描くと1pt≒15mになるため、最も細かいLOD3(20m)にする。
    /// 1県1ファイルで最大約3.5MB。詳細画面を開いたときだけ読む。
    private static let municipalityLOD = 3

    /// 日本地図を用意する。読み込み済み・読み込み中なら何もしない。
    func loadJapanMapIfNeeded() async {
        guard japanMap == nil else { return }
        await load(key: "japan") { repository, manifest in
            let selector = BoundaryLODSelector(transitions: manifest.lodTransitions)
            // 最も粗いLODは全国1ファイルなので、47県を1回の読み込みで揃えられる。
            let files = manifest.files(in: .prefectures, lod: selector.coarsestLOD, intersecting: Self.wholeWorld)
            // 日本地図では約15km未満の島は1pt前後にしかならず描かないので、デコード直後に捨ててメモリを抑える。
            let prefectures = try await repository.boundaries(
                in: files, pieceFilter: BoundaryPieceFilter(visibleWidthMeters: 1_500_000)
            )
            let builder = BoundarySilhouetteBuilder(targetPoints: Self.areaMapResolution)
            // 間引きは全国で数十万頂点を舐めるので、メインスレッドの外で行う。
            let map = await Task.detached(priority: .utility) { builder.japanMap(of: prefectures) }.value
            try Task.checkCancellation()
            self.japanMap = map
        }
    }

    /// 都道府県の地図を用意する。読み込み済み・読み込み中なら何もしない。
    func loadPrefectureMapIfNeeded(code: String) async {
        guard prefectureMaps[code] == nil else { return }
        await load(key: "prefecture-\(code)") { repository, manifest in
            // 最も小さい県(香川県・大阪府、約100km)の枠でも1pt≒1kmなので、1km未満の島は描かない。
            let loadFilter = BoundaryPieceFilter(visibleWidthMeters: 100_000)
            let prefecture = try await repository.boundaries(
                in: manifest.files(in: .prefectures, lod: Self.prefectureLOD, prefectureCode: code),
                pieceFilter: loadFilter
            ).first
            let municipalities = try await repository.boundaries(
                in: manifest.files(in: .municipalities, lod: Self.prefectureLOD, prefectureCode: code),
                pieceFilter: loadFilter
            )
            guard let prefecture else {
                self.logger.error("都道府県\(code, privacy: .public)の境界ファイルが見つかりません")
                return
            }
            let builder = BoundarySilhouetteBuilder(targetPoints: Self.areaMapResolution)
            let map = await Task.detached(priority: .utility) {
                builder.prefectureMap(of: prefecture, municipalities: municipalities)
            }.value
            try Task.checkCancellation()
            self.prefectureMaps[code] = map
        }
    }

    /// 市区町村単体の地図を用意する。読み込み済み・読み込み中なら何もしない。
    func loadMunicipalityMapIfNeeded(code: String) async {
        guard municipalityMaps[code] == nil else { return }
        // 行政区域コードの先頭2桁は都道府県コード。
        let prefectureCode = String(code.prefix(2))
        await load(key: "municipality-\(code)") { repository, manifest in
            // 県のファイルごと読むが、この市区町村以外はすぐ捨てる。50m未満の岩礁は描かない。
            let municipality = try await repository.boundaries(
                in: manifest.files(in: .municipalities, lod: Self.municipalityLOD, prefectureCode: prefectureCode),
                pieceFilter: BoundaryPieceFilter(visibleWidthMeters: 5_000)
            ).first { $0.code == code }
            guard let municipality else {
                self.logger.error("市区町村\(code, privacy: .public)の境界が見つかりません")
                return
            }
            let builder = BoundarySilhouetteBuilder(targetPoints: Self.municipalityMapResolution)
            let map = await Task.detached(priority: .utility) { builder.municipalityMap(of: municipality) }.value
            try Task.checkCancellation()
            self.municipalityMaps[code] = map
        }
    }

    /// 読み込みの共通部分。同じ`key`の読み込みが進行中なら何もしない。
    ///
    /// 地図の`MunicipalityPuzzleStore`とはリポジトリを共有しない。リポジトリのキャッシュはファイル単位で
    /// 「同じファイルには同じフィルタ」が前提のため。作った地図だけを残し、デコード結果は使い終わったら捨てる。
    private func load(
        key: String,
        _ operation: (BoundaryRepository, BoundaryManifest) async throws -> Void
    ) async {
        guard !loadingKeys.contains(key) else { return }
        loadingKeys.insert(key)
        defer { loadingKeys.remove(key) }

        do {
            let repository = BoundaryRepository.bundled()
            let manifest = try await repository.loadManifest()
            try await operation(repository, manifest)
        } catch is CancellationError {
            // 画面を離れただけ。次に表示されたときに読み直す。
        } catch {
            // 小さな地図は進捗の飾りで、無くても踏破率は読める。ユーザーには出さず開発者向けに残す。
            logger.error("地図のシルエットを用意できませんでした(\(key, privacy: .public)): \(String(describing: error), privacy: .public)")
        }
    }

    private static let wholeWorld = GeoBoundingBox(minLongitude: -180, minLatitude: -90, maxLongitude: 180, maxLatitude: 90)
}
