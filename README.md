# WAGhack

現在地を地図で確認し、その住所を保存できるiOS 26向けSwiftUIアプリです。

## 機能

- MapKitによる現在地表示
- 右上の＋ボタンから現在地の住所を端末の言語・地域設定に合わせて保存
- 保存した場所を地図上のマーカーで表示
- SwiftDataによる住所・座標・保存日時の永続化
- 保存済み住所の一覧表示と削除
- iOS 26のネイティブタブバーとLiquid Glass表現

## 画面構成

- **マップ**: 現在地、保存済みマーカー、住所保存ボタン
- **保存済み**: 保存した住所の一覧、スワイプ・編集モードによる削除

## ディレクトリ構成

```text
WAGhack/WAGhack/
├── ContentView.swift                 # 2タブのルート画面
├── WAGhackApp.swift                  # SwiftDataコンテナの生成
├── Models/
│   └── SavedPlace.swift              # 保存する住所モデル
├── Services/
│   ├── LocationService.swift         # 現在地の取得
│   └── AddressResolver.swift         # 座標から住所への変換
└── Features/
    ├── Map/
    │   ├── MapScreen.swift           # 地図画面
    │   └── MapViewModel.swift        # 地図画面の状態と処理
    └── SavedPlaces/
        └── SavedPlacesScreen.swift   # 保存済み住所一覧
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
