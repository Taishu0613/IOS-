//
//  ContentView.swift
//  WAGhack
//
//  Created by 若杉泰周 on 2026/08/23.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    private let modelContainer: ModelContainer?

    @State private var masterLoadState: MasterLoadState
    @State private var tutorialGate = TutorialGate()

    init(modelContainer: ModelContainer? = nil) {
        self.modelContainer = modelContainer
        _masterLoadState = State(initialValue: Self.initialMasterLoadState(modelContainer: modelContainer))
    }

    /// 地図が操作の主役になってよい状態か。読み込み画面・チュートリアルの裏にいる間はfalse。
    private var isMapActive: Bool {
        masterLoadState.isReady && !tutorialGate.isPresented
    }

    var body: some View {
        ZStack {
            // 地図が常に主役で、記録一覧はMapScreenの常駐シートから辿る構成のためタブは持たない。
            // MapKitの初期化とマスタの読み込みは重く、チュートリアルの「はじめる」を押した瞬間に
            // まとめて走ると画面が固まって見えるため、読み込み画面・チュートリアルの裏で先に生成しておく。
            // 裏にいる間はisActive=falseにして、現在地取得(位置情報の許可ダイアログ)やシートの
            // 自動提示を止める(fullScreenCoverで重ねるとそれらの自動提示と競合するため、ZStackで重ねる)。
            MapScreen(isActive: isMapActive)
                .allowsHitTesting(isMapActive)
                .accessibilityHidden(!isMapActive)

            if !masterLoadState.isReady {
                // 初期データ構築が終わるまではチュートリアルを出さない。構築中はメイン
                // スレッドが一時的にブロックされうるため、詩のフェード演出と同時に走らせると
                // アニメーションが固まって見えてしまう。ロード完了後にチュートリアルへ進む。
                masterLoadOverlay
                    .transition(.opacity)
                    // フェードアウト中も、入れ替わりで出てくるチュートリアル(zIndex 1)より手前に描く。
                    // 背景色が同じなので、読み込み画面が溶けて詩が浮かび上がるように見える。
                    .zIndex(2)
            } else if tutorialGate.isPresented {
                TutorialScreen(onFinish: { withAnimation { tutorialGate.markSeen() } })
                    // 閉じる時のフェードアウト中も地図より手前に描かれるよう、明示的に前面へ置く。
                    .zIndex(1)
            }
        }
        .task {
            guard case .idle = masterLoadState else { return }
            await loadMunicipalityMaster()
        }
    }

    @ViewBuilder
    private var masterLoadOverlay: some View {
        switch masterLoadState {
        case .ready:
            EmptyView()
        case .idle, .loading:
            MasterLoadBackdrop {
                VStack(spacing: 28) {
                    // 明朝体(serif)は使わず、システム標準のゴシック体(日本語はヒラギノ角ゴ)にする。
                    // Noto Sans JPに近い見た目を、フォントを同梱せずに得られる。
                    Text("よりみち")
                        .font(.largeTitle.weight(.bold))
                    VStack(spacing: 8) {
                        Text("旅の支度をしています")
                            .font(.title3)
                        // 詩の1連目(「47の都道府県と、1,700を超える市区町村」)と数字をそろえる。
                        Text("47の都道府県と、1,700を超える街を用意しています")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView()
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
            }
        case .failed(let message):
            MasterLoadBackdrop {
                ContentUnavailableView {
                    Label("旅の準備ができませんでした", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("再試行") {
                        Task {
                            await loadMunicipalityMaster()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                }
            }
        }
    }

    /// 初回描画より前に、マスタの同期が必要かどうかを確定させる。`.task`の中で判定すると、
    /// 同期が不要な起動でも判定が終わるまでの一瞬だけ読み込み画面が出てちらつくため。
    /// ここで行うのはCSVのハッシュ計算と件数の取得だけで、同期そのもの(全件のパースと比較)より十分軽い。
    private static func initialMasterLoadState(modelContainer: ModelContainer?) -> MasterLoadState {
        guard let modelContainer else { return .ready }

        // どちらも失敗時は「同期が必要」側に倒すだけで、エラーの内容は同期処理の中で改めて表示するためtry?にする。
        let fingerprint = (try? MunicipalityMasterImporter.sourceData()).map(MunicipalityMasterSyncGate.fingerprint(of:))
        let storedCount = (try? modelContainer.mainContext.fetchCount(FetchDescriptor<Municipality>())) ?? 0

        let needsSynchronization = MunicipalityMasterSyncGate().needsSynchronization(
            fingerprint: fingerprint,
            storedMunicipalityCount: storedCount
        )
        return needsSynchronization ? .idle : .ready
    }

    private func loadMunicipalityMaster() async {
        guard let modelContainer else {
            masterLoadState = .ready
            return
        }

        masterLoadState = .loading

        do {
            let csvData = try MunicipalityMasterImporter.sourceData()
            let records = try MunicipalityMasterImporter().records(from: csvData)
            let masterStore = MunicipalityMasterStore(modelContainer: modelContainer)
            try await masterStore.synchronize(records: records)
            MunicipalityMasterSyncGate().markSynchronized(
                fingerprint: MunicipalityMasterSyncGate.fingerprint(of: csvData)
            )
            withAnimation(.easeOut(duration: 0.4)) {
                masterLoadState = .ready
            }
        } catch {
            masterLoadState = .failed(error.localizedDescription)
        }
    }
}

/// 読み込み画面の背景。完了後に続くチュートリアルの詩のページ(TutorialStoryPage)と同じ黒→ティールにそろえ、
/// 読み込み画面から詩へ切り替わる時に、別の画面へ飛んだように見せない。
private struct MasterLoadBackdrop<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            // TutorialScreenと同じく、黒を敷いた上に薄いティールのグラデーションを重ねる。
            Color.black
                .ignoresSafeArea()
            LinearGradient(colors: [.black, Color.teal.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            content
                .padding(24)
        }
        // 背景が常に暗いので、端末がライトモードでも文字・スピナーを暗い背景向けの色で描く。
        .environment(\.colorScheme, .dark)
    }
}

private enum MasterLoadState {
    case idle
    case loading
    case ready
    case failed(String)

    var isReady: Bool {
        if case .ready = self { true } else { false }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [SavedPlace.self, Municipality.self, VisitedPrefecture.self], inMemory: true)
}
