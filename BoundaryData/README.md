# BoundaryData 仕様

行政区域境界 GeoJSON（WAGhack 地図表示用）とその生成環境。更新: 2026-09-24 / buildRevision 4

## 要点
- アプリに入れるのは `generated/BoundaryData/` のみ。WAGhack は `manifest.json`・`attribution.txt`・`municipalities/`・`prefectures/`・`prefectureLines/` を参照（地方レイヤは未使用）。
- 元データ: 国交省 N03 2026-01-01 版（CC BY 4.0、出典表示必須）。
- 4 レイヤ（市区町村 1,905 / 都道府県 47 / 地方 10 のポリゴン + 県境線）× LOD0〜3。
- 都道府県・地方・県境線は市区町村の形から生成 → 境界は完全一致。
- 県境線（`prefectureLines`）は「都道府県コードが変わる境目」と「海岸線」だけの線。県内の市区町村境は含まない。1本の県境は隣り合う2県のうちコードの小さい県のファイルにだけ入る（アプリが同じ線を2回描かないため）。
- 元データの市区町村どうしのわずかなすき間・重なり（幅5.6m以下、全国16か所）は `-clean` で修復している。修復しないと県が複数のポリゴンに分かれ、県内に誤った県境が出る（千代田・中央・港区の外周など8か所で発生していた）。
- Git 管理対象は本 README と `scripts/`（`node_modules` 除く）のみ。他は大容量・再生成可のため管理外。

## フォルダ
| パス | 内容 | 削除 |
|---|---|---|
| `raw/N03-20260101_GML/` | 原本 `N03-20260101.geojson`（580MB, SHA-256 `3095bfbb…7751`）とメタデータ XML | 不可（再生成の入力） |
| `scripts/mapshaper_boundary_tools/` | 生成ツール。`regions.json` が地方区分の唯一の定義 | 不可（`node_modules/` は可） |
| `normalized/<実行ID>/` | 中間データ（約412MB）。生成成功時に最新1回分だけ自動で残す | 可 |
| `reports/<実行ID>/` | ログ・検査結果（`output-checks.json`） | 非推奨 |
| `generated/BoundaryData/` | **完成品** | 再生成可 |

## 完成品
```
BoundaryData/
├── manifest.json   目録（最初に読む）
├── attribution.txt 出典表示文（アプリ内に表示）
├── municipalities/lod{N}_{m}m/municipality_{範囲}_lod{N}.geojson
├── prefectures/   同上 prefecture_*
├── prefectureLines/ 同上 prefecture_line_*（県境線。MultiLineString）
└── regions/       同上 region_*
```
範囲: LOD0 は `jp`（全国1ファイル）。LOD1〜3 は市区町村・都道府県・県境線が都道府県コード `01`〜`47`、地方が地方コード `01`〜`10`。
県境線のファイルは「その県が持ち主の線」だけを含むので、1ファイルでその県の外周がすべて揃うわけではない。

| LOD | 簡略化(DP) | 画面横幅 | 切替（拡大時 / 縮小時） |
|---|---|---|---|
| 0 | 2000m | 800km〜 | → LOD1: 700km未満 / ← 900km超 |
| 1 | 500m | 200〜800km | → LOD2: 180km未満 / ← 230km超 |
| 2 | 100m | 50〜200km | → LOD3: 45km未満 / ← 60km超 |
| 3 | 20m | 〜50km | |

GeoJSON: FeatureCollection、WGS84 経緯度、`bbox` 付き。座標の桁数は LOD0 が小数4桁（約11m）、LOD1 が5桁（約1m）、LOD2・3 が6桁（簡略化の許容距離より十分細かい）。ポリゴンのレイヤは Polygon/MultiPolygon で 1 Feature = 1 行政単位。県境線は MultiLineString で 1 Feature = 1 県の 1 種類（県境 / 海岸線）。
properties（コードはすべて文字列）:
- 市区町村 `{c:"15101", n:"新潟市北区", p:"15", r:"04"}`
- 都道府県 `{p:"20", n:"長野県", r:"03"}`
- 地方 `{r:"04", n:"北陸"}`
- 県境線 `{p:"13", k:"border"}`（`k` は `border`=県境 / `coast`=海岸線。LOD0 は `p` なし）

`manifest.json`（schemaVersion 2）: `lods`, `lodTransitions`, `source`, `regionSource`, `regions[{code,name,nameEn,prefectureCodes}]`, `files[{id, layer, lod, prefectureCode, regionCode, path, bbox, byteSize, featureCount, polygonCount, holeCount, vertexCount, sha256}]`（県境線は `polygonCount`/`holeCount` の代わりに `lineCount`）。
全国ファイルは `prefectureCode`/`regionCode` が null、地方ファイルは `prefectureCode` が null。

## 小さな島の除去（buildRevision 4〜）
`keep-shapes` は約12.5万の島をすべて残すため、buildRevision 3 まで LOD0 は1ファイル約12MB あり、頂点の約96%が10頂点以下の島だった。アプリはこれを読み込んだ直後に捨てており、実機で起動直後の読み込みが遅い主な原因と考えられた（未計測）。
- 各 LOD で「アプリがそのLODでは絶対に描かない島」を生成時に捨てる（`boundary_tools.mjs` の `prune-and-round`）。
  - 基準: 島の外接矩形の長辺が `そのLODの最小画面幅（lodTransitions の zoomInBelowMeters）÷ 100` 未満。LOD0 は7km、LOD1 は1.8km、LOD2 は450m。LOD3 は捨てない。manifest の `lods[].minPieceMeters` に記録。
  - アプリの `BoundaryPieceFilter` と同じ規則（各行政単位の最大の島は必ず残す、県境線は閉じた線＝島の海岸線だけを捨てる）なので、地図の見た目は変わらない。`APP_SCREEN_RESOLUTION`（=100）はアプリの `BoundaryPieceFilter.screenResolution` と必ずそろえる。
- 座標の丸めも同じ手順で、小さな島を捨てた後に行う。mapshaper の出力時に丸めると、ポリゴン側からは潰れた小さな島が消えるのに県境線側には残り、県境線の持ち主判定（頂点の完全一致）が失敗するため。潰れた穴は捨てる（そのLODでは1pt未満）。
- 島数の警告（`Outer component count changed`）は、島を捨てない LOD3 だけで確認する。

## 地方区分（国土地理院「日本の典型地形」地域別リスト準拠）
01北海道 / 02東北(02-07) / 03関東(08-14, **19山梨, 20長野**) / 04北陸(**15新潟**-18) / 05中部(21-24) / 06近畿(25-30) / 07中国(31-35) / 08四国(36-39) / 09九州(40-46) / 10沖縄(47)
- 甲信越・東海はない。リポジトリ直下の地方別 CSV（11区分）とは不一致。アプリでどちらを使うかは未決定。
- 変更は `regions.json` のみ編集 → 再生成。

## アプリへの組み込み
- Xcode の Resources に上記 5 つを追加済み（`municipalities/`・`prefectures/`・`prefectureLines/` はフォルダ参照）。バンドル直下にそのままコピーされ、manifest の `path` がそのまま使える。
- 生成物が無いとアプリのビルドが失敗する。クローン直後は下記「再生成」を先に行う。
- 使い方は リポジトリ直下 `README.md` の「市区町村パズル」を参照。

## 再生成
```bash
cd BoundaryData/scripts/mapshaper_boundary_tools && npm ci
bash build_boundaries.sh   # 入力は raw/ の原本
```
- Node 22+、mapshaper 0.7.65 固定。数分で完了。
- `generated/BoundaryData` が既にあると停止する → 先に別の場所へ移動する。
- `N03-20260101_prefecture.geojson` は使わない（別々に簡略化すると境界がずれる）。
- 流れ: 属性検査 → すき間・重なりの修復（`-clean`）と全国トポロジー化 → LOD ごとに全国一括で簡略化 → 結合・県境線生成・分割 → 小さな島の除去と座標の丸め（`prune-and-round`）→ 構造検査 → manifest 生成。
- 修復するのは市区町村どうしのすき間・重なりだけ（`-clean` の既定。修復内容は `reports/<実行ID>/02_normalize.log`）。コード欠損など属性の異常は修復せず停止する。実機検証は未実施（`releaseStatus: needs_spatial_and_device_review`）。

## 既知の問題
- **04606 松島町**: 全 LOD で島が 1875 → 1874 に減る（警告のみ）。
- **東京都の bbox が巨大**（沖ノ鳥島・南鳥島を含む）: bbox の重なりだけで読み込むファイルを決めると、関係ない範囲でも東京都が読み込まれる。
