# WAGhack

現在地を地図で確認し、訪れた市区町村と地域の豆知識を記録できるiOS 26向けSwiftUIアプリです。

## 機能

- MapKitによる現在地表示
- CSVの市区町村マスタ（1965件）を起動時にSwiftDataへ同期
- マップ下部の記録ボタンから現在地を市区町村単位で保存
- 同じ市区町村を再保存した場合は、重複させず保存日時と座標を更新
- 保存した場所を地図上のマーカーで表示
- SwiftDataによる市区町村マスタ、住所・座標・保存日時の永続化
- 全国・都道府県ごとの市区町村踏破率、達成状況、次の目標を表示
- 都道府県別の図鑑で、訪問済み・未訪問を絞り込み
- 市区町村の訪問削除、未訪問も含む豆知識詳細の表示
- 豆知識の空欄は補完せず空欄のまま表示
- iOS 26のネイティブタブバーとLiquid Glass表現

## 画面構成

- **マップ**: 現在地、保存済みマーカー、市区町村保存ボタン
- **市区町村**: 全国の旅の記録 → 都道府県別の図鑑 → 市区町村の豆知識。訪問済み行のスワイプで訪問を削除

## ディレクトリ構成

```text
WAGhack/WAGhack/
├── ContentView.swift                 # 2タブのルート画面
├── WAGhackApp.swift                  # SwiftDataコンテナの生成
├── Models/
│   ├── Municipality.swift            # 市区町村マスタモデル
│   └── SavedPlace.swift              # 保存した市区町村と訪問情報
├── Services/
│   ├── LocationService.swift         # 現在地の取得
│   ├── AddressResolver.swift         # 座標から表示用・照合用住所への変換
│   ├── CSVParser.swift               # 引用符・改行・空欄対応のCSV解析
│   ├── MunicipalityMasterImporter.swift # CSVからマスタレコードへの変換
│   ├── MunicipalityMasterStore.swift # ModelActor上でSwiftDataへ同期
│   └── MunicipalityMatcher.swift     # 日本語住所と市区町村マスタの照合
└── Features/
    ├── Map/
    │   ├── MapScreen.swift           # 地図画面
    │   └── MapViewModel.swift        # 地図画面の状態と処理
    └── SavedPlaces/
        └── SavedPlacesScreen.swift   # 市区町村一覧と豆知識詳細
```

## 使用技術

- SwiftUI
- MapKit for SwiftUI
- Core Location `CLLocationUpdate.liveUpdates()`
- MapKit `MKReverseGeocodingRequest`
- SwiftData
- Observation

## 実行時の注意

初回起動時に位置情報の使用許可を求めます。シミュレータで確認する場合は、Simulatorの位置情報メニューからテスト用の現在地を設定してください。

市区町村マスタはリポジトリ直下の `LocalGovernmentCodeJapan_Knowledge.csv` をアプリへ同梱し、起動時に行政区域コードをキーとしてSwiftDataへ同期します。CSVを更新した場合は、次回起動時に既存マスタも更新されます。

## 2026年9月12・13日: 旅の図鑑

作業ブランチ: `feature/2026-09-12-13-saved-places-gamification`

### 踏破率の規則

- 分母は同梱マスタ内の対象市区町村数。都道府県行と、区を持つ政令指定都市の親市行は除外する。
- 政令指定都市は区単位、東京都の特別区は区単位、その他は市町村単位。行政区域コードで重複排除する。
- 分子は対象コードと訪問済みコードの共通部分。全国の率は市区町村数の合計から求める（都道府県の率の平均ではない）。
- 親市だけの記録から区の訪問は推測しない。未照合・集計対象外の記録は全国画面の別欄に残し、確認・削除できる。
- 25・50・75・100%の節目と、次の節目までの市区町村数を表示する。達成表示は現在の記録から導出し、削除すると戻る。
- マスタ更新で対象数が変われば率も変わる。固定の自治体総数や面積割合ではない。

### 責務とデータフロー

`SwiftData → @Query → SavedPlacesStore → ExplorationProgressCalculator → 各View`

- `ExplorationProgress.swift`: SwiftData/SwiftUIに依存しない集計用の値型、対象判定、率、節目計算。
- `SavedPlacesStore.swift`: Query結果を集計入力へ変換し、削除・保存失敗時のrollbackを担当。進捗を永続化・二重保持しない。
- `SavedPlacesScreen.swift`: 全国サマリー、都道府県一覧、集計対象外の記録。
- `PrefectureExplorationScreen.swift`: 都道府県の図鑑と訪問状況の絞り込み。
- `ExplorationProgressCard.swift`: 共通の進捗表示と都道府県行。標準のProgressViewと可変文字サイズを使用。
- `MunicipalityDetailScreen.swift`: 訪問の有無に依存しない豆知識詳細。

SwiftDataのQueryを取得層として維持し、単一実装だけのRepository/protocolは追加しない。
永続モデルの変更、新規依存ライブラリの追加はなし。既存のiOS 26.2以上のアプリ設定に合わせる。

### 検証

`ExplorationProgressTests`で空データ、政令市・特別区、全国の加重集計、重複コード、節目の切り上げ、フィルター、SwiftDataでの訪問削除を検証する。

## MAPアップデート: 探索と記録

ブランチ: `feature/2026-09-12-13-map-exploration`（図鑑ブランチから作成）。

- 起動時に現在地の市区町村を確認し、下部カードで訪問状況と記録ボタンを表示。
- 訪問済みピンをタップすると、選択色、最終訪問日、豆知識へのシートを表示。選択解除で現在地カードへ戻る。
- 上部は現在地または選択ピンの都道府県進捗。未特定時は全国の訪問都道府県数を表示。
- 記録操作では現在地を再取得する。選択中のピンや古い位置を保存しない。
- 初訪問・再訪問・25/50/75/100%達成を区別。成功時はカード内に結果を表示し、確認アラートを出さない。
- ピン選択・保存成功・失敗に標準触覚フィードバック。実際の振動は対応する実機で確認する。
- 現在地の再確認ボタン、読み込み状態、再試行可能なエラーを表示。位置情報を許可しなくても保存済みピンの閲覧は可能。
- Reduce Motionに対応。カードはスクロール可能で、大きな文字でも操作へ到達できる。

### MAPの責務分離

`MapScreen`はQueryと選択・カメラを所有し、`MapViewModel`が位置取得・住所照合・処理状態を管理。
`MapVisitRecorder`が保存と再訪問更新、保存失敗時のrollback、節目判定を担当する。
`MapExplorationCards`は状態と操作クロージャを受け取って描画する。
共有集計と豆知識画面は`Shared/Exploration`へ移し、図鑑とマップから利用する。
進捗は永続化せず、SwiftDataの最新記録から導出する。永続モデルや外部依存は変更しない。

未訪問ピン・行政区域の塗り分けは未実装（代表座標・境界データが別途必要）。
現在地カードは起動時と明示的な再確認時に更新し、連続的なバックグラウンド追跡はしない。
