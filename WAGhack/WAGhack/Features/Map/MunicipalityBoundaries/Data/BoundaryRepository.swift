import Foundation

/// アプリに同梱した境界データ(manifest.json と市区町村・都道府県・県境線のGeoJSON)を読み込み、メモリに保持する。
///
/// GeoJSONのデコードは全国ファイルで数百ms以上かかるため、actorにしてメインスレッドの外で行う。
/// 同じファイルを何度もデコードしないよう、最近使ったファイルだけを上限付きでキャッシュする。
actor BoundaryRepository {
    enum LoadError: Error {
        case resourceNotFound(String)
        case unsupportedSchemaVersion(Int)
    }

    /// LOD1で広域(〜900km)を見たときに重なる都道府県数(十数件)を市区町村・県境線の2レイヤぶん収め、
    /// 行き来しても読み直さずに済む数。
    /// 1ファイルは数百KB〜数MB。
    static let maximumCachedFileCount = 48

    /// manifest.json と、そこから相対パスで参照される各GeoJSONが置かれたフォルダ。
    private let baseURL: URL
    private var manifest: BoundaryManifest?
    private var cachedBoundaries: [String: [AdministrativeBoundary]] = [:]
    private var cachedLines: [String: [BoundaryLine]] = [:]
    /// 古い順。末尾が最後に使ったファイル。
    private var recentlyUsedFileIDs: [String] = []

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// アプリ本体に同梱したデータを読む。Xcodeプロジェクト上で`manifest.json`と`municipalities`・`prefectures`・`prefectureLines`フォルダを
    /// バンドル直下へコピーしている(`BoundaryData/README.md`「アプリへの組み込み」参照)。
    static func bundled(in bundle: Bundle = .main) -> BoundaryRepository {
        BoundaryRepository(baseURL: bundle.resourceURL ?? bundle.bundleURL)
    }

    func loadManifest() throws -> BoundaryManifest {
        if let manifest { return manifest }
        let data = try readResource(at: "manifest.json")
        let decoded = try JSONDecoder().decode(BoundaryManifest.self, from: data)
        guard decoded.schemaVersion == BoundaryManifest.supportedSchemaVersion else {
            throw LoadError.unsupportedSchemaVersion(decoded.schemaVersion)
        }
        manifest = decoded
        return decoded
    }

    /// 複数ファイルの市区町村・都道府県の境界をまとめて返す。
    ///
    /// `pieceFilter`はそのLODで最も拡大したときの基準を渡す。キャッシュはファイル単位なので、
    /// 同じファイルには常に同じフィルタを渡すこと(LODごとに固定値になるので実際には自然にそうなる)。
    func boundaries(in files: [BoundaryManifest.File], pieceFilter: BoundaryPieceFilter) throws -> [AdministrativeBoundary] {
        var result: [AdministrativeBoundary] = []
        for file in files {
            try Task.checkCancellation()
            result += try boundaries(in: file, pieceFilter: pieceFilter)
        }
        return result
    }

    private func boundaries(in file: BoundaryManifest.File, pieceFilter: BoundaryPieceFilter) throws -> [AdministrativeBoundary] {
        if let cached = cachedBoundaries[file.id] {
            markAsRecentlyUsed(file.id)
            return cached
        }
        let data = try readResource(at: file.path)
        let decoded = try BoundaryGeoJSONDecoder().decode(data, pieceFilter: pieceFilter)
        cachedBoundaries[file.id] = decoded
        markAsRecentlyUsed(file.id)
        evictIfNeeded()
        return decoded
    }

    /// 複数ファイルの県境・海岸線をまとめて返す。`pieceFilter`の扱いは`boundaries(in:pieceFilter:)`と同じ。
    func lines(in files: [BoundaryManifest.File], pieceFilter: BoundaryPieceFilter) throws -> [BoundaryLine] {
        var result: [BoundaryLine] = []
        for file in files {
            try Task.checkCancellation()
            result += try lines(in: file, pieceFilter: pieceFilter)
        }
        return result
    }

    private func lines(in file: BoundaryManifest.File, pieceFilter: BoundaryPieceFilter) throws -> [BoundaryLine] {
        if let cached = cachedLines[file.id] {
            markAsRecentlyUsed(file.id)
            return cached
        }
        let data = try readResource(at: file.path)
        let decoded = try BoundaryLineGeoJSONDecoder().decode(data, fileID: file.id, pieceFilter: pieceFilter)
        cachedLines[file.id] = decoded
        markAsRecentlyUsed(file.id)
        evictIfNeeded()
        return decoded
    }

    private func readResource(at relativePath: String) throws -> Data {
        let url = baseURL.appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw LoadError.resourceNotFound(relativePath)
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func markAsRecentlyUsed(_ fileID: String) {
        recentlyUsedFileIDs.removeAll { $0 == fileID }
        recentlyUsedFileIDs.append(fileID)
    }

    private func evictIfNeeded() {
        while recentlyUsedFileIDs.count > Self.maximumCachedFileCount {
            // ファイルidはレイヤをまたいで一意なので、どちらのキャッシュにあっても消せる。
            let oldest = recentlyUsedFileIDs.removeFirst()
            cachedBoundaries[oldest] = nil
            cachedLines[oldest] = nil
        }
    }
}
