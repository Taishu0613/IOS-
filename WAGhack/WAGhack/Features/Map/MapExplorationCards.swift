import SwiftUI

struct MapProgressHeader: View {
    let prefecture: PrefectureExploration?
    let summary: ExplorationSummary

    /// 0=市区町村(都道府県別)、1=全国(都道府県別)。TabView(.page)のネイティブなページングに任せることで、
    /// スワイプの取り合い・気づきにくさ・モーションの薄さを自前実装せずに解決する。
    @State private var page = 1

    private var canToggle: Bool { prefecture != nil }
    /// カードの高さのみを固定し、ドットの分は含めない(ドットはカードの外に別途置く)。
    private static let cardHeight: CGFloat = 96

    var body: some View {
        VStack(spacing: 2) {
            TabView(selection: $page) {
                if let prefecture {
                    pageView(
                        title: "\(prefecture.name)  \(prefecture.progress.visited) / \(prefecture.progress.total) 市区町村",
                        progress: prefecture.progress,
                        unit: "市区町村",
                        tint: nil
                    )
                    .tag(0)
                }
                pageView(
                    title: "都道府県 \(summary.prefectureProgress.visited) / \(summary.prefectureProgress.total) ",
                    progress: summary.prefectureProgress,
                    unit: "都道府県",
                    tint: .cyan
                )
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: Self.cardHeight)
            // システム標準のページドットはカードの内側下端に重なってしまうため、自前でカードの外に置く。
            if canToggle {
                pageDots
            }
        }
        .onChange(of: canToggle, initial: true) { _, canToggle in
            // 現在地の都道府県が不明な間は市区町村ページ自体が存在しないので、全国ページへ寄せる。
            if !canToggle { page = 1 }
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach([0, 1], id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.primary.opacity(0.8) : Color.primary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func pageView(title: String, progress: ExplorationCount, unit: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ProgressView(value: progress.fraction)
                .tint(.teal)
                .accessibilityLabel("\(unit)踏破率")
                .accessibilityValue(progress.percentageText)
            Text("\(progress.percentageText) · \(progress.nextGoalText(unit: unit))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 都道府県制覇率(全国ページ)は市区町村ページと見分けがつくよう、ごく薄く水色にする。
        // clearベースにして、より透過するリキッドグラスの見た目にする。
        .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.22)) } ?? .clear, in: RoundedRectangle(cornerRadius: 18))
        // ページ間に隙間を作り、スライド中にカードの角がTabViewの端でクリップされて見切れるのを防ぐ。
        .padding(.horizontal, 6)
    }
}

/// 地図の上に浮かせる、現在地の「〇〇県〇〇市」ラベル。踏破率ヘッダーとは別の独立したピルとして置く。
/// タップで現在地の詳細シートを開く。
struct MapCurrentLocationBadge: View {
    let name: String
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
        .accessibilityHint("タップで現在地の詳細を表示します")
    }
}

/// 折りたたみシートの「現在地」カード。初めての場所への誘い・記録ボタンは`MunicipalityFirstVisitSheet`
/// (記録前)に譲ったため、ここでは常に旅の記録そのものの見出しを主役にする。取るべき行動は
/// 「旅の記録を見る」か「(再度/この場所を)記録する」のどちらかだけに絞り、機能を増やさない。
/// みどころはここでは出さない(図鑑・詳細で見る)。
struct MapCurrentPlaceCard: View {
    let isVisited: Bool
    let statusText: String?
    let errorMessage: String?
    let result: MapVisitResult?
    let summary: ExplorationSummary
    let save: () -> Void
    let refresh: () -> Void
    let showRecords: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result {
                AchievementBanner(result: result)
            }
            if let statusText {
                currentLocationLabel
                ProgressView(statusText).font(.body)
            } else if let errorMessage {
                currentLocationLabel
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.body)
                Button("現在地を再確認", action: refresh)
                    .buttonStyle(.borderedProminent)
            } else {
                MapRecordsPreviewCard(summary: summary, isVisited: isVisited, onRecord: save, onExpand: showRecords)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentLocationLabel: some View {
        Label("現在地", systemImage: "location.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.teal)
    }
}

/// 旅の記録ページの「見出しだけ」のプレビュー。タップでシートを旅の記録まで引き上げる、
/// いわば折りたたまれた旅の記録そのもの。訪問済みなら再度記録、未訪問ならこの場所を記録する、
/// という控えめな第二の行動を見出しの下に添えるだけにする(主役は誘導シートの側)。
private struct MapRecordsPreviewCard: View {
    let summary: ExplorationSummary
    let isVisited: Bool
    let onRecord: () -> Void
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onExpand) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("旅の記録", systemImage: "book.closed.fill")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 20) {
                        statTile(value: "\(summary.visitedPrefectureCount)", unit: "都道府県")
                        statTile(value: "\(summary.progress.visited)", unit: "市区町村")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("旅の記録")
            .accessibilityHint("タップで旅の記録を開きます")

            Button(
                isVisited ? "現在地を再度記録" : "この場所を記録する",
                systemImage: isVisited ? "arrow.clockwise" : "plus.circle",
                action: onRecord
            )
            .font(.footnote)
            .buttonStyle(.borderless)
            .tint(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statTile(value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.teal)
                .monospacedDigit()
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 「旅の記録」の見出しだけの行。最小表示(現在地カードをさらに畳んだ状態)から使う、
/// `MapRecordsPreviewCard`のさらに簡略版。
struct MapRecordsLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                Text("旅の記録")
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityHint("シートを広げて旅の記録を表示します")
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
        // 呼び出し元(AchievementBanner/PrefectureFirstVisitSheet)はshowsIcon等をwithAnimation(.spring(...))で
        // 包んでいるため、ここを.animation(_:value:)にすると祖先の明示的トランザクションに上書きされて
        // 無視されてしまう(アイコンのspringの速さでしかパーティクルが動かない/一瞬で終わる)。
        // .transactionでこの部分木のアニメーションを強制的に差し替え、狙った弾け方の速さを確実に反映させる。
        .transaction { transaction in
            guard !transaction.disablesAnimations else { return }
            transaction.animation = .easeOut(duration: 0.75)
        }
        .accessibilityHidden(true)
    }
}

/// 記録した瞬間の「集めた」快感を演出するバナー。ただの初訪問はコインを拾うようにサッと弾む程度、
/// 節目(25/50/75/100%)は二重の輪＋パーティクルの弾け方で、達成の重みの違いを体で分からせる。
/// どちらも、都道府県を丸ごと祝う`PrefectureFirstVisitSheet`とは意図的に違う「軽さ」にしている。
private struct AchievementBanner: View {
    let result: MapVisitResult

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMilestone: Bool { result.milestone != nil }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if isMilestone {
                    ForEach([0, 1], id: \.self) { ring in
                        Circle()
                            .stroke(Color.yellow.opacity(hasAppeared ? 0 : 0.7), lineWidth: 3)
                            .frame(
                                width: hasAppeared ? 54 + CGFloat(ring) * 16 : 20,
                                height: hasAppeared ? 54 + CGFloat(ring) * 16 : 20
                            )
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.65).delay(Double(ring) * 0.12),
                                value: hasAppeared
                            )
                    }
                    if !reduceMotion {
                        ParticleBurstView(
                            trigger: hasAppeared, symbol: "sparkle", color: .yellow,
                            count: 10, distanceRange: 26...48, sizeRange: 8...13
                        )
                    }
                } else if !reduceMotion {
                    ParticleBurstView(
                        trigger: hasAppeared, symbol: "sparkle", color: .teal,
                        count: 5, distanceRange: 14...26, sizeRange: 6...9
                    )
                }
                Image(systemName: isMilestone ? "trophy.fill" : "checkmark.seal.fill")
                    .font(isMilestone ? .title.weight(.bold) : .title3)
                    .foregroundStyle(isMilestone ? .yellow : .teal)
                    .symbolEffect(.bounce, value: hasAppeared)
            }
            Text(result.title)
                .font(isMilestone ? .title2.weight(.bold) : .title3.weight(.semibold))
                .foregroundStyle(isMilestone ? Color.primary : Color.teal)
        }
        .scaleEffect(hasAppeared ? 1 : (isMilestone ? 0.4 : 0.6))
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            withAnimation(
                reduceMotion ? nil : .spring(response: isMilestone ? 0.5 : 0.35, dampingFraction: isMilestone ? 0.5 : 0.62)
            ) {
                hasAppeared = true
            }
        }
    }
}

/// 初めての都道府県に入ったときだけ、市区町村を記録する前に割り込んで見せる特別感のあるシート。
/// 背景を水色にするのはMapScreen側の`.presentationBackground`で行い、ここは中身だけを持つ。
/// `AchievementBanner`(市区町村)は一瞬でポンと出るのに対し、こちらは要素を1つずつ間を置いて
/// 出す「儀式感」のある演出にして、都道府県という単位の大きさの違いを体験としても分ける。
struct PrefectureFirstVisitSheet: View {
    let prefectureName: String
    let confirm: () -> Void

    @State private var showsIcon = false
    @State private var showsTitle = false
    @State private var showsSubtitle = false
    @State private var showsButton = false
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
                    .symbolEffect(.bounce, value: showsIcon)
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
                    .symbolEffect(.bounce, value: showsIcon)
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
            VStack(spacing: 10) {
                primaryButton
                if showsDetailLink {
                    Button(action: showDetail) {
                        Label("みどころを見る", systemImage: "book.pages")
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
