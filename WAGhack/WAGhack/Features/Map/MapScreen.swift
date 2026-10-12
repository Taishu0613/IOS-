import MapKit
import SwiftData
import SwiftUI

struct MapScreen: View {
    /// マスタ準備中はシートを出さない。出してしまうとContentViewの読み込みオーバーレイをシートが覆う。
    var isMasterReady = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @Query(sort: \Municipality.code) private var municipalities: [Municipality]
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
    @State private var sheetDetent: PresentationDetent = .height(Self.visitedCompactHeight)
    /// シートが中段以上に広がっているか。折りたたみ中は現在地カード、広げると旅の記録のスタックに切り替わる。
    @State private var isSheetExpanded = false
    @State private var sheetPath: [MapSheetRoute] = []
    @State private var isPrefectureIntroPresented = false
    @State private var isMunicipalityInvitationPresented = false
    @State private var isMunicipalityCelebrationPresented = false
    /// municipalities/savedPlacesが実際に変わった時だけ計算し直す。ピン選択などのUI操作のたびに
    /// 全市区町村(1,898件)を集計し直すと体感できるラグになるため、bodyでは計算しない。
    @State private var summary = ExplorationSummary(prefectures: [], eligibleCodes: [])

    // 折りたたみ時のシート高さ。内容の行数が状態で変わるため、状態ごとに固定値を持つ。
    private static let visitedCompactHeight: CGFloat = 110
    private static let unvisitedCompactHeight: CGFloat = 235
    private static let locatingCompactHeight: CGFloat = 140
    private static let errorCompactHeight: CGFloat = 235
    private static let resultExtraHeight: CGFloat = 40
    /// 地図だけ見たい時にさらに畳める最小状態。「記録した一覧を確認する」の行だけを残す。
    private static let minimizedHeight: CGFloat = 64

    private var selectedPlace: SavedPlace? {
        savedPlaces.first { $0.persistentModelID == selectedPlaceID }
    }

    private var isCurrentPlaceVisited: Bool {
        guard let code = viewModel.currentVisit?.municipality.code else { return false }
        return savedPlaces.contains { $0.municipality?.code == code }
    }

    /// 初めての市区町村・節目の達成は`MunicipalityFirstVisitSheet`という専用の儀式で見せるため、
    /// それ以外(単なる再訪問の更新)だけをカード内の控えめなバナーに残す。
    private var celebratesInDedicatedSheet: Bool {
        guard let result = viewModel.result else { return false }
        return result.isFirstVisit || result.milestone != nil
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
        let base = isCurrentPlaceVisited ? Self.visitedCompactHeight : Self.unvisitedCompactHeight
        return base + (viewModel.result == nil ? 0 : Self.resultExtraHeight)
    }

    /// ピン、または現在地バッジから詳細を開いているか。どちらも「都道府県 → 詳細」までpathを積んで中段で見せる。
    private var isShowingDetailRoute: Bool {
        selectedPlace != nil || !sheetPath.isEmpty
    }

    /// ユーザーがドラッグで最小状態まで畳んだか。市区町村未選択の時だけ選べる。
    private var isMinimized: Bool {
        sheetDetent == .height(Self.minimizedHeight)
    }

    /// 詳細表示中だけ中段を持つ。未選択時は、通常の折りたたみに加えて最小状態にも畳める。
    private var sheetDetents: Set<PresentationDetent> {
        isShowingDetailRoute
            ? [.height(compactSheetHeight), .medium, .large]
            : [.height(Self.minimizedHeight), .height(compactSheetHeight), .large]
    }

    private var backgroundInteractionDetent: PresentationDetent {
        isShowingDetailRoute ? .medium : .height(compactSheetHeight)
    }

    /// シートに隠れる分。詳細表示中は中段まで上がるので地図の半分を空ける。
    private var mapBottomInset: CGFloat {
        if isShowingDetailRoute { return mapHeight / 2 }
        return isMinimized ? Self.minimizedHeight : compactSheetHeight
    }

    var body: some View {
        let municipality = selectedPlace?.municipality ?? viewModel.currentVisit?.municipality
        let prefecture = summary.prefectures.first { $0.code == municipality?.prefectureCode }

        mapLayer(prefecture: prefecture, summary: summary)
            // 節目(25/50/75/100%)達成はただの初訪問より重みのある触覚にして、報酬の違いを体で伝える。
            .sensoryFeedback(trigger: viewModel.successFeedback) { _, _ in
                viewModel.result?.milestone != nil ? .levelChange : .success
            }
            .sensoryFeedback(.error, trigger: viewModel.errorFeedback)
            .sensoryFeedback(.selection, trigger: selectedPlaceID) { _, newValue in newValue != nil }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.successFeedback)
            .sheet(isPresented: $isSheetPresented) {
                sheetContent()
            }
            .onChange(of: selectedPlaceID) { _, _ in handleSelectionChange() }
            .onChange(of: isMasterReady, initial: true) { _, isReady in isSheetPresented = isReady }
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
            .task(id: municipalities.count) {
                guard !municipalities.isEmpty, viewModel.currentVisit == nil else { return }
                await viewModel.refresh(municipalities: municipalities)
                if let location = viewModel.currentLocation { focusMap(on: location.coordinate) }
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
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
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
                MapProgressHeader(prefecture: prefecture, summary: summary)
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
    /// ただし最小状態まで畳んでいる間は、ユーザーの選択を優先して追従させない。
    private func handleCompactHeightChange(_ height: CGFloat) {
        if !isSheetExpanded, !isMinimized {
            sheetDetent = .height(height)
        }
    }

    /// pathは常に呼び出し側(ピン選択・現在地バッジ・旅の記録リンク)が展開前に確定させるので、
    /// ここでは折りたたんだ時の後片付けだけ行う。
    private func handleExpansionChange(_ isExpanded: Bool) {
        guard !isExpanded else { return }
        sheetPath = []
        selectedPlaceID = nil
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
        Group {
            if isMinimized {
                // 地図だけ見たい時の最小状態。「旅の記録」の見出しだけを残す。
                MapRecordsLink(action: {
                    sheetPath = []
                    sheetDetent = .large
                })
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            } else {
                MapCurrentPlaceCard(
                    isVisited: isCurrentPlaceVisited,
                    statusText: viewModel.statusText,
                    errorMessage: viewModel.errorMessage,
                    // 初訪問・節目は専用シート(MunicipalityFirstVisitSheet)で祝うので、
                    // カード内のバナーには単なる再訪問の更新だけを残す。
                    result: celebratesInDedicatedSheet ? nil : viewModel.result,
                    summary: summary,
                    save: handleSaveTap,
                    refresh: refreshLocation,
                    showRecords: {
                        sheetPath = []
                        sheetDetent = .large
                    }
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 2)
            }
        }
        // 既にシートを表示中なので、同じ画面(mapLayer側)に付けると2枚目の提示が無視される。
        // 表示中のシートの中身側に付けて、その上に重ねて出す。最小状態でも初めての都道府県の
        // お知らせは受け取れるよう、分岐の外に付ける。
        .sheet(isPresented: $isPrefectureIntroPresented) {
            PrefectureFirstVisitSheet(
                prefectureName: viewModel.currentVisit?.municipality.prefectureName ?? "",
                confirm: confirmPrefectureVisit
            )
            .presentationDetents([.height(340)])
            .presentationBackground(.cyan.opacity(0.15))
            // ボタン(confirm)以外では閉じられないようにする。ドラッグで動かせる見た目も紛らわしいので消す。
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $isMunicipalityInvitationPresented) {
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
                .presentationDetents([.height(360)])
                .presentationBackground(Color.teal.opacity(0.15))
            }
        }
        .sheet(isPresented: $isMunicipalityCelebrationPresented) {
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
                .presentationDetents([.height(360)])
                .presentationBackground((result.milestone != nil ? Color.yellow : Color.teal).opacity(0.15))
            }
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
        actionTask = Task {
            await viewModel.refresh(municipalities: municipalities)
            if let location = viewModel.currentLocation, selectedPlaceID == nil {
                focusMap(on: location.coordinate)
            }
        }
    }

    /// 初めての都道府県なら、記録する前に特別感のある確認シートを挟む。
    private func handleSaveTap() {
        if isFirstPrefectureVisit {
            isPrefectureIntroPresented = true
        } else {
            saveVisit()
        }
    }

    /// 現在地が初めての都道府県に変わったら、記録ボタンを待たずに真っ先にこのシートを見せる。
    /// ピン選択中や旅の記録を広げている最中は、そちらの表示を優先して割り込まない。
    private func handlePrefectureVisitChange() {
        guard !isSheetExpanded, selectedPlace == nil, isFirstPrefectureVisit else { return }
        isPrefectureIntroPresented = true
    }

    /// 現在地が初めての市区町村に変わったら、記録ボタンを待たずに誘いのシートを見せる。
    /// 都道府県ごと初めての場合は、先にそちらの儀式(handlePrefectureVisitChange)を優先し、
    /// ここでは割り込まない(confirmPrefectureVisit側で確認後に改めてこの誘いへ繋げる)。
    /// `viewModel.currentVisit`はrefresh/save中に一旦nilへ戻ってから再設定されるため、そのnilへの
    /// 変化でも`municipality.code`のonChangeは発火する。nilの間は「未訪問」と誤判定してしまう
    /// (isCurrentPlaceVisitedがfalseを返す)ため、currentVisitがある時だけ動くよう明示的に絞る。
    private func handleMunicipalityVisitChange() {
        guard !isSheetExpanded, selectedPlace == nil, viewModel.currentVisit != nil,
              !isCurrentPlaceVisited, !isFirstPrefectureVisit
        else { return }
        isMunicipalityInvitationPresented = true
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

    private func saveVisit() {
        guard !viewModel.isBusy else { return }
        actionTask = Task {
            await viewModel.save(municipalities: municipalities, context: modelContext)
            if let location = viewModel.currentLocation, selectedPlaceID == nil {
                focusMap(on: location.coordinate)
            }
        }
    }

    private func focusMap(on coordinate: CLLocationCoordinate2D) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate, latitudinalMeters: 1_200, longitudinalMeters: 1_200
            ))
        }
    }
}

/// 展開シート内の遷移先。折りたたみ中の選択状態から、広げたときに積み直すための値。
private enum MapSheetRoute: Hashable {
    case prefecture(code: String, name: String)
    case municipalityDetail(SavedPlace)
    case currentMunicipalityDetail(Municipality)
}

#Preview {
    MapScreen().modelContainer(for: [SavedPlace.self, Municipality.self, VisitedPrefecture.self], inMemory: true)
}
