# 全国市区町村・都道府県・地方 GeoJSON 生成ツール

2026年版 N03 の全国市区町村 GeoJSON から、アプリ同梱用データを生成します。
入力は `N03-20260101.geojson` です。都道府県外形と地方外形は同じ市区町村形状を結合して生成するため、
`*_prefecture.geojson` は使いません（別々に簡略化すると境界がずれるため）。

## フォルダ構成

このツールは `BoundaryData/scripts/mapshaper_boundary_tools/`（リポジトリ直下）に置く前提です。
入出力先は 2 階層上の `BoundaryData/`（環境変数 `DATA_ROOT` で変更可）を基準にします。

| フォルダ | 役割 |
|---|---|
| `raw/N03-20260101_GML/` | 入力の原本（既定の入力パス） |
| `scripts/mapshaper_boundary_tools/` | このツール |
| `normalized/<実行ID>/` | 中間データ（属性テーブル・未簡略化トポロジー）。成功時に最新 1 回分だけ残す |
| `reports/<実行ID>/` | 処理ログ、属性検査、ファイル検査、原本の SHA-256、使用した `regions.json` |
| `generated/BoundaryData/` | アプリに同梱するフォルダ |

## 実行

Node.js 22以上と npm を使います。

```bash
npm ci
bash build_boundaries.sh
```

引数を省略すると `raw/N03-20260101_GML/N03-20260101.geojson` を読みます。別の場所の原本を使う場合はパスを引数で渡します。

## 地方区分

`regions.json` が地方区分の唯一の定義です。国土地理院「日本の典型地形」の地域別リストに準拠した 10 地方です。

| コード | 地方 | 都道府県コード |
|---|---|---|
| 01 | 北海道 | 01 |
| 02 | 東北 | 02–07 |
| 03 | 関東 | 08–14, 19（山梨）, 20（長野） |
| 04 | 北陸 | 15（新潟）–18 |
| 05 | 中部 | 21–24 |
| 06 | 近畿 | 25–30 |
| 07 | 中国 | 31–35 |
| 08 | 四国 | 36–39 |
| 09 | 九州 | 40–46 |
| 10 | 沖縄 | 47 |

区分を変える場合は `regions.json` だけを編集して再生成します。全都道府県がちょうど 1 地方に属さないと停止します。

## 出力

| LOD | DP interval | 市区町村・都道府県・県境線の分割 | 地方の分割 |
|---|---|---|---|
| 0 | 2000m | 全国 1 ファイル | 全国 1 ファイル |
| 1 | 500m | 都道府県 47 ファイル | 地方 10 ファイル |
| 2 | 100m | 都道府県 47 ファイル | 地方 10 ファイル |
| 3 | 20m | 都道府県 47 ファイル | 地方 10 ファイル |

市区町村 142 + 都道府県 142 + 県境線 142 + 地方 31 + manifest.json + attribution.txt = 459 ファイルです。
全 LOD を同じ未簡略化データから生成します。

各 Feature の属性:

| レイヤ | 属性 |
|---|---|
| 市区町村 | `c` 市区町村コード, `n` 名前, `p` 都道府県コード, `r` 地方コード |
| 都道府県 | `p` 都道府県コード, `n` 名前, `r` 地方コード |
| 地方 | `r` 地方コード, `n` 地方名 |
| 県境線 | `p` 持ち主の都道府県コード（LOD0 はなし）, `k` `border`=県境 / `coast`=海岸線 |

県境線は `-lines p` で「都道府県コードが変わる境目」（RANK 1）と「外周＝海岸線」（RANK 0）だけを取り出し、
`boundary_tools.mjs prefecture-lines` で各線を 1 県に割り当てて（県境は隣り合う 2 県のうちコードの小さい方）、
つながる線を 1 本にまとめてから都道府県ごとのファイルに分けます。同じ LOD の都道府県ポリゴンと頂点が完全一致することを使って割り当てます。

`manifest.json` には各ファイルの `prefectureCode` / `regionCode`、および `regions`（地方の定義）が入ります。

## 注意

原本は上書きしません。出力先 `generated/BoundaryData` がすでにある場合は停止します。再実行時は既存出力を別の場所へ移動してください。
コード欠損・不正や属性仕様の不一致は、勝手に除去せず停止します。
正規化の段階で `-clean` を実行し、市区町村どうしのわずかなすき間・重なりを修復します（2026年版では幅 5.6m 以下の 16 か所）。
修復しないと境目がトポロジー上で共有されず、県が複数のポリゴンに分かれて県内に誤った県境が出ます。
修復後の `-dissolve ... no-repair` は、すでにトポロジーが整っている前提で自動修復を省く設定です。
`-explode` 後の `keep-shapes` で各外周部分を保護しますが、穴や極小形状の変化は出力後に確認してください。
ヒープ上限は 8192 MB ですが、プロセス全体のメモリ上限ではありません。

## 検証範囲

全国原本（SHA-256 `3095bfbb…7751`）で一括実行し、構造検査（コード網羅・重複・属性・リング形状）に合格することを確認しています。
構造検査の合格は、境界の幾何的正しさ・実機性能・公開可否の保証ではありません。
公開前に出典表示と必要な利用手続きを確認してください。

## Official references

- https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N03-2026.html
- https://www.gsi.go.jp/kikaku/tenkei_kanto.html （地方区分）
- https://mapshaper.org/docs/essentials/command-line.html
- https://mapshaper.org/docs/reference.html
- https://mapshaper.org/docs/guides/simplification.html
- https://mapshaper.org/docs/guides/topology.html
- https://mapshaper.org/docs/formats/geojson.html
