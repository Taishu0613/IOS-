import MapKit
import SwiftData
import SwiftUI

struct MapScreen: View {
    /// マスタ準備中・チュートリアル表示中はfalse。ContentViewは初期化の重さを先に済ませるため、
    /// それらの裏でもMapScreenを生成しておく。falseの間はシートの提示も現在地取得(位置情報の
    /// 許可ダイアログ)も始めない。出してしまうと手前の読み込み画面やチュートリアルをシートが覆う。
    var isActive = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @Query(MapScreen.municipalityDescriptor) private var municipalities: [Municipality]
    @Query private var visitedPrefectures: [VisitedPrefecture]

    @State private var cameraPosition: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var viewModel = MapViewModel()
    @State private var selectedPlaceID: PersistentIdentifier?
    @State private var actionTask: Task<Void, Never>?
    @State private var mapHeight: CGFloat = 0
    /// ヘッダー(進捗カード+現在地バッジ/戻るボタンの行)の実測高さ。MapKit標準のコンパス/スケール表示が
    /// ここに被らないよう、Mapのセーフエリアをこの分だけ広げる。
    @State private var headerOverlayHeight: CGFloat = 0
    @State private var isSheetPresented = false
    @State private var sheetDetent: PresentationDetent = .height(Self.recordsCompactHeight)
    /// シートが中段以上に広がっているか。折りたたみ中は現在地カード、広げると旅の記録のスタックに切り替わる。
    @State private var isSheetExpanded = false
    @State private var sheetPath: [MapSheetRoute] = []
    @State private var isJapanIntroPresented = false
    @State private var isPrefectureIntroPresented = false
    @State private var isMunicipalityInvitationPresented = false
    @State private var isMunicipalityCelebrationPresented = false
    /// 都道府県・市区町村どちらの初訪問儀式よりも先に実行したい処理を一時的に預かる。
    /// 日本の儀式を確定した直後に、元々起ころうとしていた処理(儀式の提示)をやり直すために使う。
    @State private var pendingAfterJapanIntro: (() -> Void)?
    /// 「日本」の儀式を出す前に、地図のカメラが移動し終えるのを待っている目的地。nilなら待っていない。
    @State private var japanIntroCameraTarget: CLLocationCoordinate2D?
    /// バージョンに紐づくチュートリアルとは独立に、「日本」を記録する儀式を見せたかどうかを覚える。
    /// アプリを以前から使っているユーザーにも一度は見せたいため、チュートリアルの表示有無に関係なく
    /// このフラグ単独で判定する。
    @AppStorage("japan.hasRecorded") private var hasRecordedJapan = false
    /// 都道府県を記録できた回数。触覚のきっかけにだけ使う。儀式シートは記録と同時に閉じるため、
    /// シートの中に触覚を付けると閉じる途中で取り除かれて鳴らないことがあり、常に残るこの画面側で鳴らす。
    @State private var prefectureRecordedFeedback = 0
    /// 各儀式シートの実測高さ。Wikipedia画像が非同期で後から差し込まれて縦に伸びるため、
    /// 固定値ではなく実測してシートの高さに反映する(初期値は画像0枚の時の見た目に合わせてある)。
    /// 「日本」の儀式シートだけは帯の場所を最初から確保した固定の高さにしている(presentationHeight参照)。
    @State private var prefectureIntroHeight: CGFloat = 340
    /// 再記録の完了を「更新済み」ボタンとピンの吹き出しで見せている間の状態。nilなら見せていない。
    /// 保存中かどうかはMapViewModel.operationが持ち、ここは完了後の表示だけを持つ。表示してよいかが
    /// シートの展開・ピンの選択というこの画面の状態に依存するため、ViewModelではなくここで持つ。
    @State private var rerecordConfirmation: MapRerecordConfirmation?
    @State private var municipalityInvitationHeight: CGFloat = 360
    @State private var municipalityCelebrationHeight: CGFloat = 360
    /// municipalities/savedPlacesが実際に変わった時だけ計算し直す。ピン選択などのUI操作のたびに
    /// 全市区町村(1,898件)を集計し直すと体感できるラグになるため、bodyでは計算しない。
    @State private var summary = ExplorationSummary(prefectures: [], eligibleCodes: [])

    // 折りたたみ時のシート高さ。内容の行数が状態で変わるため、状態ごとに固定値を持つ。
    /// 「旅の記録」の1行(MapRecordsSummaryRow)だけの高さ。訪問済みでも未訪問でも行数は変わらない
    /// (違いは右端の再記録ボタンの有無だけ)ので、1つの値にまとめている。再記録の保存中・完了後も
    /// ボタンの見た目が変わるだけで行は増やさない(`MapViewModel.Operation.statusText`参照)。
    /// 地図を最大限見せる最小の状態も兼ねるため、これより小さく畳む段階は持たない。
    private static let recordsCompactHeight: CGFloat = 76
    private static let locatingCompactHeight: CGFloat = 140
    private static let errorCompactHeight: CGFloat = 235

    /// 地図を目的地へ寄せるカメラアニメーションの長さ。再記録の吹き出しは、この移動が終わってから出す。
    private static let focusAnimationDuration: TimeInterval = 0.35
    /// 再記録の完了から吹き出しを出すまでの待ち時間。保存完了と同時に始まる`focusMap`の移動が
    /// 終わってから出す。移動完了を`onMapCameraChange`で待たないのは、再記録は同じ場所で行うことが多く、
    /// カメラが実際には動かず完了通知が来ないことがあるため。
    private static var rerecordCalloutDelay: Duration { .seconds(focusAnimationDuration) + .milliseconds(50) }
    /// 吹き出しを見せておく時間。
    private static let rerecordCalloutDuration: Duration = .milliseconds(2500)
    /// 吹き出しを透明にしてから取り除くまでの時間(フェードの長さ)。
    private static let rerecordDismissDuration: TimeInterval = 0.2

    /// SwiftUIのMapからは地図タイルの描画完了を受け取れないため、カメラの移動完了からこれだけ置いて
    /// 「現在地周辺の地図が読み込まれた」とみなし、「日本」の儀式を出す。
    /// 初回の許可直後は地球儀の視点から現在地まで一気に移動して3D地図の読み込みが集中するため、
    /// 短くすると読み込み中の地図の上でシートの演出が重なって重くなる。
    private static let mapSettleDelay: Duration = .milliseconds(500)
    /// カメラの移動完了が通知されない場合(既に同じ位置を表示していて移動が起きない等)でも、
    /// 「日本」の儀式を必ず出すための待ち時間の上限。
    private static let cameraSettleTimeout: Duration = .seconds(3)
    /// 現在地へ地図を寄せる時の表示範囲(縦横のメートル)。
    private static let focusSpanMeters: CLLocationDistance = 1_200
    /// カメラの移動完了が「現在地への移動」によるものかを判定する許容距離。
    /// Mapは上側のセーフエリアをヘッダー分広げているため、カメラが現在地を中心に合わせても
    /// `context.region.center`とは百数十mずれうる(未計測)。狭い許容距離だと判定を外してタイムアウトまで
    /// 待たされるため、表示範囲の半分まで許容する。初期表示の地球儀視点は数千km離れているので区別できる。
    private static var cameraArrivalTolerance: CLLocationDistance { focusSpanMeters / 2 }

    /// 地図画面で使う列(集計と住所照合に必要な分)だけを読み込む。みどころ・歴史のテキストはマスタ全体で
    /// 約1MBあり、全件を画面生成時にメインスレッドで読み込むと体感できる固まりになるため除外する。
    /// 除外した列も、市区町村詳細などで実際にアクセスした時点でSwiftDataが個別に読み込む。
    private static var municipalityDescriptor: FetchDescriptor<Municipality> {
        var descriptor = FetchDescriptor<Municipality>(sortBy: [SortDescriptor(\.code)])
        descriptor.propertiesToFetch = [
            \.code, \.prefectureCode, \.prefectureName, \.municipalityName, \.isPrefecture,
        ]
        return descriptor
    }

    private var selectedPlace: SavedPlace? {
        savedPlaces.first { $0.persistentModelID == selectedPlaceID }
    }

    private var isCurrentPlaceVisited: Bool {
        guard let code = viewModel.currentVisit?.municipality.code else { return false }
        return savedPlaces.contains { $0.municipality?.code == code }
    }

    /// 初めての市区町村・節目の達成は`MunicipalityFirstVisitSheet`という専用の儀式で見せる。
    /// それ以外(単なる再訪問の更新)はシートを出さず、再記録ボタンの状態遷移とピンの吹き出しで伝える
    /// (`MapVisitFeedbackPolicy`参照)。
    private var celebratesInDedicatedSheet: Bool {
        guard let result = viewModel.result else { return false }
        return result.kind != .update
    }

    /// 再記録ボタンの見た目。状態としては持たず、「保存中か」(viewModel.operation)と
    /// 「更新済みを見せている最中か」(rerecordConfirmation)から毎回計算する。
    private var rerecordButtonPhase: MapRerecordButtonPhase {
        if viewModel.isRerecording { return .recording }
        switch rerecordConfirmation?.stage {
        case .updated, .showingCallout:
            return .updated
        // 吹き出しを消し始めた時点でボタンは「再記録」に戻し、次の再記録を受け付ける。
        case .dismissing, nil:
            return .idle
        }
    }

    /// ヘッダーに出す「東京都千代田区」のような表記。ピン選択中でも、これは常に実際のGPS現在地を指す。
    private var currentLocationName: String? {
        guard let municipality = viewModel.currentVisit?.municipality else { return nil }
        return "\(municipality.prefectureName)\(municipality.municipalityName)"
    }

    /// この都道府県が(市区町村の記録・都道府県単独の記録のどちらの意味でも)まだ一度も記録されていないか。
    /// 記録済みの市区町村があればその都道府県も既に記録済みなので、再訪問(isCurrentPlaceVisited)のときは必ずfalseになる。
    private var isFirstPrefectureVisit: Bool {
        guard let code = viewModel.currentVisit?.municipality.prefectureCode else { return false }
        let hasMunicipalityRecord = savedPlaces.contains { $0.municipality?.prefectureCode == code }
        let hasExplicitRecord = visitedPrefectures.contains { $0.code == code }
        return !hasMunicipalityRecord && !hasExplicitRecord
    }

    private var compactSheetHeight: CGFloat {
        if viewModel.statusText != nil { return Self.locatingCompactHeight }
        if viewModel.errorMessage != nil { return Self.errorCompactHeight }
        return Self.recordsCompactHeight
    }

    /// ピン、または現在地バッジから詳細を開いているか。どちらも「都道府県 → 詳細」までpathを積んで中段で見せる。
    private var isShowingDetailRoute: Bool {
        selectedPlace != nil || !sheetPath.isEmpty
    }

    /// 詳細表示中だけ中段を持つ。未選択時は、折りたたみ(旅の記録の1行)と全画面の2段だけにする。
    private var sheetDetents: Set<PresentationDetent> {
        isShowingDetailRoute
            ? [.height(compactSheetHeight), .medium, .large]
            : [.height(compactSheetHeight), .large]
    }

    private var backgroundInteractionDetent: PresentationDetent {
        isShowingDetailRoute ? .medium : .height(compactSheetHeight)
    }

    /// シートに隠れる分。詳細表示中は中段まで上がるので地図の半分を空ける。
    /// 常駐シートを出していない間(「日本」の儀式が済むまで)は地図を全面に使う。
    private var mapBottomInset: CGFloat {
        guard isSheetPresented else { return 0 }
        if isShowingDetailRoute { return mapHeight / 2 }
        return compactSheetHeight
    }

    var body: some View {
        let municipality = selectedPlace?.municipality ?? viewModel.currentVisit?.municipality
        let prefecture = summary.prefectures.first { $0.code == municipality?.prefectureCode }

        mapLayer(prefecture: prefecture, summary: summary)
            // 節目(25/50/75/100%)達成はただの初訪問より重みのある触覚にして、報酬の違いを体で伝える。
            // 単なる再訪問の更新は達成ではないため、「押した操作が届いた」程度の軽い触覚に留める。
            .sensoryFeedback(trigger: viewModel.successFeedback) { _, _ in
                switch viewModel.result?.kind {
                case .milestone: return .levelChange
                case .firstVisit: return .success
                case .update: return .impact(weight: .light)
                case nil: return nil
                }
            }
            // 「日本」「都道府県」の記録は、市区町村の節目と同じくアプリ内で最も重い達成として扱う。
            // SensoryFeedbackの標準にはこれより強い「達成」の触覚が無く、Core Hapticsで独自パターンを
            // 作るほどの差ではないため、節目と同じ.levelChangeにそろえる。
            // 日本はフラグがfalse→trueになった時(記録ボタンを押した時)だけ鳴らす。
            .sensoryFeedback(.levelChange, trigger: hasRecordedJapan) { _, newValue in newValue }
            .sensoryFeedback(.levelChange, trigger: prefectureRecordedFeedback)
            .sensoryFeedback(.error, trigger: viewModel.errorFeedback)
            .sensoryFeedback(.selection, trigger: selectedPlaceID) { _, newValue in newValue != nil }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.successFeedback)
            .sheet(isPresented: $isSheetPresented) {
                sheetContent()
            }
            // 「日本」の儀式だけは常駐シートより先に出るため、常駐シートの内側ではなくここに付ける。
            // 内側に付けると、儀式を見せるためだけに中身のない常駐シートを先に出す必要が生まれ、
            // それが「何も書かれていない空のシート」として見えてしまう。
            .sheet(isPresented: $isJapanIntroPresented) {
                JapanFirstVisitSheet(confirm: confirmJapanIntro)
                    // 実測して追従させると、表示アニメーション中の高さ補正と画像到着時の伸長でシートが
                    // 2回動き、そのたびに地図を含むMapScreen全体が再評価されて表示が重くなるため固定にする。
                    .presentationDetents([.height(JapanFirstVisitSheet.presentationHeight)])
                    .presentationBackground(Color.red.opacity(0.12))
                    // ボタン(confirm)以外では閉じられないようにする。
                    .interactiveDismissDisabled()
            }
            .onChange(of: selectedPlaceID) { _, _ in handleSelectionChange() }
            .onChange(of: isActive, initial: true) { _, isActive in
                // 「日本」の儀式が済むまでは常駐シート自体を出さない。儀式より先に出すと、
                // 中身が空のままのシートだけが画面下に残ってしまう。
                isSheetPresented = isActive && hasRecordedJapan
            }
            .onChange(of: sheetDetent) { _, detent in handleDetentChange(detent) }
            .onChange(of: compactSheetHeight) { _, height in handleCompactHeightChange(height) }
            .onChange(of: isSheetExpanded) { _, isExpanded in handleExpansionChange(isExpanded) }
            .onChange(of: summaryInputCounts, initial: true) { _, _ in refreshSummary() }
            .onChange(of: viewModel.currentVisit?.municipality.prefectureCode) { _, _ in
                handlePrefectureVisitChange()
            }
            .onChange(of: viewModel.currentVisit?.municipality.code) { _, _ in
                handleMunicipalityVisitChange()
            }
            // 再記録の「更新済み」→吹き出し→消える、の段階を1本のタスクで進める。確認が置き換わった(idが変わった)・
            // 途中で取り消された(nilになった)時は、このタスクごとキャンセルされて古い段階を進めない。
            .task(id: rerecordConfirmation?.id) {
                guard rerecordConfirmation != nil else { return }
                do {
                    try await Task.sleep(for: Self.rerecordCalloutDelay)
                    rerecordConfirmation?.stage = .showingCallout
                    try await Task.sleep(for: Self.rerecordCalloutDuration)
                    withAnimation(.easeOut(duration: Self.rerecordDismissDuration)) {
                        rerecordConfirmation?.stage = .dismissing
                    }
                    try await Task.sleep(for: .seconds(Self.rerecordDismissDuration))
                    rerecordConfirmation = nil
                } catch {
                    // Task.sleepが投げるのはキャンセルだけ。キャンセルした側(取り消し・置き換え)が状態を
                    // 決め直しているので、ここで続きの段階を進めたり状態を触ったりしない。
                    return
                }
            }
            .onChange(of: viewModel.successFeedback) { _, _ in
                guard celebratesInDedicatedSheet else { return }
                // 記録前の誘い(MunicipalityFirstVisitSheet)を閉じた直後に保存が完了するケースがあるため、
                // 直前のシートのdismissアニメーションと重ならないよう一呼吸置く(重なるとUIKit側で
                // 提示が正しく反映されないことがある)。
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    isMunicipalityCelebrationPresented = true
                }
            }
            .task(id: InitialLocationTrigger(isActive: isActive, municipalityCount: municipalities.count)) {
                guard isActive, !municipalities.isEmpty, viewModel.currentVisit == nil else { return }
                // シート提示アニメーションと、位置情報が未確定の場合に走るOS標準の許可ダイアログが
                // 同時に出ると見た目が競合するため、他の儀式シート遷移と同じ350msだけ間を置く。
                try? await Task.sleep(for: .milliseconds(350))
                await viewModel.refresh(municipalities: municipalities)
                // idが変わって走り直す場合は、新しい方の実行に儀式の提示を任せる。
                guard !Task.isCancelled else { return }
                guard let location = viewModel.currentLocation else {
                    // 許可されなかった・取得に失敗した場合も、儀式を出さないと常駐シートが出ないまま残るため提示する。
                    presentJapanIntroIfNeeded()
                    return
                }
                // 「日本」の儀式は、現在地へ地図を動かし終えてから出す。先に地図で自分の居場所を見せてから
                // 迎えることで、「今いるこの場所から旅が始まる」ことが伝わるようにする。
                // 位置の取得(許可ダイアログへの応答を含む)を待ってから出すので、ダイアログとも競合しない。
                waitForMapToSettleBeforeJapanIntro(at: location.coordinate)
                focusMap(on: location.coordinate)
            }
            .onDisappear { actionTask?.cancel() }
    }

    private func mapLayer(prefecture: PrefectureExploration?, summary: ExplorationSummary) -> some View {
        Map(position: $cameraPosition, selection: $selectedPlaceID) {
            UserAnnotation()
            ForEach(savedPlaces) { place in
                Marker(place.displayName, systemImage: "checkmark", coordinate: place.coordinate)
                    .tint(selectedPlaceID == place.persistentModelID ? .teal : .orange)
                    .tag(place.persistentModelID)
            }
            // Markerとは別に、再記録した場所の上に吹き出しを重ねる。Marker自体の見た目は変えない。
            // 選択用のtagを付けないので、地図の選択(selectedPlaceID)には関わらない。
            if let confirmation = rerecordConfirmation, confirmation.stage != .updated,
               let place = savedPlaces.first(where: { $0.persistentModelID == confirmation.placeID }) {
                Annotation(coordinate: place.coordinate, anchor: .bottom) {
                    MapRerecordCallout(
                        placeName: confirmation.placeName,
                        isDismissing: confirmation.stage == .dismissing
                    )
                } label: {
                    EmptyView()
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            handleCameraSettled(at: context.region.center)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            mapHeight = height
        }
        // シートに隠れる分をセーフエリアから除き、法的表示とカメラの中心をシートの上に収める。
        .safeAreaPadding(.bottom, mapBottomInset)
        // MapKit標準のコンパス/スケールはセーフエリアを避けて自動配置されるため、
        // ヘッダーの実測高さ分だけ上のセーフエリアも広げて、両者が重ならないようにする。
        .safeAreaPadding(.top, headerOverlayHeight)
        .overlay(alignment: .top) {
            // safeAreaInsetだとカメラの表示枠まで縮むため、overlayで地図の上に重ねるだけにする。
            VStack(alignment: .trailing, spacing: 4) {
                MapProgressHeader(
                    prefecture: prefecture,
                    summary: summary,
                    showPrefecture: showPrefectureProgress,
                    showNationwide: showNationwideProgress
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                // 現在地バッジと現在地へ戻るボタンを同じ行に同居させ、ボタンの位置をヘッダー直下のまま動かさない。
                ZStack(alignment: .trailing) {
                    if let currentLocationName {
                        MapCurrentLocationBadge(name: currentLocationName, onTap: handleCurrentLocationBadgeTap)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Button("現在地へ戻る", systemImage: "location.fill") {
                        selectedPlaceID = nil
                        refreshLocation()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: Circle())
                    .disabled(viewModel.isBusy)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                headerOverlayHeight = height
            }
        }
    }

    private func handleSelectionChange() {
        if let selectedPlace {
            // ピンを選ぶと地図がそのピンへ動いて再記録の場所から離れるため、吹き出しは待たずに消す。
            rerecordConfirmation = nil
            focusMap(on: selectedPlace.coordinate)
            // 展開済みかどうかに関わらず、ここでpathを確定させる(展開側では計算し直さない)。
            sheetPath = expandedRoutes(for: selectedPlace)
            sheetDetent = .medium
        } else if isSheetExpanded {
            // ピン以外の場所をタップして選択が外れたら、折りたたんで現在地カードへ戻す。
            sheetDetent = .height(compactSheetHeight)
        }
    }

    /// ヘッダー下の現在地バッジをタップしたら、選択中のピンを解除して現在地自身の詳細を見せる。
    private func handleCurrentLocationBadgeTap() {
        guard let municipality = viewModel.currentVisit?.municipality else { return }
        if let location = viewModel.currentLocation {
            focusMap(on: location.coordinate)
        }
        showMunicipalityDetail(municipality, detent: .medium)
    }

    /// ヘッダーの市区町村ページをタップしたら、表示中の都道府県の市区町村踏破率を開く。
    /// 旅の記録(都道府県一覧)の階層に積むので、シート内の戻る操作でそのまま旅の記録まで遡れる。
    ///
    /// `showMunicipalityDetail`と違い、ピンの選択は解除しない。ヘッダーの都道府県は選択中のピンに
    /// 追従しているため、解除するとヘッダーだけ現在地の都道府県に戻って開いた一覧と食い違ううえ、
    /// 選択解除を受けた`handleSelectionChange`が展開中のシートを折りたたんでしまうため。
    /// 選択はシートを折りたたんだ時に`handleExpansionChange`で解除される。
    private func showPrefectureProgress(_ prefecture: PrefectureExploration) {
        sheetPath = [.prefecture(code: prefecture.code, name: prefecture.name)]
        sheetDetent = .large
    }

    /// ヘッダーの全国ページをタップしたら、旅の記録(都道府県の踏破率)そのものを開く。
    /// ピンの選択を解除しない理由は`showPrefectureProgress`と同じ。
    private func showNationwideProgress() {
        sheetPath = []
        sheetDetent = .large
    }

    /// 市区町村詳細を、都道府県一覧(旅の記録)のナビゲーション階層に乗せて開く。現在地バッジ・
    /// 記録儀式シートの「みどころを見る」など、どこから開いても同じ階層(詳細→都道府県一覧→
    /// 旅の記録)に合流させ、その階層をそのまま遡って戻れるようにする(孤立した画面にしない)。
    private func showMunicipalityDetail(_ municipality: Municipality, detent: PresentationDetent) {
        selectedPlaceID = nil
        sheetPath = [
            .prefecture(code: municipality.prefectureCode, name: municipality.prefectureName),
            .currentMunicipalityDetail(municipality),
        ]
        sheetDetent = detent
    }

    private func handleDetentChange(_ detent: PresentationDetent) {
        let expandedDetents: [PresentationDetent] = [.medium, .large]
        isSheetExpanded = expandedDetents.contains(detent)
    }

    /// 折りたたみ中に内容が変わって高さが変わったら、選択中のdetentも追従させる。
    private func handleCompactHeightChange(_ height: CGFloat) {
        if !isSheetExpanded {
            sheetDetent = .height(height)
        }
    }

    /// pathは常に呼び出し側(ピン選択・現在地バッジ・旅の記録リンク)が展開前に確定させるので、
    /// ここでは折りたたんだ時の後片付けだけ行う。
    private func handleExpansionChange(_ isExpanded: Bool) {
        guard !isExpanded else {
            // 広げると再記録ボタンが隠れ、「更新済み」の続きを見届けられないため、吹き出しごと待たずに消す。
            rerecordConfirmation = nil
            return
        }
        sheetPath = []
        selectedPlaceID = nil
        // ピン選択中・旅の記録展開中(「みどころを見る」からの遷移含む)は儀式シートの表示を
        // 見送っているため、現在地カードに戻った直後に改めて提示し直す。誘いシートを記録の
        // 唯一の入口にするには、見送った分をここで必ず回収する必要がある。
        handlePrefectureVisitChange()
        handleMunicipalityVisitChange()
    }

    private func sheetContent() -> some View {
        Group {
            if isSheetExpanded {
                expandedSheetContent
            } else {
                compactSheetContent
            }
        }
        .presentationDetents(sheetDetents, selection: $sheetDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: backgroundInteractionDetent))
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }

    private var expandedSheetContent: some View {
        NavigationStack(path: $sheetPath) {
            SavedPlacesScreen()
                .navigationDestination(for: MapSheetRoute.self) { route in
                    switch route {
                    case .prefecture(let code, let name):
                        PrefectureExplorationScreen(prefectureCode: code, name: name)
                    case .municipalityDetail(let place):
                        MunicipalityDetailScreen(municipality: place.municipality, fallbackName: place.address)
                    case .currentMunicipalityDetail(let municipality):
                        MunicipalityDetailScreen(municipality: municipality, fallbackName: municipality.municipalityName)
                    }
                }
        }
    }

    private var compactSheetContent: some View {
        MapCurrentPlaceCard(
            // 記録中・更新済みの間は、currentVisitの差し替えや@Queryへの反映のタイミングに左右されず
            // ボタン自体を残し、押したボタンの状態遷移を最後まで見届けられるようにする。
            isVisited: isCurrentPlaceVisited || rerecordButtonPhase != .idle,
            statusText: viewModel.statusText,
            errorMessage: viewModel.errorMessage,
            recordButtonPhase: rerecordButtonPhase,
            latestPlace: savedPlaces.first,
            save: handleRerecordTap,
            refresh: refreshLocation,
            showRecords: {
                sheetPath = []
                sheetDetent = .large
            }
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 2)
        // 既にシートを表示中なので、同じ画面(mapLayer側)に付けると2枚目の提示が無視される。
        // 表示中のシートの中身側に付けて、その上に重ねて出す。
        .sheet(isPresented: $isPrefectureIntroPresented) {
            PrefectureFirstVisitSheet(
                prefectureName: viewModel.currentVisit?.municipality.prefectureName ?? "",
                confirm: confirmPrefectureVisit
            )
            .measuredSheetHeight($prefectureIntroHeight)
            .presentationBackground(.cyan.opacity(0.15))
            // ボタン(confirm)以外では閉じられないようにする。ドラッグで動かせる見た目も紛らわしいので消す。
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $isMunicipalityInvitationPresented) {
            // measuredSheetHeightは`if let`などの分岐の内側ではなく、必ずシート内容の最上位(Group)に
            // 付ける。分岐の内側に付けると、初回の高さは反映されるが画像が届いた後の高さ更新が
            // 提示側に伝わらず、ボタンが見切れたままになる(定義箇所のコメント参照)。
            Group {
                if let municipality = viewModel.currentVisit?.municipality {
                    MunicipalityFirstVisitSheet(
                        mode: .invitation(municipality: municipality, save: {
                            isMunicipalityInvitationPresented = false
                            handleSaveTap()
                        }),
                        dismiss: { isMunicipalityInvitationPresented = false },
                        showDetail: {
                            isMunicipalityInvitationPresented = false
                            showMunicipalityDetail(municipality, detent: .large)
                        }
                    )
                }
            }
            .measuredSheetHeight($municipalityInvitationHeight)
            .presentationBackground(Color.teal.opacity(0.15))
            // 記録する/みどころを見る、以外では閉じられないようにする。この誘いシートが
            // 未訪問の場所を記録する唯一の入口なので、スワイプで取りこぼせないようにする。
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $isMunicipalityCelebrationPresented) {
            // 誘いシートと同じ理由で、measuredSheetHeightは`if let`の外(Group)に付ける。
            Group {
                if let result = viewModel.result {
                    MunicipalityFirstVisitSheet(
                        mode: .celebration(result: result, municipality: viewModel.currentVisit?.municipality),
                        dismiss: { isMunicipalityCelebrationPresented = false },
                        showDetail: {
                            isMunicipalityCelebrationPresented = false
                            if let municipality = viewModel.currentVisit?.municipality {
                                showMunicipalityDetail(municipality, detent: .large)
                            }
                        }
                    )
                }
            }
            .measuredSheetHeight($municipalityCelebrationHeight)
            .presentationBackground((viewModel.result?.milestone != nil ? Color.yellow : Color.teal).opacity(0.15))
        }
    }

    /// municipalities/savedPlaces/visitedPrefecturesのいずれかが変わった時だけsummaryを計算し直すための
    /// まとめたトリガー値。onChangeを3つ並べると型検査が重くなりすぎるため1つにまとめている。
    private var summaryInputCounts: [Int] {
        [municipalities.count, savedPlaces.count, visitedPrefectures.count]
    }

    private func refreshSummary() {
        summary = ExplorationProgressCalculator().summarize(
            models: municipalities, savedPlaces: savedPlaces, visitedPrefectures: visitedPrefectures
        )
    }

    private func expandedRoutes(for place: SavedPlace) -> [MapSheetRoute] {
        var routes: [MapSheetRoute] = []
        if let municipality = place.municipality {
            routes.append(.prefecture(code: municipality.prefectureCode, name: municipality.prefectureName))
        }
        routes.append(.municipalityDetail(place))
        return routes
    }

    private func refreshLocation() {
        guard !viewModel.isBusy else { return }
        // 取り直すと現在地そのものが変わりうるため、前の場所への「更新済み」を残さない。
        rerecordConfirmation = nil
        actionTask = Task {
            await viewModel.refresh(municipalities: municipalities)
            if let location = viewModel.currentLocation, selectedPlaceID == nil {
                focusMap(on: location.coordinate)
            }
        }
    }

    /// 誘いシート(MunicipalityFirstVisitSheet)の「記録する」。初めての都道府県なら、記録する前に特別感のある確認シートを挟む。
    private func handleSaveTap() {
        if isFirstPrefectureVisit {
            performAfterJapanIntro { isPrefectureIntroPresented = true }
        } else {
            performAfterJapanIntro { saveVisit(trigger: .firstVisitInvitation) }
        }
    }

    /// 常駐シートの「再記録」。`handleSaveTap`の前処理は再記録では常に素通りになるため挟まない。
    /// 常駐シートは「日本」の儀式を済ませた後にしか出ない(performAfterJapanIntroは即実行になる)うえ、
    /// このボタンは訪問済みの場所でしか出ず、その都道府県も必ず記録済み(isFirstPrefectureVisitがfalse)なため。
    private func handleRerecordTap() {
        saveVisit(trigger: .rerecordButton)
    }

    /// 現在地が初めての都道府県に変わったら、記録ボタンを待たずに真っ先にこのシートを見せる。
    /// ピン選択中や旅の記録を広げている最中は、そちらの表示を優先して割り込まない。
    private func handlePrefectureVisitChange() {
        guard !isSheetExpanded, selectedPlace == nil, isFirstPrefectureVisit else { return }
        performAfterJapanIntro { isPrefectureIntroPresented = true }
    }

    /// 現在地が初めての市区町村に変わったら、記録ボタンを待たずに誘いのシートを見せる。
    /// 都道府県ごと初めての場合は、先にそちらの儀式(handlePrefectureVisitChange)を優先し、
    /// ここでは割り込まない(confirmPrefectureVisit側で確認後に改めてこの誘いへ繋げる)。
    /// `viewModel.currentVisit`はrefresh中と誘いシート経路のsave中に一旦nilへ戻ってから再設定される
    /// (再記録のsaveでは保存前の値を残すが、失敗・中断した場合はnilになる)ため、そのnilへの
    /// 変化でも`municipality.code`のonChangeは発火する。nilの間は「未訪問」と誤判定してしまう
    /// (isCurrentPlaceVisitedがfalseを返す)ため、currentVisitがある時だけ動くよう明示的に絞る。
    private func handleMunicipalityVisitChange() {
        guard !isSheetExpanded, selectedPlace == nil, viewModel.currentVisit != nil,
              !isCurrentPlaceVisited, !isFirstPrefectureVisit
        else { return }
        performAfterJapanIntro { isMunicipalityInvitationPresented = true }
    }

    /// 「日本を記録する」儀式の初回提示。初回の現在地取得(許可ダイアログへの応答を含む)が終わった後にだけ
    /// 呼ぶこと。応答前に出すと、OS標準の許可ダイアログとこの儀式シートが競合して提示され、
    /// どちらも正しく表示されない(内側のシートが出ず、空のシートだけ残る)ことがある。
    private func presentJapanIntroIfNeeded() {
        guard isActive, !hasRecordedJapan, !isJapanIntroPresented else { return }
        Task {
            // 直前のシート提示アニメーション(またはOS標準の許可ダイアログ)と重ならないよう、
            // 他の儀式シート遷移と同じく一呼吸置く。
            try? await Task.sleep(for: .milliseconds(350))
            isJapanIntroPresented = true
        }
    }

    /// 地図が現在地へ移動し終えたら「日本」の儀式を出すよう待ち合わせる。移動完了は`handleCameraSettled`で
    /// 受け取るが、通知が来ない場合に備えて上限時間を過ぎたら待たずに出す。
    private func waitForMapToSettleBeforeJapanIntro(at coordinate: CLLocationCoordinate2D) {
        guard !hasRecordedJapan else { return }
        japanIntroCameraTarget = coordinate
        Task {
            try? await Task.sleep(for: Self.cameraSettleTimeout)
            guard japanIntroCameraTarget != nil else { return }
            japanIntroCameraTarget = nil
            presentJapanIntroIfNeeded()
        }
    }

    private func handleCameraSettled(at center: CLLocationCoordinate2D) {
        guard let target = japanIntroCameraTarget else { return }
        let distance = CLLocation(latitude: center.latitude, longitude: center.longitude)
            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
        // 現在地へ動かす前のカメラ(初期表示)が止まった通知は無視し、現在地に着いた時だけ扱う。
        guard distance <= Self.cameraArrivalTolerance else { return }
        japanIntroCameraTarget = nil
        Task {
            try? await Task.sleep(for: Self.mapSettleDelay)
            presentJapanIntroIfNeeded()
        }
    }

    /// 都道府県・市区町村どちらの初訪問儀式よりも先に、「日本」を記録する儀式を一度だけ挟む。
    /// 既に記録済みなら`action`をそのまま実行し、まだなら`action`を預けておく。日本の儀式そのものは
    /// ここでは出さず、初回の現在地取得と地図の移動が終わった時点で出す(その前に地図を見せるため)。
    private func performAfterJapanIntro(_ action: @escaping () -> Void) {
        guard !hasRecordedJapan else {
            action()
            return
        }
        pendingAfterJapanIntro = action
    }

    /// 日本の儀式を確定したら、フラグを立てて常駐シートを開き、割り込む前に本来起ころうとしていた処理を続行する。
    /// 割り込んだ処理が無く、現在地もまだ解決できていなければ(取得の失敗など)、ここで取り直す。
    private func confirmJapanIntro() {
        hasRecordedJapan = true
        isJapanIntroPresented = false
        let action = pendingAfterJapanIntro
        pendingAfterJapanIntro = nil
        Task {
            // 直前のシートのdismissアニメーションと重ならないよう、一呼吸置いてから常駐シートを出す。
            try? await Task.sleep(for: .milliseconds(350))
            isSheetPresented = true
            // 次の儀式シートは常駐シートの内側に付いているため、その提示が終わってから出す。
            // 現在地の解決も、始めると常駐シートの高さが変わるため同じく提示を待つ。
            try? await Task.sleep(for: .milliseconds(350))
            if let action {
                action()
            } else if viewModel.currentVisit == nil {
                refreshLocation()
            }
        }
    }

    /// 都道府県の記録と市区町村の記録は完全に独立している。ここでは都道府県だけを記録し、
    /// 現在地の市区町村自体は(この後改めて「この場所を記録する」を押すまで)保存しない。
    /// 都道府県ごと初めての場合、市区町村も必ず未訪問なので、確認直後にその誘いのシートへ繋げる。
    private func confirmPrefectureVisit() {
        isPrefectureIntroPresented = false
        guard let municipality = viewModel.currentVisit?.municipality else { return }
        let code = municipality.prefectureCode
        if !visitedPrefectures.contains(where: { $0.code == code }) {
            modelContext.insert(VisitedPrefecture(code: code, name: municipality.prefectureName))
            do {
                try modelContext.save()
                // 保存できた時だけ鳴らす。失敗して巻き戻した記録を「記録できた」と体で伝えないため。
                prefectureRecordedFeedback += 1
            } catch {
                modelContext.rollback()
            }
        }
        guard !isCurrentPlaceVisited else { return }
        Task {
            // 直前のシートのdismissアニメーションと重ならないよう、一呼吸置いてから次の儀式に繋げる。
            try? await Task.sleep(for: .milliseconds(350))
            isMunicipalityInvitationPresented = true
        }
    }

    private func saveVisit(trigger: MapVisitSaveTrigger) {
        guard !viewModel.isBusy else { return }
        actionTask = Task {
            let result = await viewModel.save(municipalities: municipalities, context: modelContext, trigger: trigger)
            // saveの完了(operationが.idleに戻る)と同じMainActorの処理の続きで判定する。onChangeで受けると
            // その間に描画が1回挟まり、再記録ボタンが一瞬「再記録」に戻ってから「更新済み」になるため。
            if let result {
                handleSaveCompletion(result, trigger: trigger)
            }
            if let location = viewModel.currentLocation, selectedPlaceID == nil {
                focusMap(on: location.coordinate)
            }
        }
    }

    /// 保存完了時の見せ方を、完了した時点のシート・ピン選択の状態で決める。初訪問・節目(.none)は
    /// `successFeedback`のonChangeが儀式シートを出すので、ここでは何もしない。
    private func handleSaveCompletion(_ result: MapVisitResult, trigger: MapVisitSaveTrigger) {
        let feedback = MapVisitFeedbackPolicy().updateFeedback(
            for: result.kind,
            trigger: trigger,
            isSheetExpanded: isSheetExpanded,
            hasSelectedPlace: selectedPlace != nil
        )
        switch feedback {
        case .none:
            return
        case .inlineConfirmation:
            // 更新なので記録は既に存在し、同じSavedPlaceが上書きされている(persistentModelIDは変わらない)。
            // 見つからないことは想定していないが、その場合はボタンを「再記録」へ直接戻し、読み上げだけ行う。
            if let code = viewModel.currentVisit?.municipality.code,
               let place = savedPlaces.first(where: { $0.municipality?.code == code }) {
                rerecordConfirmation = MapRerecordConfirmation(
                    placeID: place.persistentModelID, placeName: place.displayName
                )
            }
            announceVisitUpdate(result)
        case .announcementOnly:
            announceVisitUpdate(result)
        }
    }

    /// 更新は画面の表示だけでは(シートを広げている等で)目に入らないことがあるため、完了時に1回だけ読み上げる。
    private func announceVisitUpdate(_ result: MapVisitResult) {
        AccessibilityNotification.Announcement("\(result.municipalityName)の訪問記録を更新しました").post()
    }

    private func focusMap(on coordinate: CLLocationCoordinate2D) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: Self.focusAnimationDuration)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate, latitudinalMeters: Self.focusSpanMeters, longitudinalMeters: Self.focusSpanMeters
            ))
        }
    }
}

/// 初回の現在地取得を始め直すきっかけ。画面が有効になった時(チュートリアルを閉じた等)と、
/// マスタが読み込まれて市区町村が揃った時のどちらでも走らせる。
private struct InitialLocationTrigger: Equatable {
    let isActive: Bool
    let municipalityCount: Int
}

/// 再記録の完了を見せている間の状態。段階はMapScreenの`.task(id:)`が時間の経過で進める。
private struct MapRerecordConfirmation {
    enum Stage {
        /// ボタンだけ「更新済み」。地図が再記録した場所へ動き終わるのを待っている。
        case updated
        /// ボタンは「更新済み」のまま、ピンの上に吹き出しを出している。
        case showingCallout
        /// ボタンは「再記録」に戻し、吹き出しを透明にしている。フェードが終わったら確認ごと取り除く。
        case dismissing
    }

    /// 連続して再記録した時に、前回分の段階を進めるタスクを確実に打ち切るための識別子(.task(id:)に使う)。
    let id = UUID()
    let placeID: PersistentIdentifier
    let placeName: String
    var stage: Stage = .updated
}

/// 展開シート内の遷移先。折りたたみ中の選択状態から、広げたときに積み直すための値。
private enum MapSheetRoute: Hashable {
    case prefecture(code: String, name: String)
    case municipalityDetail(SavedPlace)
    case currentMunicipalityDetail(Municipality)
}

/// Wikipedia画像のように非同期で後から差し込まれる要素があるシートを、実測した高さに追従させる。
///
/// **必ずシート内容の最上位に付けること。** `if let` などの条件分岐の中身にだけ付けると、初回の
/// 高さは反映されても、分岐後の再計測が`.presentationDetents`側に伝わらなくなり、画像到着後も
/// シートが育たずボタンが見切れたままになる(公式ドキュメントに記載のない挙動)。
private struct MeasuredSheetHeight: ViewModifier {
    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .presentationDetents([.height(height)])
    }
}

private extension View {
    func measuredSheetHeight(_ height: Binding<CGFloat>) -> some View {
        modifier(MeasuredSheetHeight(height: height))
    }
}

#Preview {
    MapScreen().modelContainer(for: [SavedPlace.self, Municipality.self, VisitedPrefecture.self], inMemory: true)
}
