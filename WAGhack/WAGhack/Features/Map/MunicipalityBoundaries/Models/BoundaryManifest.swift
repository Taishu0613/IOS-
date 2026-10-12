import Foundation

/// 境界データのレイヤ。manifestの`layer`の値と一致させる。
/// 地方のポリゴン(`regions`)は使わないので定義しない。
nonisolated enum BoundaryLayer: String, Sendable {
    /// 市区町村のポリゴン。
    case municipalities
    /// 都道府県のポリゴン。制覇率の塗りにだけ使う(輪郭の線は`prefectureLines`で描く)。
    case prefectures
    /// 県境と海岸線の線。1本の県境は隣り合う2県のうちコードの小さい県のファイルにだけ入っている。
    case prefectureLines
}

/// 同梱した境界データの目録(`manifest.json`)。アプリが使う項目だけを読む。
///
/// 仕様はリポジトリ直下の`BoundaryData/README.md`を正とする。LODの切替距離もここから読み、
/// アプリ側に数値を二重に持たない(データを作り直したときに食い違わないようにするため)。
nonisolated struct BoundaryManifest: Decodable, Sendable {
    let schemaVersion: Int
    let lods: [Level]
    let lodTransitions: [BoundaryLODTransition]
    let files: [File]

    /// 1段階の詳細度。`intervalMeters`は簡略化(Douglas-Peucker)の許容距離。
    struct Level: Decodable, Sendable {
        let id: Int
        let intervalMeters: Double
    }

    struct File: Decodable, Sendable, Identifiable {
        let id: String
        let layer: String
        let lod: Int
        /// 全国ファイル(LOD0)ではnil。
        let prefectureCode: String?
        /// manifest.jsonのあるフォルダからの相対パス。
        let path: String
        let bbox: [Double]

        var boundingBox: GeoBoundingBox? { GeoBoundingBox(geoJSON: bbox) }
    }

    static let supportedSchemaVersion = 2

    /// 指定レイヤ・LODのファイルのうち、表示範囲と重なるもの。
    ///
    /// LOD0は全国1ファイルなので常にそれが選ばれる。LOD1以降は都道府県単位のファイルをbboxで絞る。
    /// 東京都は沖ノ鳥島・南鳥島を含むためbboxが太平洋側に大きく広がっており、関東〜東海を見ているときは
    /// 範囲外でも読み込まれる。ファイル自体は小さく、描画は`MunicipalityPuzzleStore`側で
    /// ポリゴン単位に絞るので、正確さより単純さを優先している。
    func files(in layer: BoundaryLayer, lod: Int, intersecting visibleBox: GeoBoundingBox) -> [File] {
        files.filter { file in
            guard file.layer == layer.rawValue, file.lod == lod,
                  let boundingBox = file.boundingBox else { return false }
            return boundingBox.intersects(visibleBox)
        }
    }

    /// 指定レイヤ・LODのうち、1つの都道府県のファイル。全国1ファイルのLOD0には都道府県コードが無いので空になる。
    func files(in layer: BoundaryLayer, lod: Int, prefectureCode: String) -> [File] {
        files.filter { $0.layer == layer.rawValue && $0.lod == lod && $0.prefectureCode == prefectureCode }
    }
}
