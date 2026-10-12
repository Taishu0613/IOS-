import SwiftData
import SwiftUI

struct SavedPlacesScreen: View {
    /// 踏破率の集計。持ち主の`MapScreen`が記録の増減に合わせて計算し直したものを受け取る。
    ///
    /// この画面はシートを広げるたびに作り直される。以前はここで全市区町村(約2,000件)を`@Query`で
    /// 読み込んで集計し直しており、それだけでメインスレッドが約0.1秒止まり(シミュレータで計測)、
    /// シートが広がるアニメーションが引っかかって見えていた。同じ集計を2か所で持たないためにも受け取る形にしている。
    let summary: ExplorationSummary

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @State private var store = SavedPlacesStore()
    /// マップのシート内でだけ渡される。プレビューなど渡されない場所では地図を出さない。
    @Environment(SilhouetteMapStore.self) private var silhouetteStore: SilhouetteMapStore?
    /// 未訪問の都道府県は数が多い(最大47件)ため、最初は畳んでおき、記録の一覧を埋もれさせない。
    @State private var isUnvisitedPrefecturesExpanded = false

    var body: some View {
        let excludedPlaces = store.excludedPlaces(savedPlaces, summary: summary)

        // マップのシート内NavigationStackにpushされる前提なので、自前のNavigationStackは持たない。
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    ExplorationProgressCard(
                        title: "日本の訪れた都道府県",
                        progress: summary.prefectureProgress,
                        unit: "都道府県",
                        emphasizesCount: true
                    )
                    // 読み込み前も枠は確保し、地図が現れたときに文字の折り返しが変わって揺れないようにする。
                    Group {
                        if let japanMap = silhouetteStore?.japanMap {
                            SilhouetteMapView(map: japanMap, visitedCodes: Set(summary.visitedPrefectures.map(\.code)))
                                .transition(.opacity)
                        }
                    }
                    .frame(width: SilhouetteMapStore.progressMapSize, height: SilhouetteMapStore.progressMapSize)
                    .padding(.top, 8)
                    .animation(.easeOut(duration: 0.25), value: silhouetteStore?.japanMap != nil)
                }
                Label(
                    "\(summary.progress.visited) / \(summary.progress.total) 市区町村を訪問",
                    systemImage: "building.2"
                )
            } footer: {
                Text("都道府県を記録するか、1つでも市区町村を訪れると制覇としてカウントします。政令指定都市は区単位で数えます。")
            }

            if summary.visitedPrefectures.isEmpty {
                Section {
                    Label("マップの「この場所を記録する」から旅をはじめよう", systemImage: "location.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section("記録した都道府県") {
                ForEach(summary.visitedPrefectures) { prefecture in
                    NavigationLink {
                        PrefectureExplorationScreen(prefectureCode: prefecture.code, name: prefecture.name)
                    } label: {
                        PrefectureExplorationRow(prefecture: prefecture)
                    }
                }
            }

            let unvisitedPrefectures = summary.unvisitedPrefectures
            if !unvisitedPrefectures.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $isUnvisitedPrefecturesExpanded) {
                        ForEach(unvisitedPrefectures) { prefecture in
                            NavigationLink {
                                PrefectureExplorationScreen(prefectureCode: prefecture.code, name: prefecture.name)
                            } label: {
                                LabeledContent(prefecture.name, value: "\(prefecture.progress.total) 市区町村")
                            }
                        }
                    } label: {
                        LabeledContent("まだ訪れていない都道府県", value: "\(unvisitedPrefectures.count)")
                    }
                } footer: {
                    Text("まだ訪れていない場所のみどころも見られます。次のよりみち先を探してみよう。")
                }
            }

            if !excludedPlaces.isEmpty {
                Section {
                    ForEach(excludedPlaces) { place in
                        NavigationLink {
                            MunicipalityDetailScreen(municipality: place.municipality, fallbackName: place.address)
                        } label: {
                            Text(place.displayName)
                        }
                    }
                    .onDelete { offsets in
                        store.delete(offsets.map { excludedPlaces[$0] }, from: modelContext)
                    }
                } header: {
                    Text("踏破率に含まれない記録")
                } footer: {
                    Text("区を特定できない市の記録や、市区町村が未確定の記録です。訪問記録は引き続き確認・削除できます。")
                }
            }

            NewMunicipalityAlertSettingsSection()

            // マップの市区町村ポリゴンの出典(CC BY 4.0の表示義務)。地図の上は操作部品で埋まっているため、ここに置く。
            Section {
                BoundaryAttributionView()
            } header: {
                Text("地図の境界データ")
            }
        }
        .task { await silhouetteStore?.loadJapanMapIfNeeded() }
        .navigationTitle("旅の記録")
        .navigationBarTitleDisplayMode(.inline)
        .alert("削除できませんでした", isPresented: Binding(
            get: { store.deletionErrorMessage != nil },
            set: { if !$0 { store.deletionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.deletionErrorMessage ?? "不明なエラーが発生しました。")
        }
    }
}

#Preview {
    NavigationStack {
        SavedPlacesScreen(summary: ExplorationSummary(prefectures: [], eligibleCodes: []))
    }
    .modelContainer(for: [SavedPlace.self, Municipality.self, VisitedPrefecture.self], inMemory: true)
}
