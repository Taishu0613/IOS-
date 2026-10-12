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

未訪問ピンは未実装。行政区域の塗り分けは下記「市区町村パズル」を参照。
現在地カードは起動時・明示的な再確認時に加え、地図画面を開いている間は移動に合わせて更新する（下記「移動中の市区町村の自動判定」）。アプリがバックグラウンドにある間の追跡はしない（裏では粗い位置で初めての市区町村だけを知らせる。下記「初めての市区町村で通知」）。

## 2026年9月23日: 市区町村パズル（境界ポリゴン）

ブランチ: `feature/2026-09-23-silverweek`。マップに市区町村と県境を重ね、訪問済みの市区町村を塗りつぶす。
訪れるたびにピースが埋まっていく体験の土台。

- 訪問済み: ティールで塗る（アプリのテーマ色）。未訪問: 薄いグレーで塗る。どちらも縁の線は0.6〜2.8ptで、常に県境より細い（区別は太さと色の両方で付く）。現在地: ティールの太い縁取り（2.5〜4.2pt、常に県境より太い）。
- 線の太さは縮尺で変える（`BoundaryLineWidths`）。1ptあたりのmの対数で補間し、全国表示（約3,000m/pt以上）で最も細く、市区町村全体が収まる縮尺（約60m/pt以下）で最も太くする。カメラが止まったときだけ8段階に丸めて更新する（動かしている最中や小さな変化で全ピースを描き直さないため）。記録・脈打ちの演出の線も同じ倍率で太らせる。
- 県境・海岸線: 境界データの`prefectureLines`（線）を`MapPolyline`で描く。市区町村の線より太い不透明の灰色（全国表示1.2pt〜市区町村の縮尺4.0pt）で、主に太さと色味で市区町村の線と区別する。線の継ぎ目は丸める（鋭角がトゲ状に伸びるのを防ぐ）。1本の県境はデータ上1回しか入っていないので二重に描かない。
  - 線には`mapOverlayLevel(.aboveLabels)`を付けない（付けると線が描かれない。iOS 26.5シミュレータで確認）。現在地の縁取り（ポリゴン）だけ`.aboveLabels`に置く。
  - 以前は都道府県ポリゴンの外周を県境として描いていた。元データのすき間で県が複数のポリゴンに分かれていた場所（千代田・中央・港区の外周、田原市と豊橋市の間など8か所）に、県内なのに県境の線が出ていた。データ生成で`-clean`を入れ、県境を線データにして解消した。
- 表示モード: 踏破率ヘッダー上部のセグメント（市区町村｜都道府県）で切り替える（ヘッダーの横スワイプでも可）。市区町村では市区町村のピースを塗り、都道府県では都道府県ごとの制覇率で塗り分け、市区町村のデータは読み込まない。選択は`@AppStorage("map.progressPage")`で端末に保存（初期値は都道府県）。都道府県ページのままユーザーが画面幅40km以下まで拡大すると、市区町村ページへ自動で切り替える（`MapProgressPageZoomPolicy`。アプリが動かしたカメラでは切り替えない＝`MapCameraPosition.positionedByUser`で判定）。引いたときに都道府県ページへ戻す自動切り替えはしない。起動直後など都道府県が不明な間は保存値を書き換えずに都道府県ページを見せ、分かり次第保存した選択へ戻す。以前あった右上の境界メニュー（市区町村と県境／県境のみ）は、ヘッダーの切り替えと役割が重なるため廃止した。
- ピン表示: 地図右下の丸ボタンで、記録した場所のピンの表示／非表示を切り替える。選択は`@AppStorage("map.showsPlacePins")`で端末に保存（初期値は表示）。再記録直後の吹き出しはピンを隠していても出す。
- 塗り分けはSwiftDataの`SavedPlace`から毎回導出し、ポリゴン側に訪問状態を持たない。記録を削除すると塗りも戻る。
- 政令指定都市は区のコードで記録されるため、区のピースが埋まる。親市だけの記録では塗らない（踏破率の規則と同じ）。
- 出典（国土数値情報 N03、CC BY 4.0）は「旅の記録」画面の末尾に`attribution.txt`の文面で表示する。
- 進捗に添える小さな地図（記録済みの区画をティール、未記録を薄い灰色で塗る）。
  - 踏破率ヘッダー（56pt）: 市区町村ページに現在地の都道府県、都道府県ページに日本地図。
  - 旅の記録シート（96pt）: 進捗の隣に日本地図。都道府県シート（96pt）: 進捗の隣にその県（市区町村ごとに塗り分け）。
  - 市区町村詳細シート: 見出しの下に、その市区町村の形を高さ220ptで大きく描く。塗らずにティールの縁取り（2.5pt、淡い影付き）だけにする。形はリストの背景に固定して描き、リスト先頭には同じ高さの透明な行を置く。スクロールするとカードが形の上に覆い被さる。
  - 塗りは踏破率と同じデータで決める（都道府県は`ExplorationSummary.visitedPrefectures`、市区町村は`PrefectureExploration.visitedCodes`）。
  - 使うデータ: 日本地図はLOD0（起動後に1回）、県の地図は県ごとのLOD1、市区町村の形は県ごとのLOD3（詳細を開いたときだけ）。
  - `SilhouetteMapStore`（`MapScreen`が所有し、シート内の画面へはenvironmentで渡す）が読み込み、`BoundarySilhouetteBuilder`で描画サイズに合わせて間引いた地図を保持する。作った地図は残し、同じ県・市区町村では読み直さない。地図用の`MunicipalityPuzzleStore`とはリポジトリを共有しない（キャッシュのフィルタ前提が異なるため）。
  - 間引き: 描画サイズに対して許容誤差0.4pt。描画時は頂点の中点を曲線でつないで角を丸める。1.5ptまで粗くすると県の形が分からなかった。
  - 日本地図は北海道〜九州を本体とし、沖縄県は左上の小窓に縮尺を変えて描く。奄美・小笠原など本体の範囲外の離島は描かない。
  - 県の地図の枠は最大ピース（本土）に合わせる。描くのは本土に載っている区画と、県の地図の大きさに対して10%以上の大きな島（佐渡島・淡路島など）だけで、小さな離島だけの町村は描かない。この省略は小さな地図だけで、メインの地図のパズルでは島も描く。
  - 読み込み前も枠の大きさは確保する（地図が現れたときにレイアウトが揺れないように）。Listの行は中身が空だと行ごと省かれ`.task`も動かないため、透明な下地を置く。

### LODと描く内容

`manifest.json`の`lodTransitions`（拡大時と縮小時で閾値が異なるヒステリシス付き）で、カメラ停止時の画面横幅からLODを決める。

| LOD | 画面横幅の目安 | 市区町村 | 県境 |
|---|---|---|---|
| 0 | 約800km〜4,000km（全国） | 訪問済み・現在地だけ | 描く |
| 1 | 約200〜800km | 訪問済み・現在地だけ | 描く |
| 2 | 約50〜200km | 未訪問も含めてすべて | 描く |
| 3 | 〜約50km | 未訪問も含めてすべて | 描く |

4,000kmより広い範囲（日本が画面の一部にしか映らない縮尺）では何も描かない。

### 重さへの対策

MapKitはポリゴン1枚ごとに描画を持つため、枚数がそのまま重さになる。

- 未訪問の網目はLOD2以上だけで描く。全国で約2,000枚・LOD1で約1,500枚だったものが、県境・海岸線（全国で約180本）と訪問済みの枚数だけになる。LOD2の網目は最大で約600枚。
- 画面幅の1/100（約4pt）未満の島は描かない。輪郭線を付けると点の塊になり、海岸沿いに並ぶと線が太い帯に見えるため。各行政単位の最大のピースだけは縮尺に関係なく必ず描く。
- ピースのidにはLODを含める。含めないとLODが変わってもidが同じになり、地図側が古いLODの形を残したまま新しい形を重ねる。簡略化の違う2本の線が重なって、境界の一部（それまでに別のLODで表示した範囲）だけが太い帯に見えていた。
- 先読みする範囲は表示範囲の上下左右20%（以前は50%で、描く面積が約2倍になっていた）。基準の表示範囲はヘッダー・シートの裏も含めた地図のビュー全体（`MapFullFrameRect`）。以前はセーフエリアの内側だけを基準にしていたため、半透明のヘッダーやシートの裏でピースが途切れて見えた。

### 起動直後の待ち時間への対策（2026-09-24）

実機で起動直後、境界と現在地の表示まで長く待たされていた。主な原因は次の2つと見ている（Instrumentsでの計測は未実施）。

- 全国ファイル（LOD0）が1レイヤ約12MB（頂点約50万）あり、その約96%は描かれない小さな島だった。起動時は日本全体が映るため、これを複数レイヤ分デコードしていた。
  → データ生成で、各LODで絶対に描かれない島を捨て、粗いLODの座標の桁を減らした（`BoundaryData/README.md`「小さな島の除去」）。描く規則はアプリの`BoundaryPieceFilter`と同じなので見た目は変わらない。
- 現在地が分かるまでカメラが`.automatic`（ピン全体、多くは日本全体）だったため、まずLOD0を読み、その後で現在地周辺を読み直していた。
  → 最後にカメラが止まった範囲を`MapRegionMemory`（UserDefaults `map.lastRegion`）に保存し、次の起動では現在地が分かるまでその範囲を見せる。初回起動など保存が無いときは従来どおり`.automatic`。
- 地図を現在地へ寄せるのが、住所の確認（`MKReverseGeocodingRequest`、通信あり）の後だった。
  → 起動時の現在地の取得では、座標が分かった時点で地図を寄せる（`MapViewModel.refresh`の`onLocationResolved`）。市区町村の特定と「現在地の市区町村を確認しています…」の表示はその後も続く。

### 責務とデータフロー

`カメラ停止(onMapCameraChange .onEnd) / 表示モード変更 → MunicipalityPuzzleStore → BoundaryRepository(actor) → 市区町村ピース + 県境線 +（都道府県表示のとき）都道府県の面`
`上記 + SavedPlaceの訪問コード + 現在地コード + 制覇率 → MunicipalityPuzzleLayer（MapContent）`

`Features/Map/MunicipalityBoundaries/`にまとめてあり、フォルダごと消せば機能を外せる。

| ファイル | 責務 |
|---|---|
| `Models/AdministrativeBoundary.swift` | 境界の値型（経緯度の矩形・ポリゴン・行政単位・県境線`BoundaryLine`） |
| `Models/BoundaryManifest.swift` | manifest.jsonの読み取り。レイヤ（`BoundaryLayer`）・LOD・表示範囲からファイルを選ぶ |
| `Models/BoundaryLOD.swift` | 画面幅からLODを決める（ヒステリシス） |
| `Models/BoundaryPieceFilter.swift` | 縮尺に対して小さすぎる島を省く規則 |
| `Data/BoundaryGeoJSONDecoder.swift` | ポリゴンのGeoJSON → 値型への変換（市区町村`{c,n,p}`・都道府県`{p,n}`） |
| `Data/BoundaryLineGeoJSONDecoder.swift` | 県境線のGeoJSON → `BoundaryLine`（`{p,k}`、kは`border`/`coast`） |
| `Data/BoundaryRepository.swift` | バンドルからの読み込み（メインスレッド外）とファイル単位のLRUキャッシュ（48件） |
| `MunicipalityPuzzleStore.swift` | 表示範囲・モード → LOD → ファイル → 描くピース。未訪問の網目を描くかも決める。古い読み込みは取り消す |
| `MunicipalityPuzzleLayer.swift` | 塗り分けと重なり順（`MunicipalityPieceStyle` / `PrefectureBorderStyle`） |
| `BoundaryDisplayMode.swift` | 読み込む境界の種類。ユーザーは直接選ばず、`MapScreen`が踏破率ヘッダーのページから決める |
| `BoundaryAttributionView.swift` | 出典表示 |

### 組み込みと注意点

- Xcodeプロジェクトは`BoundaryData/generated/BoundaryData/`の`manifest.json`・`attribution.txt`・`municipalities/`・`prefectures/`・`prefectureLines/`（フォルダ参照）をバンドル直下へコピーする。都道府県ポリゴンは制覇率の塗りにだけ使う。
  生成物はGit管理外のため、**クローン直後は`BoundaryData/README.md`の手順で再生成しないとビルドが失敗する**。
- 同梱サイズは市区町村・都道府県・県境線レイヤで約188MB（地方レイヤは未使用のため含めない）。
- 全国の市区町村ファイル（12MB）の初回デコードはMacで約0.7秒かかる。actor上で行い、以降はキャッシュを使う。
- 県境線のデータには海岸線も入っていて、県境と同じ線で描く。全国の県境線ファイル（LOD0）の初回デコードはMacで約1.4秒。
- 訪問済みが数百件になると、全国表示でも同じ数だけポリゴンが増える（すべて埋めると約2,000枚）。
- ポリゴンのタップ選択には対応していない（SwiftUIの`Map`の選択はMarker/Annotationが対象）。
- 実機での描画性能・メモリは未検証。シミュレータ（iPhone 14 Plus / iOS 26.5）で、全国〜LOD3の表示・県境・表示モードの切替を確認済み。
- LODの判定・島の間引き・GeoJSON変換（ポリゴン・県境線）・ファイル選択は`MunicipalityBoundaryTests`で検証する。

### 地図の現在地操作

- 現在地ボタンとピン表示ボタンは地図右下、シートの上に縦並びで配置する。どちらも56pt、アイコンはtitle2。
- 現在地ボタンとヘッダーの現在地バッジは、表示モードに合わせた区域の範囲へ移動する。
- 市区町村は表示用の間引きとは独立して、その県の最詳細境界を読み込み、離島・飛び地を含む区域全体に余白を付けて収める。100kmの上限は適用しない。都道府県の縮尺の決め方は維持する。
- 境界を取得できない場合は従来の現在地周辺表示へ戻し、読み込みエラーは開発者ログに残す。

### 移動中の市区町村の自動判定（2026-09-26）

アプリを開いたまま移動して別の市区町村に入ったら、現在地ボタンを押さなくても、既存の「新しい市区町村に入った」演出（脈打ち→誘いシート）を出す。

- `LocationService.accurateLocationUpdates`で`CLLocationUpdate.liveUpdates`を受け、`MapViewModel.monitorMunicipalityChanges`が判定する。市区町村が変わった時だけ`currentVisit`を差し替え、既存の`municipality.code`のonChangeに任せる。
- 判定中も`currentVisit`を消さず、進行状況の表示・エラー・エラーの触覚は出さない（失敗は開発者ログのみ）。
- 電池と通信への配慮:
  - 住所の確認（通信あり）は、前回から**300m以上**移動し、かつ前回の自動判定から**30秒以上**たった時だけ。精度が**100m**より粗い位置は使わない。
  - 3つの値は`MapViewModel`の定数（`automaticCheckDistance` / `automaticCheckInterval` / `automaticCheckMaximumAccuracy`）。仮の値で、実機で歩き・車・電車を試して調整する前提。
  - 地図の`UserAnnotation`のためにGPSは元々動いているので、位置を受ける側を1本足す負担は小さい。静止中はCore Locationが更新を自動で止める。
- 監視するのは`MapScreen.canMonitorMunicipalityChanges`がtrueの間だけ（前面にある・儀式/誘いシートを出していない・現在地が一度は取れている）。**儀式シートを新しく足したら、この条件にも加えること**（表示中のシートの市区町村が書き換わらないようにするため）。
- 誘いシートは、ピン選択中・旅の記録を広げている間は出ない（既存の`handleMunicipalityVisitChange`の判定）。記録を折りたたんだ時に出る。
- 自動判定中に現在地ボタン・記録が始まったら、そちらの結果を優先する（`locationRequestGeneration`で古い結果を捨てる）。
- 移動中の実機での動作は未検証。Simulatorでは Features > Location > Freeway Drive などで確認する。

## 初めての市区町村で通知（2026-10-12）

ブランチ: `feature/first-city-notification`。記録が一度もない市区町村に入ったら、アプリを閉じていてもローカル通知で知らせる。
「旅の記録」画面の「初めての市区町村で通知」トグルでオンにする（初期値はオフ）。

- 「初めて」の判定は既存の記録（`SavedPlace`の市区町村コード）をそのまま使う。政令指定都市は区のコードで判定し、親市だけの記録では区を記録済みとみなさない（踏破率の規則と同じ）。
- 裏での位置はCore Locationの大幅な位置の変化（significant-change location service）で受け取る。約500m以上の移動でしか届かず、GPSを常時動かさないので電池への負担が小さい。アプリが終了していても、位置が変わればシステムが裏で起動し直す（iOS 26.5シミュレータで、`simctl terminate`後に位置を動かして通知が出ることを確認）。ユーザーがアプリスイッチャーで終了させた場合はOSが起動し直さない。
  - 却下した案: `CLBackgroundActivitySession`＋`liveUpdates`による常時追跡。GPSを動かし続けて電池を大きく使う割に、市区町村単位の判定には精度が過剰。
- 裏で位置を受け取るには位置情報の「常に」許可が要る（`NSLocationAlwaysAndWhenInUseUsageDescription`）。トグルをオンにした時に通知と「常に」の許可を求め、起動時には求めない。足りない許可は脚注で伝え、設定アプリへの導線を出す。
- 前面にある間は地図画面が自前の誘いシートを出すため通知しない。その場合も「知らせた」ものとして履歴に残し、裏へ回った後に同じ市区町村を通知しない。
- 同じ市区町村の中で位置が変わっただけでは通知しない。境界を行き来しても、一度知らせた市区町村は12時間通知しない（`NewMunicipalityAlertPolicy.renotifyInterval`）。
- 判定に使う位置の精度の上限は1,000m（`NewMunicipalityAlertMonitor.maximumHorizontalAccuracy`）。大幅な位置の変化は基地局・Wi-Fiの粗い位置で届くことが多いため、地図画面の自動判定（100m）より緩い。12時間・1,000mとも仮の値で、実機で調整する。
- 通知をタップするとアプリが開き、地図画面が現在地を確認して従来の誘いシートを出す（通知専用の画面遷移は持たない）。

### 責務とデータフロー

`大幅な位置の変化 → NewMunicipalityAlertMonitor → AddressResolver + MunicipalityMatcher → SavedPlaceの記録コード → NewMunicipalityAlertPolicy → UNUserNotificationCenter`

`Features/NewMunicipalityAlert/`にまとめてあり、フォルダと`WAGhackApp`・`SavedPlacesScreen`の各1か所を消せば機能を外せる。

| ファイル | 責務 |
|---|---|
| `NewMunicipalityAlertPolicy.swift` | 通知するかの判定と履歴（値型。位置情報・通知・SwiftDataに依存しない） |
| `NewMunicipalityAlertMonitor.swift` | 位置の監視・許可の要求・住所照合・通知の発行。`WAGhackApp`が所有し、environmentで画面へ渡す |
| `NewMunicipalityAlertSettingsSection.swift` | 「旅の記録」画面のトグルと許可の案内 |

- オン/オフは`UserDefaults`の`newMunicipalityAlert.isEnabled`、判定の履歴は`newMunicipalityAlert.history`（JSON）。永続モデル（SwiftData）は変更しない。
- 裏で起動し直された場合も位置を受け取れるよう、`WAGhackApp`の初期化で`startIfEnabled()`を呼ぶ（画面が作られるのを待たない）。
- 判定のロジックは`NewMunicipalityAlertPolicyTests`で検証する。実機での電池消費・通知の遅れは未検証。
