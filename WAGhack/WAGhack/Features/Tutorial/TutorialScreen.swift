import SwiftUI

/// 新規アップデート後に表示するチュートリアル。1ページ目は「日本という国そのもの」を
/// 記録対象として紹介する遊び心のある詩、以降は実際の記録操作に紐づく短い説明で構成する。
/// 最終ページは、閉じた直後にMapScreenが現在地取得を始めて位置情報の許可ダイアログが出ることを
/// 予告する文言にし、唐突感を消す。ダイアログの要求自体はMapScreen(LocationService)に任せる。
/// ここでも許可を求めてしまうと、閉じた瞬間にMapScreen側も未確定のまま同じ許可を求め、
/// ダイアログが二重に積まれてしまう(シミュレータで確認済みの不具合)。
struct TutorialScreen: View {
    let onFinish: () -> Void

    @State private var pageIndex = 0
    /// footer(ドット+ボタン)の実測高さ。詩ページのScrollViewはTabViewの外にあるfooterの存在を
    /// 知らないため、これを最下部の余白として明示的に伝えないと、最後の連がfooterの下に隠れてしまう。
    @State private var footerHeight: CGFloat = 0

    private let pages = TutorialPage.all

    var body: some View {
        ZStack {
            // TabView自体は下端だけ無視して(footerまで塗るため)ノッチ側は避けるが、
            // それだけだとTabViewが避けた上端の帯が黒く塗られず背景が透けるため、
            // 別レイヤーで画面全体を黒く敷いておく。
            Color.black.ignoresSafeArea()

            ZStack(alignment: .topTrailing) {
                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        TutorialPageContent(page: page, footerHeight: footerHeight)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .bottom)

                // このZStack自体は安全領域を無視していないので、「スキップ」は
                // ノッチ/ステータスバーと衝突せず自然な位置に収まる。
                if pageIndex < pages.count - 1 {
                    Button("スキップ", action: finish)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            TutorialPageDots(count: pages.count, current: pageIndex)

            Button(pageIndex == pages.count - 1 ? "はじめる" : "次へ") {
                if pageIndex == pages.count - 1 {
                    finish()
                } else {
                    withAnimation { pageIndex += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background {
            // glassEffect(Rectangle)は帯の上端に縁取り(ハイライト)が出てページとの境目が
            // 目立つため、縁のないultraThinMaterialに変更(MapCurrentLocationBadgeと同じ考え方)。
            // .backgroundだけをignoresSafeAreaすることで、ボタン/ドットの位置は安全領域内の
            // ままホームインジケーター側まで帯を塗り切り、下端に隙間を残さない。
            // ultraThinMaterialは標準素材の中で最も透過するが、それでもページの色を
            // はっきり隠してしまうため、opacityをさらに落としてページ背景を強く透かす。
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.55)
                .ignoresSafeArea(edges: .bottom)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
    }

    private func finish() {
        withAnimation { onFinish() }
    }
}

private struct TutorialPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

private struct TutorialPageContent: View {
    let page: TutorialPage
    let footerHeight: CGFloat

    var body: some View {
        switch page {
        case .story(let stanzas):
            TutorialStoryPage(stanzas: stanzas, footerHeight: footerHeight)
        case .feature(let icon, let title, let text, let tint):
            TutorialFeaturePage(icon: icon, title: title, text: text, tint: tint)
        }
    }
}

/// 詩を連ごとに少しずつ浮かび上がらせ、映画の導入のような間を作る。タップすれば即座に全文表示できる。
private struct TutorialStoryPage: View {
    let stanzas: [TutorialStanza]
    let footerHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedCount = 0
    /// 初回の文章レンダリング(フォントの初期化など)に一瞬かかっても唐突に出さないよう、
    /// 連ごとの演出とは別に、ページ全体をまずふわっと出す。
    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(Array(stanzas.enumerated()), id: \.offset) { index, stanza in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(stanza.lines, id: \.self) { line in
                            Text(line)
                                .font(stanza.isLead ? .title.bold() : .system(.title3, design: .serif))
                                .foregroundStyle(.white)
                        }
                    }
                    // フェード+上方向オフセットのみで浮かび上がらせる。ブラーは出現時に
                    // ちらついて見えたため使わない。
                    .opacity(index < revealedCount ? 1 : 0)
                    .offset(y: index < revealedCount ? 0 : 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            // TabView側は上端の安全領域を尊重するようにしたので、ここでは「スキップ」ボタンの
            // 行と1行目が衝突しない分だけを追加すればよい(安全領域そのものの分は含めない)。
            .padding(.top, 56)
            // TabView自体はfooterの分だけ画面下まで広がっているため、footerの実測高さを
            // 明示的に加算しないと最後の連がfooterの裏に隠れてしまう。
            .padding(.bottom, 40 + footerHeight)
            // ScrollViewの外側に付けると中身のopacity/blur等の変化にアニメーションが乗らず、
            // 連が一瞬で切り替わってしまう(iOS 26.5で確認)。必ずコンテンツ側に付ける。
            .animation(.easeOut(duration: 1.1), value: revealedCount)
        }
        .scrollIndicators(.hidden)
        .background(
            // アプリ全体のアクセントカラー(.teal)を基調にし、他画面の儀式演出と同じ
            // Glassの薄い色付け(opacity 0.22)に合わせて浮かないようにする。
            LinearGradient(colors: [.black, Color.teal.opacity(0.22)], startPoint: .top, endPoint: .bottom)
        )
        .opacity(hasAppeared ? 1 : 0)
        .onTapGesture {
            revealedCount = stanzas.count
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { hasAppeared = true }
        }
        .task {
            guard revealedCount == 0 else { return }
            if reduceMotion {
                revealedCount = stanzas.count
                return
            }
            for index in stanzas.indices {
                revealedCount = index + 1
                try? await Task.sleep(for: .seconds(0.9))
            }
        }
    }
}

private struct TutorialFeaturePage: View {
    let icon: String
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(tint)
            Text(title)
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(text)
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            // Spacerを2つ重ねて下側の余白を上側より大きくし、内容を中央よりやや上に寄せる。
            // footer(ドット+ボタン)はこのページの外側でsafeAreaInsetとして重なるため、
            // 中央揃えのままだとテキストがfooterの帯に近づきすぎるのを避けている。
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [.black, tint.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        )
    }
}

#Preview {
    TutorialScreen(onFinish: {})
}
