import os
import SwiftUI

/// 踏破率ヘッダーのページ。地図の塗り分け(市区町村のパズル / 都道府県の制覇率)もこれに連動するため、
/// ヘッダー自身ではなく`MapScreen`が所有する。
///
/// `@AppStorage`に保存するためString型のrawValueを持つ。rawValueを変えると保存済みの選択が失われるので変えないこと。
enum MapProgressPage: String, CaseIterable {
    /// 現在地の都道府県内の市区町村踏破率。地図は市区町村のピースで塗る。
    case municipalities
    /// 全国の都道府県制覇率。地図は都道府県ごとに市区町村踏破率の濃さで塗る。
    case prefectures

    /// ヘッダー上部のセグメントに出す名前。
    var title: String {
        switch self {
        case .municipalities: "市区町村"
        case .prefectures: "都道府県"
        }
    }
}

struct MapProgressHeader: View {
    let prefecture: PrefectureExploration?
    let summary: ExplorationSummary
    /// 市区町村ページに添える、現在地の都道府県を市区町村に分けた地図。読み込み前はnil(枠だけ空けておく)。
    let prefectureMap: SilhouetteMap?
    /// 全国ページに添える日本地図。読み込み前はnil。
    let japanMap: SilhouetteMap?
    /// 切り替えの主な入口はカード上部のセグメント。横スワイプとページドットだけでは、
    /// 切り替えられること自体と、地図の塗り分けまで変わることが伝わらなかったため。
    /// TabView(.page)のスワイプも、慣れた人向けの近道として残している。
    @Binding var page: MapProgressPage
    /// 市区町村ページ(その都道府県内の市区町村踏破率)をタップした時。
    let showPrefecture: (PrefectureExploration) -> Void
    /// 全国ページ(都道府県の踏破率)をタップした時。
    let showNationwide: () -> Void

    private var canToggle: Bool { prefecture != nil }
    /// 日本地図で塗る都道府県。
    private var visitedPrefectureCodes: Set<String> {
        Set(summary.visitedPrefectures.map(\.code))
    }
    /// 都道府県の地図・日本地図を描く枠の一辺。カード(96pt)から上下の余白12ptずつを引いた72ptに、ゆとりを持って収まる大きさ。
    private static let silhouetteSize = SilhouetteMapStore.headerMapSize
    /// カードの高さのみを固定し、セグメントの分は含めない(セグメントはカードの外に別途置く)。
    private static let cardHeight: CGFloat = 96

    var body: some View {
        VStack(spacing: 6) {
            pagePicker
            TabView(selection: $page) {
                if let prefecture {
                    pageView(
                        title: "\(prefecture.name)  \(prefecture.progress.visited) / \(prefecture.progress.total) 市区町村",
                        progress: prefecture.progress,
                        unit: "市区町村",
                        tint: nil,
                        accessibilityHint: "タップで\(prefecture.name)の市区町村制覇率を開きます",
                        action: { showPrefecture(prefecture) }
                    ) {
                        if let prefectureMap {
                            // 塗りを踏破率の数字と一致させるため、踏破率と同じ訪問済みコードを使う。
                            SilhouetteMapView(map: prefectureMap, visitedCodes: prefecture.visitedCodes)
                        }
                    }
                    .tag(MapProgressPage.municipalities)
                }
                pageView(
                    title: "都道府県 \(summary.prefectureProgress.visited) / \(summary.prefectureProgress.total) ",
                    progress: summary.prefectureProgress,
                    unit: "都道府県",
                    tint: .cyan,
                    accessibilityHint: "タップで都道府県の制覇率を開きます",
                    action: showNationwide
                ) {
                    if let japanMap {
                        SilhouetteMapView(map: japanMap, visitedCodes: visitedPrefectureCodes)
                    }
                }
                .tag(MapProgressPage.prefectures)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: Self.cardHeight)
        }
        // 現在地の都道府県が不明な間に全国ページへ寄せるのは`MapScreen`側で行う(ここでpageへ書き込むと、
        // 起動直後に保存済みの選択が都道府県で上書きされてしまうため)。
        .sensoryFeedback(.selection, trigger: page)
    }

    /// 踏破率の単位(=地図の塗り分け)を選ぶセグメント。
    /// 現在地の都道府県が不明で市区町村ページが無い間も、ヘッダーの高さが変わって地図が揺れないよう
    /// 隠さずに無効化だけする。
    private var pagePicker: some View {
        Picker("踏破率の単位", selection: $page) {
            ForEach(MapProgressPage.allCases, id: \.self) { page in
                Text(page.title).tag(page)
            }
        }
        .pickerStyle(.segmented)
        // 標準の溝はほぼ透明で、地図の文字と重なって未選択側が読めないため、カードと同じガラスを敷く。
        .glassEffect(.regular, in: Capsule())
        .disabled(!canToggle)
        // カードと左右の端をそろえる(カードはページ間の隙間として左右6ptずつ内側に入っている)。
        .padding(.horizontal, 6)
    }

    private func pageView<Silhouette: View>(
        title: String,
        progress: ExplorationCount,
        unit: String,
        tint: Color?,
        accessibilityHint: String,
        action: @escaping () -> Void,
        @ViewBuilder silhouette: () -> Silhouette
    ) -> some View {
        // onTapGestureではなくButtonにして、VoiceOverからも「ボタン」として開けるようにする。
        // Buttonはドラッグを取り合わないので、TabViewの横スワイプによるページ切り替えはそのまま効く。
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        // 右に形を置いた分だけ横幅が狭いので、長い県名でも2行にならず縮めて収める(カードの高さは固定のため)。
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    ProgressView(value: progress.fraction)
                        .tint(.teal)
                        .accessibilityLabel("\(unit)踏破率")
                        .accessibilityValue(progress.percentageText)
                    Text("\(progress.percentageText) · \(progress.nextGoalText(unit: unit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // 読み込み前も枠は確保しておき、形が現れたときに文字やバーの幅が変わって揺れないようにする。
                silhouette()
                    .frame(width: Self.silhouetteSize, height: Self.silhouetteSize)
                    .transition(.opacity)
            }
            .animation(.easeOut(duration: 0.25), value: prefectureMap != nil)
            .animation(.easeOut(duration: 0.25), value: japanMap != nil)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 都道府県制覇率(全国ページ)は市区町村ページと見分けがつくよう、ごく薄く水色にする。
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.22)) } ?? .regular, in: RoundedRectangle(cornerRadius: 18))
            // 文字の無い余白部分も含め、見えているカードの形全体を押せる範囲にする。
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
        // ページ間に隙間を作り、スライド中にカードの角がTabViewの端でクリップされて見切れるのを防ぐ。
        .padding(.horizontal, 6)
    }
}

/// 地図の上に浮かせる、現在地の「〇〇県〇〇市」ラベル。踏破率ヘッダーとは別の独立したピルとして置く。
/// タップで現在地の詳細シートを開く。
struct MapCurrentLocationBadge: View {
    let name: String
    /// 現在地の市区町村を記録済みか。見た目は変えず、読み上げだけで伝える。地図上では未記録の区域を
    /// 縁取りの脈打ち(`MapAreaEffectController`)で知らせているため、見えない人にも同じ情報を届ける。
    let isRecorded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label(name, systemImage: "location.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                // ヘッダーより控えめな存在にしたいので、regularより透過するultraThinMaterialにする。
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("現在地：\(name)")
        .accessibilityValue(isRecorded ? "" : "未記録")
        .accessibilityHint("タップで現在地の詳細を表示します")
    }
}

/// 記録した場所のピンを表示するか・隠すかを切り替える丸ボタン。
/// 見た目は隣の「現在地へ戻る」ボタンと揃える(44pt・Liquid Glassの円)。
/// 選択肢が2つしかないのでメニューにはせず、1タップで切り替える。アイコンは今の状態を表す。
struct MapPinVisibilityButton: View {
    @Binding var showsPins: Bool

    var body: some View {
        Button("記録のピン", systemImage: showsPins ? "mappin.and.ellipse" : "mappin.slash") {
            showsPins.toggle()
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .frame(width: 56, height: 56)
        .contentShape(Circle())
        .glassEffect(.regular, in: Circle())
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(showsPins ? "表示中" : "非表示")
        .sensoryFeedback(.selection, trigger: showsPins)
    }
}

/// 折りたたみシートの「現在地」カード。初めての場所を記録する入口は`MunicipalityFirstVisitSheet`
/// (誘いシート)だけに一本化しているため、ここでは常に旅の記録そのものの見出しを主役にする。
/// 未訪問時にこのカード自身から記録する手段は持たない(誘いシートが唯一の入口)。
/// みどころはここでは出さない(図鑑・詳細で見る)。
struct MapCurrentPlaceCard: View {
    let isVisited: Bool
    let statusText: String?
    let errorMessage: String?
    /// 再記録ボタンの見た目の段階。再記録の進行と結果はカードの行を増やさず、このボタンだけで伝える。
    let recordButtonPhase: MapRerecordButtonPhase
    /// 最も新しく記録した場所。まだ1件も記録が無ければnil。
    let latestPlace: SavedPlace?
    let save: () -> Void
    let refresh: () -> Void
    let showRecords: () -> Void

    var body: some View {
        Group {
            if let statusText {
                MapLocationStatusRow(status: .locating(statusText), retry: refresh)
            } else if let errorMessage {
                MapLocationStatusRow(status: .failed(errorMessage), retry: refresh)
            } else {
                MapRecordsSummaryRow(
                    latestPlace: latestPlace,
                    isVisited: isVisited,
                    recordButtonPhase: recordButtonPhase,
                    onRecord: save,
                    onExpand: showRecords
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 現在地の取得中・取得失敗を、「旅の記録」の1行(`MapRecordsSummaryRow`)と同じ形(アイコン+見出し+1行の補足
/// +右端のボタン)で見せる。折りたたみシートの高さを状態によらず一定に保ち、切り替わりで地図が揺れないようにするため、
/// 行を増やす表示はしない。1行に収まらないエラー文は、補足の部分をタップするとポップオーバーで全文を読める。
private struct MapLocationStatusRow: View {
    enum Status {
        case locating(String)
        case failed(String)
    }

    let status: Status
    let retry: () -> Void

    @State private var isShowingFullMessage = false

    var body: some View {
        HStack(spacing: 12) {
            switch status {
            case .locating(let message):
                HStack(spacing: 12) {
                    icon(systemName: "location.fill", color: .teal, isPulsing: true)
                    texts(title: "現在地", message: message)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            case .failed(let message):
                Button {
                    isShowingFullMessage = true
                } label: {
                    HStack(spacing: 12) {
                        icon(systemName: "location.slash.fill", color: .orange, isPulsing: false)
                        texts(title: "現在地を取得できません", message: message)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("タップで詳細を表示します")
                // シートの中でも全画面のシートに化けず、文言の近くに小さく出す。
                .popover(isPresented: $isShowingFullMessage) {
                    Text(message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding()
                        .frame(idealWidth: 300)
                        .presentationCompactAdaptation(.popover)
                }

                // 見た目は再記録ボタン(MapRerecordButton)とそろえる。
                Button("再確認", systemImage: "arrow.clockwise", action: retry)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.glass)
                    .accessibilityLabel("現在地を再確認")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「旅の記録」行の本のアイコンと同じ幅を確保し、状態が切り替わっても見出しの位置がずれないようにする。
    /// 数値で幅を決め打ちしないのは、Dynamic Typeでアイコンが大きくなった時にもそろえるため。
    private func icon(systemName: String, color: Color, isPulsing: Bool) -> some View {
        Image(systemName: "book.closed.fill")
            .font(.title2)
            .hidden()
            .overlay {
                Image(systemName: systemName)
                    .font(.title2)
                    .foregroundStyle(color)
                    .symbolEffect(.pulse, isActive: isPulsing)
            }
            .accessibilityHidden(true)
    }

    private func texts(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// 折りたたまれた旅の記録そのものを、ミニプレイヤーのような1行で見せる。タップでシートを旅の記録まで引き上げる。
///
/// 踏破数・踏破率は地図上の`MapProgressHeader`が常に出しているため、ここでは繰り返さず、
/// ヘッダーに無い「最後にどこを記録したか」だけを添える。iOS 26のシートはそれ自体がガラスの面なので、
/// 内側に背景付きのカードを重ねず、シートの面に直接置く(開ける合図もシートのつまみに任せる)。
/// 訪問済みの場所でだけ「再記録」を右端に添える(未訪問時の記録は誘いシートの専任なので、ここには出さない)。
private struct MapRecordsSummaryRow: View {
    let latestPlace: SavedPlace?
    let isVisited: Bool
    let recordButtonPhase: MapRerecordButtonPhase
    let onRecord: () -> Void
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onExpand) {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed.fill")
                        .font(.title2)
                        .foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("旅の記録")
                            .font(.headline)
                        latestPlaceText
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("タップで旅の記録を開きます")

            if isVisited {
                MapRerecordButton(phase: recordButtonPhase, action: onRecord)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 相対日時(「昨日」「3日前」など)は時間の経過では自動更新されず、画面が再描画された時点の値になる。
    /// 常駐シートは記録・現在地更新のたびに再描画されるため、この粒度(日単位)なら実用上ずれは目立たない。
    @ViewBuilder
    private var latestPlaceText: some View {
        if let latestPlace {
            Text("最近: \(latestPlace.displayName) · \(Text(latestPlace.savedAt, format: .relative(presentation: .named)))")
        } else {
            Text("訪れた場所を記録すると、ここに残ります")
        }
    }
}

/// 再記録ボタンの見た目の段階。状態として保持せず、MapScreenが「保存中か」(MapViewModel.operation)と
/// 「更新済みを見せている最中か」(MapScreenのrerecordConfirmation)から毎回計算して渡す。
enum MapRerecordButtonPhase: CaseIterable {
    case idle, recording, updated

    fileprivate var title: String {
        switch self {
        case .idle: "ピンを立て直す"
        case .recording: "記録中"
        case .updated: "更新済み"
        }
    }

    fileprivate var accessibilityValue: String {
        switch self {
        case .idle: ""
        case .recording: "記録中"
        case .updated: "更新済み"
        }
    }
}

/// 常駐シートの「再記録」ボタン。保存中・完了後をこのボタン自身の状態遷移(再記録→記録中→更新済み→再記録)で
/// 見せることで、行を足してシートの高さを変えずに済ませる。
private struct MapRerecordButton: View {
    let phase: MapRerecordButtonPhase
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reduce Motion時はシンボルの出現エフェクト(拡大を伴う)を使わず、フェードだけにする。
    private var iconTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.symbolEffect(.appear))
    }

    var body: some View {
        Button(action: action) {
            Label {
                // 段階ごとに文言の長さが違い、そのままだとボタンの幅が変わって隣の「旅の記録」の行が揺れる。
                // 全段階の文言を透明のまま重ねて最長の幅に固定する。数値のminWidthで決め打ちすると、
                // Dynamic Typeで文字が大きくなった時に収まらなくなるため使わない。
                ZStack {
                    ForEach(MapRerecordButtonPhase.allCases, id: \.self) { candidate in
                        Text(candidate.title).hidden()
                    }
                    Text(phase.title)
                        .contentTransition(.opacity)
                }
            } icon: {
                // 入れ替わるアイコン同士を横に並べず、同じ位置で重ねて切り替えるためにZStackで包む。
                ZStack {
                    switch phase {
                    case .idle:
                        Image(systemName: "arrow.clockwise")
                            .transition(iconTransition)
                    case .recording:
                        ProgressView()
                            .controlSize(.small)
                            .transition(.opacity)
                    case .updated:
                        Image(systemName: "checkmark")
                            .foregroundStyle(.teal)
                            .transition(iconTransition)
                    }
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.glass)
        // 記録中は保存が重複しないよう、更新済みの間は結果を読み取れるよう、押せなくする。
        .disabled(phase != .idle)
        // phaseは親の様々な状態変化(ViewModelの保存完了など)から計算されるため、変化の出どころに
        // アニメーションが付いているとは限らない。ボタン側で段階の切り替えに必ずアニメーションを乗せる。
        .animation(.easeInOut(duration: 0.25), value: phase)
        .accessibilityLabel("現在地を再度記録")
        .accessibilityValue(phase.accessibilityValue)
    }
}

/// 再記録した場所のピンの上に一時的に出す吹き出し。地図の`Annotation`として、下端をピンの座標に合わせて置く。
/// 表示の開始・終了はMapScreenが決め、ここは出現の演出と、`isDismissing`での透明化だけを持つ。
struct MapRerecordCallout: View {
    let placeName: String
    /// 消し始めたか。Map内のAnnotationは取り除く時のtransitionが効かない見込みのため、
    /// 取り除く前にこれで透明にしておく。
    let isDismissing: Bool

    @State private var hasAppeared = false
    @State private var hasRingFinished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// MapKit標準のMarker(バルーン)の高さの目安(未計測)。吹き出しを座標に置くと同じ座標のMarkerに
    /// 重なるため、この分の透明な空きを下に置いてMarkerの真上に持ち上げる。ずれて見えたらここを調整する。
    private static let markerHeight: CGFloat = 44

    private var ringScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return hasRingFinished ? 1.5 : 0.3
    }

    private var ringOpacity: Double {
        if hasRingFinished { return 0 }
        // Reduce Motion時は広げずに、薄く出してから消すだけにする。
        if reduceMotion { return hasAppeared ? 0.4 : 0 }
        return 0.8
    }

    var body: some View {
        VStack(spacing: 2) {
            // Marker下の標準タイトルと同じ名前が並ぶため、名前だけでは何が起きたかが伝わらない。
            // 「〇〇を記録しました」と文で出し、再記録ボタンと同じアイコンを添えて結果として読めるようにする。
            Label("\(placeName)を記録しました", systemImage: "arrow.clockwise")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                // 現在地バッジ(MapCurrentLocationBadge)と同じ控えめな素材にそろえる。
                .background(.ultraThinMaterial, in: Capsule())
                .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.85, anchor: .bottom)
                .opacity(hasAppeared ? 1 : 0)
            Color.clear
                .frame(width: Self.markerHeight, height: Self.markerHeight)
                // 空きの中心(=ピンの頭のあたり)から、線だけのリングを1回だけ広げる。
                .overlay {
                    Circle()
                        .stroke(Color.teal, lineWidth: 2)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                }
        }
        .opacity(isDismissing ? 0 : 1)
        // 親のwithAnimationのトランザクションがMap内のAnnotationまで届くとは限らないため、ここでも付ける。
        .animation(.easeOut(duration: 0.2), value: isDismissing)
        // 透明な空きがMarkerに重なるため、タップを奪ってピンを選べなくならないようにする。
        .allowsHitTesting(false)
        // 読み上げはMapScreenが保存完了時に1回だけ行うため、ここでは重ねない。
        .accessibilityHidden(true)
        .task {
            await playEntranceAnimation()
        }
    }

    private func playEntranceAnimation() async {
        guard reduceMotion else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { hasAppeared = true }
            withAnimation(.easeOut(duration: 0.8)) { hasRingFinished = true }
            return
        }
        withAnimation(.easeOut(duration: 0.2)) { hasAppeared = true }
        do {
            try await Task.sleep(for: .milliseconds(600))
        } catch {
            // 吹き出しごと取り除かれて中断された。消す相手が無いので何もしない。
            return
        }
        withAnimation(.easeOut(duration: 0.4)) { hasRingFinished = true }
    }
}

/// 星形パーティクルが放射状に飛び散って消える、収集演出の使い回しパーツ。
/// 個々のパーティクルの角度・距離・大きさは初回表示時に1度だけ抽選し、以後は`trigger`の
/// true/falseだけで飛散させる(抽選をやり直さない)。
private struct ParticleBurstView: View {
    let trigger: Bool
    let symbol: String
    let color: Color
    let count: Int
    var distanceRange: ClosedRange<CGFloat> = 30...55
    var sizeRange: ClosedRange<CGFloat> = 8...14

    private struct Particle: Identifiable {
        let id = UUID()
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let rotation: Double
    }

    // @State(参照的に安定)にせず単なるletにすると、親の再描画のたびにこの構造体のinitが再実行され、
    // Particle.id(UUID)が毎回変わってしまう。ForEachはidで要素を追跡するため、trigger切り替え前後で
    // 「同じ星が移動する」のではなく「全く別の星に差し替わる」と解釈され、アニメーションが成立しない。
    // @Stateにしてビューの同一性に紐づけつつ、initで初期値を即座に確定させて競合(onAppear時点でまだ
    // 空配列という状態)も同時に防ぐ。
    @State private var particles: [Particle]

    init(
        trigger: Bool, symbol: String, color: Color, count: Int,
        distanceRange: ClosedRange<CGFloat> = 30...55, sizeRange: ClosedRange<CGFloat> = 8...14
    ) {
        self.trigger = trigger
        self.symbol = symbol
        self.color = color
        self.count = count
        self.distanceRange = distanceRange
        self.sizeRange = sizeRange
        _particles = State(initialValue: (0..<count).map { _ in
            Particle(
                angle: .random(in: 0..<(2 * .pi)),
                distance: .random(in: distanceRange),
                size: .random(in: sizeRange),
                rotation: .random(in: -140...140)
            )
        })
    }

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Image(systemName: symbol)
                    .font(.system(size: particle.size))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(trigger ? particle.rotation : 0))
                    .offset(
                        x: trigger ? cos(particle.angle) * particle.distance : 0,
                        y: trigger ? sin(particle.angle) * particle.distance : 0
                    )
                    .opacity(trigger ? 0 : 1)
                    .scaleEffect(trigger ? 0.3 : 1)
            }
        }
        // 呼び出し元(各FirstVisitSheet)はshowsIcon等をwithAnimation(.spring(...))で
        // 包んでいるため、ここを.animation(_:value:)にすると祖先の明示的トランザクションに上書きされて
        // 無視されてしまう(アイコンのspringの速さでしかパーティクルが動かない/一瞬で終わる)。
        // .transactionでこの部分木のアニメーションを強制的に差し替え、狙った弾け方の速さを確実に反映させる。
        .transaction { transaction in
            guard !transaction.disablesAnimations else { return }
            transaction.animation = .easeOut(duration: 0.75)
        }
        // 最大16個のSF Symbolがそれぞれoffset/rotation/opacity/scaleを同時に動かすため、
        // レイヤーごとに描画すると重ねの多い儀式シートでモーションが重くなる。
        // .drawingGroupで1枚のテクスチャに事前合成し、GPU側の1回の描画に潰すことで負荷を下げる。
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// Wikipediaから探した代表画像を横並びで見せる帯。URLを受け取って描くだけの部品で、取得は持たない。
///
/// 取得(`.task`)を帯自身に持たせて「画像が無ければ何も描かない」構造にすると、SwiftUIでは中身が
/// 空の`Group`に付けた`.task`が一切実行されず、永遠に画像が取れないという自己矛盾に陥る。
/// そのため取得は常に存在するシート本体側で行い、URLが揃ったときだけこの帯を差し込む。
private struct WikipediaImageStrip: View {
    let urls: [URL]

    /// 帯の高さ。画像の到着前から場所を確保したいシート(JapanFirstVisitSheet)からも参照する。
    static let imageHeight: CGFloat = 92

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WAGhack", category: "WikipediaImage")

    var body: some View {
        HStack(spacing: 8) {
            ForEach(urls, id: \.self) { url in
                // 画像はダウンロード完了のタイミングがばらばらで、そのまま出すと1枚ずつパッと切り替わって
                // 目立つため、読み込み状態の変化にアニメーションを乗せて写真だけをフェードインさせる。
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.4))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    case .failure(let error):
                        // 読み込み失敗は枠ごと透明にして目立たせないが、原因は追えるよう残す。
                        let _ = Self.logger.error("画像の読み込み失敗 \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        Color.clear
                    default:
                        Color.clear
                    }
                }
                .frame(height: Self.imageHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .transition(.opacity)
    }
}

/// 初めての都道府県に入ったときだけ、市区町村を記録する前に割り込んで見せる特別感のあるシート。
/// 背景を水色にするのはMapScreen側の`.presentationBackground`で行い、ここは中身だけを持つ。
/// 要素を1つずつ間を置いて出す「儀式感」のある演出にして、都道府県という単位の大きさを体験としても伝える。
struct PrefectureFirstVisitSheet: View {
    let prefectureName: String
    let confirm: () -> Void

    @State private var showsIcon = false
    @State private var showsTitle = false
    @State private var showsSubtitle = false
    @State private var showsButton = false
    /// Wikipediaの代表画像。取得は本体の`.task`で非同期に行い、揃ったときだけ帯を差し込む。
    @State private var imageURLs: [URL] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                if !reduceMotion {
                    ParticleBurstView(
                        trigger: showsIcon, symbol: "sparkle", color: .blue,
                        count: 14, distanceRange: 40...84, sizeRange: 10...18
                    )
                }
                Image(systemName: "sparkles")
                    .font(.system(size: 52))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    // symbolEffect(.bounce)は下のscaleEffect/opacityのspringと同じ「ポンと出る」動きを
                    // 二重に(グラデーション付きベクターの再描画で)行っていただけなので外す。
                    // 見た目はspringだけでほぼ変わらず、モーションの負荷だけ下がる。
                    .scaleEffect(showsIcon ? 1 : 0.3)
                    .opacity(showsIcon ? 1 : 0)
            }
            .frame(height: 70)
            VStack(spacing: 6) {
                Text("初めての都道府県です！")
                    .font(.title2.weight(.bold))
                    .scaleEffect(showsTitle ? 1 : 0.7)
                    .opacity(showsTitle ? 1 : 0)
                Text("\(prefectureName)を記録して、旅の記録に加えましょう")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(showsSubtitle ? 1 : 0)
            }
            if !imageURLs.isEmpty {
                WikipediaImageStrip(urls: imageURLs)
            }
            Button(action: confirm) {
                Label("\(prefectureName)を記録する", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)
            .opacity(showsButton ? 1 : 0)
            .offset(y: showsButton ? 0 : 12)
        }
        .padding(24)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else {
                showsIcon = true
                showsTitle = true
                showsSubtitle = true
                showsButton = true
                return
            }
            // アイコン→タイトル→サブタイトル→ボタンの順に少しずつ間を置いて見せる「儀式感」の演出。
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { showsIcon = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.18)) { showsTitle = true }
            withAnimation(.easeOut(duration: 0.3).delay(0.3)) { showsSubtitle = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.4)) { showsButton = true }
        }
        .task(id: prefectureName) {
            let urls = await WikipediaImageService.shared.images(prefectureName: prefectureName)
            withAnimation(.easeOut(duration: 0.3)) { imageURLs = urls }
        }
    }
}

/// 都道府県よりさらに上位の「日本」という国そのものを記録する、アプリ全体の導入儀式。
/// 新規・既存ユーザーとも、まだ見ていなければ最初に現在地を取得して地図をそこへ動かし終えた後に、
/// 都道府県・市区町村どちらの初訪問儀式よりも先に一度だけ挟む(表示可否はMapScreen側で
/// バージョンに依存しないUserDefaultsフラグとして管理し、チュートリアルの表示有無とは独立させる)。
struct JapanFirstVisitSheet: View {
    let confirm: () -> Void

    @State private var showsIcon = false
    @State private var showsTitle = false
    @State private var showsSubtitle = false
    @State private var showsButton = false
    /// 富士山・伏見稲荷・東京の3枚で「日本」を象徴させる。都道府県版と違い検索結果任せにはせず、
    /// 季節外れの富士山や鳥居の写っていない京都府庁写真などが出ないよう、事前に確認した
    /// ファイルを`curatedImage`で直接指定する(この儀式は表示箇所が1つしかなく、狙った絵を
    /// 確実に出す価値がある)。
    @State private var imageURLs: [URL] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// シートの固定の高さ。画像の帯の場所を最初から確保しているため、画像の到着で変わらない。
    /// 標準の文字サイズで、幅375〜440ptのどのiPhoneでも内容がちょうど収まる実測値(副題は1行に収まる)。
    /// 文字サイズを大きくしてこれを超えた分は、本体のScrollViewでスクロールできる。
    /// 余白・文言・要素を変えたら、UIHostingController.sizeThatFitsで測り直してこの値も更新すること。
    static let presentationHeight: CGFloat = 384

    /// シートの提示アニメーション(約0.4秒)の最中に文字をバネで動かすと、シートの移動と重なって
    /// カクついて見えるため、提示がほぼ終わってから登場演出を始める。提示の終わり際はシートの動きが
    /// 小さいので、完全に止まるまでは待たない(待ち切ると儀式全体が間延びして見えるため)。
    private static let entranceStartDelay: Duration = .milliseconds(250)
    /// 写真の帯を差し込むまでの待ち時間(最後のボタンのdelay 0.25秒 + springの動きが大きい前半分)。
    /// 帯の差し込みで画像のデコードが始まるため演出と重ねたくないが、springが完全に収束するまで
    /// 待つと写真だけ遅れて見えるので、目立つ動きが終わった時点で差し込む。
    private static let entranceDuration: Duration = .milliseconds(450)

    var body: some View {
        ScrollView {
            content
        }
        // 標準の文字サイズでは収まるのでスクロールさせず、収まらない時だけスクロールを有効にする。
        .scrollBounceBehavior(.basedOnSize)
        // アイコン周りのパーティクルはアイコンの枠の外まで飛び散るため、ScrollViewの境界で切り取らない。
        .scrollClipDisabled()
    }

    private var content: some View {
        VStack(spacing: 20) {
            ZStack {
                if !reduceMotion {
                    ParticleBurstView(
                        trigger: showsIcon, symbol: "sparkle", color: .red,
                        count: 16, distanceRange: 44...90, sizeRange: 10...18
                    )
                }
                // 国そのものを記録する儀式なので、国旗の絵文字をそのままアイコンにする。
                // 1文字のグリフで多層の合成が無いため、以前の円の意匠で必要だったdrawingGroupは付けない。
                Text("🇯🇵")
                    .font(.system(size: 56))
                    // 直後のタイトル「日本」と読み上げが重複するため、装飾として扱う。
                    .accessibilityHidden(true)
                    .scaleEffect(showsIcon ? 1 : 0.3)
                    .opacity(showsIcon ? 1 : 0)
            }
            .frame(height: 70)
            VStack(spacing: 6) {
                Text("日本")
                    .font(.title2.weight(.bold))
                    .scaleEffect(showsTitle ? 1 : 0.7)
                    .opacity(showsTitle ? 1 : 0)
                Text("ようこそ美しい日本へ。よりみちをはじめましょう")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(showsSubtitle ? 1 : 0)
            }
            // 画像が届く前から帯の高さを確保しておく。後から差し込んで伸ばすとシートの高さも
            // 変える必要があり、表示中にシートが動いて重くなるため(presentationHeightはこの確保が前提)。
            // 取得に失敗した場合は、この高さの余白だけが残る。
            ZStack {
                if !imageURLs.isEmpty {
                    WikipediaImageStrip(urls: imageURLs)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: WikipediaImageStrip.imageHeight)
            Button(action: confirm) {
                Label("日本を記録する", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .opacity(showsButton ? 1 : 0)
            .offset(y: showsButton ? 0 : 12)
        }
        .padding(24)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .task {
            // 画像URLの取得(軽い通信)だけは先に並行して始めておき、画像が出るまでの待ち時間を増やさない。
            // めっちゃ雪の降った富士山、鳥居が映える伏見稲荷、東京の大都市感が伝わる上空写真、
            // の3枚を狙って選定済み(Wikimedia Commonsで実在確認済みのファイル名)。
            async let fuji = WikipediaImageService.shared.curatedImage(
                fileTitle: "冬日晴空下的富士山_Fuji_Mountain_under_winter_blue_sky.jpg"
            )
            async let inari = WikipediaImageService.shared.curatedImage(
                fileTitle: "Fushimi Inari-taisha senbon-torii, August 2019.jpg"
            )
            async let tokyo = WikipediaImageService.shared.curatedImage(
                fileTitle: "Aerial view of tokyo skytree.jpg"
            )
            await playEntranceAnimation()
            let results = await [fuji, inari, tokyo]
            // 帯を差し込むと画像本体のダウンロードとデコードが始まり重いため、登場演出が終わってから差し込む。
            withAnimation(.easeOut(duration: 0.3)) { imageURLs = results.compactMap { $0 } }
        }
    }

    /// アイコン→タイトル→サブタイトル→ボタンの順に出す登場演出。演出が落ち着くまで待ってから戻る。
    private func playEntranceAnimation() async {
        guard !reduceMotion else {
            showsIcon = true
            showsTitle = true
            showsSubtitle = true
            showsButton = true
            return
        }
        // 開始を遅らせるのはwithAnimationの.delayではなくsleepで行う。ParticleBurstViewは.transactionで
        // アニメーションを差し替えるためdelayが消え、アイコンより先にパーティクルだけが弾けてしまう。
        try? await Task.sleep(for: Self.entranceStartDelay)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { showsIcon = true }
        // 1つずつ出す順番は残しつつ、間隔は「順に出た」と分かる最小限にする(間隔が長いと待たされて見える)。
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1)) { showsTitle = true }
        withAnimation(.easeOut(duration: 0.3).delay(0.18)) { showsSubtitle = true }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.25)) { showsButton = true }
        try? await Task.sleep(for: Self.entranceDuration)
    }
}

/// 初めての市区町村に出会った時(記録前の誘い)と、実際に記録した直後(記録後の祝福)の
/// どちらでも使う共通シート。`PrefectureFirstVisitSheet`と同じ「儀式感」の演出
/// (要素を1つずつ間を置いて出す)を踏襲しつつ、モードに応じて主役のボタンと文言だけを変える。
/// 節目(25/50/75/100%)は都道府県よりさらに大きな達成として、色をトロフィーの金色にして差別化する。
/// 記録後(celebration)だけ「みどころを見る」から図鑑(`MunicipalityDetailScreen`)に直接繋げる。
/// 記録前(invitation)は「記録して初めて開く」という順番を保つため、あえて出さない。
struct MunicipalityFirstVisitSheet: View {
    enum Mode {
        /// 記録前。まだ訪問済みではない現在地に出会った瞬間に、記録を後押しする。
        case invitation(municipality: Municipality, save: () -> Void)
        /// 記録後。保存が完了した結果を祝う。都道府県情報が無い場合(区が特定できない等)はmunicipalityがnilになりうる。
        case celebration(result: MapVisitResult, municipality: Municipality?)
    }

    let mode: Mode
    let dismiss: () -> Void
    /// 「みどころを見る」を押した時の遷移。図鑑の1ページとして孤立させず、旅の記録の
    /// ナビゲーション階層(市区町村詳細→都道府県一覧→旅の記録)にそのまま合流させるため、
    /// このシート自身では遷移を持たず、常に呼び出し元(MapScreen)に委ねる。
    let showDetail: () -> Void

    @State private var showsIcon = false
    @State private var showsTitle = false
    @State private var showsSubtitle = false
    @State private var showsButtons = false
    /// Wikipediaの代表画像。取得は本体の`.task`で非同期に行い、揃ったときだけ帯を差し込む。
    @State private var imageURLs: [URL] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMilestone: Bool {
        guard case .celebration(let result, _) = mode else { return false }
        return result.milestone != nil
    }
    private var tint: Color { isMilestone ? .yellow : .teal }
    private var icon: String {
        switch mode {
        case .invitation: "mappin.circle.fill"
        case .celebration: isMilestone ? "trophy.fill" : "checkmark.seal.fill"
        }
    }
    private var gradientColors: [Color] { isMilestone ? [.yellow, .orange] : [.teal, .mint] }

    private var municipality: Municipality? {
        switch mode {
        case .invitation(let municipality, _): municipality
        case .celebration(_, let municipality): municipality
        }
    }

    /// 「みどころを見る」は記録後(celebration)だけで見せる。記録前に見せると、まだ自分の街になって
    /// いない場所の情報を先に消費してしまい、「記録して初めて開く」という報酬の順番が崩れるため。
    private var showsDetailLink: Bool {
        guard case .celebration = mode else { return false }
        return municipality != nil
    }

    private var title: String {
        switch mode {
        case .invitation: "初めての街です！"
        case .celebration(let result, _): result.title
        }
    }

    private var subtitle: String {
        switch mode {
        case .invitation(let municipality, _):
            "\(municipality.municipalityName)は、あなたが初めて訪れた街。図鑑の1ページを増やそう"
        case .celebration(let result, _):
            if let milestone = result.milestone {
                "市区町村の踏破率が\(milestone)%を超えました。この調子で日本を制覇しましょう"
            } else {
                "\(result.municipalityName)を旅の記録に加えました。みどころは記録一覧から確認できます"
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                if !reduceMotion {
                    ParticleBurstView(
                        trigger: showsIcon, symbol: "sparkle", color: tint,
                        count: isMilestone ? 14 : 10,
                        distanceRange: isMilestone ? 40...84 : 30...60,
                        sizeRange: isMilestone ? 10...18 : 8...14
                    )
                }
                Image(systemName: icon)
                    .font(.system(size: 52))
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    // symbolEffect(.bounce)は下のscaleEffect/opacityのspringと同じ「ポンと出る」動きを
                    // 二重に(グラデーション付きベクターの再描画で)行っていただけなので外す。
                    // 見た目はspringだけでほぼ変わらず、モーションの負荷だけ下がる。
                    .scaleEffect(showsIcon ? 1 : 0.3)
                    .opacity(showsIcon ? 1 : 0)
            }
            .frame(height: 70)
            VStack(spacing: 6) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .scaleEffect(showsTitle ? 1 : 0.7)
                    .opacity(showsTitle ? 1 : 0)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(showsSubtitle ? 1 : 0)
            }
            if !imageURLs.isEmpty {
                WikipediaImageStrip(urls: imageURLs)
            }
            VStack(spacing: 10) {
                primaryButton
                if showsDetailLink {
                    // 主役は「みどころを見る」(primaryButton)なので、閉じるは控えめな二番手に置く。
                    Button(action: dismiss) {
                        Label("閉じる", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(tint)
                    .controlSize(.large)
                }
            }
            .opacity(showsButtons ? 1 : 0)
            .offset(y: showsButtons ? 0 : 12)
        }
        .padding(24)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else {
                showsIcon = true
                showsTitle = true
                showsSubtitle = true
                showsButtons = true
                return
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { showsIcon = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.18)) { showsTitle = true }
            withAnimation(.easeOut(duration: 0.3).delay(0.3)) { showsSubtitle = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.4)) { showsButtons = true }
        }
        .task(id: municipality?.code) {
            guard let municipality else { return }
            let urls = await WikipediaImageService.shared.images(
                prefectureName: municipality.prefectureName, municipalityName: municipality.municipalityName
            )
            withAnimation(.easeOut(duration: 0.3)) { imageURLs = urls }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch mode {
        case .invitation(let municipality, let save):
            Button(action: save) {
                Label("\(municipality.municipalityName)を記録する", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .controlSize(.large)
        case .celebration:
            if showsDetailLink {
                // 記録した直後はその街への関心が最も高いため、図鑑への入口を主役(上・塗りつぶし)にする。
                Button(action: showDetail) {
                    Label("みどころを見る", systemImage: "book.pages")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(.large)
            } else {
                // 市区町村が特定できず図鑑を開けない場合は、閉じるだけが唯一の操作なので主役に据える。
                Button(action: dismiss) {
                    Label("閉じる", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(.large)
            }
        }
    }
}
