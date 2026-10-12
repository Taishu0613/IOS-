import SwiftUI

struct MunicipalityDetailScreen: View {
    let municipality: Municipality?
    let fallbackName: String

    /// マップのシート内でだけ渡される。プレビューなど渡されない場所では形を出さない。
    @Environment(SilhouetteMapStore.self) private var silhouetteStore: SilhouetteMapStore?

    /// 形を描く枠の高さ。
    private static let shapeHeight: CGFloat = 220
    /// 形の上下の余白。リスト先頭の透明な行もこの分を含めた高さにして、最初は形とカードが重ならないようにする。
    private static let shapeVerticalPadding: CGFloat = 16

    /// 背景に形を敷くか。Storeが渡されない場所(プレビューなど)や市区町村が不明なときは敷かない。
    private var showsShape: Bool {
        municipality?.code != nil && silhouetteStore != nil
    }

    var body: some View {
        List {
            if let code = municipality?.code, showsShape {
                Section {
                    // 形そのものは背景に固定して描き、ここには同じ高さの透明な行だけを置く。
                    // スクロールするとこの行が上へ抜け、下のカードが形の上に覆い被さっていく。
                    Color.clear
                        .frame(height: Self.shapeHeight + Self.shapeVerticalPadding * 2)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        // 読み込みはこの行に付ける(Listの外側に付けるより、表示される市区町村と対応が明確なため)。
                        .task { await silhouetteStore?.loadMunicipalityMapIfNeeded(code: code) }
                        .accessibilityHidden(true)
                }
                // 先頭のセクションの上に空く標準の余白を詰め、形の位置と透明な行の位置をそろえる。
                .listSectionMargins(.top, 0)
            }

            Section("市区町村") {
                LabeledContent("都道府県", value: municipality?.prefectureName ?? "")
                LabeledContent("市区町村", value: municipality?.municipalityName ?? fallbackName)
                LabeledContent("行政区域コード", value: municipality?.code ?? "")
            }

            TriviaSection(
                title: "みどころ",
                content: municipality?.famousThingsTrivia ?? ""
            )

            TriviaSection(
                title: "怪奇・都市伝説",
                content: municipality?.historyTrivia ?? ""
            )

        }
        .background(alignment: .top) {
            if showsShape {
                shapeBackground
            }
        }
        // 標準の背景を消して、背景に敷いた形がカードの間から見えるようにする(背景色は`shapeBackground`側で塗る)。
        .scrollContentBackground(showsShape ? .hidden : .automatic)
        .navigationTitle(municipality?.municipalityName ?? "市区町村")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension MunicipalityDetailScreen {
    /// リストの後ろに固定する、市区町村の形。スクロールしても動かず、カードが上を流れていく。
    private var shapeBackground: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            if let code = municipality?.code, let map = silhouetteStore?.municipalityMaps[code] {
                SilhouetteOutlineView(map: map)
                    .frame(height: Self.shapeHeight)
                    .padding(.horizontal, 24)
                    .padding(.vertical, Self.shapeVerticalPadding)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: municipality.flatMap { silhouetteStore?.municipalityMaps[$0.code] } != nil)
    }
}

private struct TriviaSection: View {
    let title: String
    let content: String

    var body: some View {
        Section(title) {
            // マスタが空欄の場合も「情報なし」へ置き換えず、空欄のまま表示する。
            Text(content)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }
}

