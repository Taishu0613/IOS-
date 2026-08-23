# WAGhack

現在地を地図で確認し、訪れた市区町村と地域の豆知識を記録できるiOS 26向けSwiftUIアプリです。

## 機能

- MapKitによる現在地表示
- CSVの市区町村マスタ（1965件）を起動時にSwiftDataへ同期
- 右上の＋ボタンから現在地を市区町村単位で保存
- 同じ市区町村を再保存した場合は、重複させず保存日時と座標を更新
- 保存した場所を地図上のマーカーで表示
- SwiftDataによる市区町村マスタ、住所・座標・保存日時の永続化
- 保存した市区町村の一覧表示、削除、豆知識詳細の表示
- 豆知識の空欄は補完せず空欄のまま表示
- iOS 26のネイティブタブバーとLiquid Glass表現

## 画面構成

- **マップ**: 現在地、保存済みマーカー、市区町村保存ボタン
- **市区町村**: 保存した市区町村の一覧、削除、豆知識詳細への遷移

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
