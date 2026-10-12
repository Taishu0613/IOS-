import SwiftData
import SwiftUI

struct PrefectureExplorationScreen: View {
    let prefectureCode: String
    let name: String

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Municipality.code) private var municipalities: [Municipality]
    @Query private var savedPlaces: [SavedPlace]
    @Query private var visitedPrefectures: [VisitedPrefecture]
    @State private var store = SavedPlacesStore()
    /// マップのシート内でだけ渡される。プレビューなど渡されない場所では地図を出さない。
    @Environment(SilhouetteMapStore.self) private var silhouetteStore: SilhouetteMapStore?

    var body: some View {
        let summary = store.summary(municipalities: municipalities, savedPlaces: savedPlaces, visitedPrefectures: visitedPrefectures)
        let prefecture = summary.prefectures.first { $0.code == prefectureCode }
        // 行ごとに全市区町村(約2,000件)を探すと、未訪問まで並べたときに件数分くり返すことになるため、先に引けるようにしておく。
        // マスタには同じコードの重複がありうるので、最初の1件を使う。
        let municipalitiesByCode = Dictionary(
            municipalities.filter { $0.prefectureCode == prefectureCode }.map { ($0.code, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        List {
            if let prefecture {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        ExplorationProgressCard(title: "\(name)の市区町村制覇率", progress: prefecture.progress)
                        // 読み込み前も枠は確保し、地図が現れたときに文字の折り返しが変わって揺れないようにする。
                        Group {
                            if let prefectureMap = silhouetteStore?.prefectureMaps[prefectureCode] {
                                // 塗りを隣の踏破率と一致させるため、踏破率と同じ訪問済みコードを使う。
                                SilhouetteMapView(map: prefectureMap, visitedCodes: prefecture.visitedCodes)
                                    .transition(.opacity)
                            }
                        }
                        .frame(width: SilhouetteMapStore.progressMapSize, height: SilhouetteMapStore.progressMapSize)
                        .padding(.top, 8)
                        .animation(.easeOut(duration: 0.25), value: silhouetteStore?.prefectureMaps[prefectureCode] != nil)
                    }
                }
                Section {
                    let entries = prefecture.visitedMunicipalities
                    if entries.isEmpty {
                        Text("マップの「この場所を記録する」から旅をはじめよう")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        if let municipality = municipalitiesByCode[entry.code] {
                            NavigationLink {
                                MunicipalityDetailScreen(municipality: municipality, fallbackName: entry.name)
                            } label: {
                                MunicipalityExplorationRow(name: entry.name, trivia: municipality.famousThingsTrivia, isVisited: true)
                            }
                            .swipeActions {
                                Button("訪問を削除", role: .destructive) {
                                    let visits = savedPlaces.filter { $0.municipality?.code == entry.code }
                                    store.delete(visits, from: modelContext)
                                }
                            }
                        }
                    }
                } header: {
                    Text("訪れた市区町村")
                } footer: {
                    Text("訪れた市区町村がここに集まります。")
                }

                let unvisitedEntries = prefecture.unvisitedMunicipalities
                if !unvisitedEntries.isEmpty {
                    Section {
                        ForEach(unvisitedEntries) { entry in
                            if let municipality = municipalitiesByCode[entry.code] {
                                NavigationLink {
                                    MunicipalityDetailScreen(municipality: municipality, fallbackName: entry.name)
                                } label: {
                                    MunicipalityExplorationRow(name: entry.name, trivia: municipality.famousThingsTrivia, isVisited: false)
                                }
                            }
                        }
                    } header: {
                        Text("まだ訪れていない市区町村")
                    } footer: {
                        Text("みどころを見て、次のよりみち先を探してみよう。")
                    }
                }
            }
        }
        .task { await silhouetteStore?.loadPrefectureMapIfNeeded(code: prefectureCode) }
        .navigationTitle(name)
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

private struct MunicipalityExplorationRow: View {
    let name: String
    let trivia: String
    let isVisited: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 未訪問は色を落とし、訪問済み(集めたもの)との違いがひと目で分かるようにする。
            Image(systemName: isVisited ? "checkmark.seal.fill" : "mappin.circle")
                .foregroundStyle(isVisited ? AnyShapeStyle(.teal) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(trivia.isEmpty ? (isVisited ? "訪問済み" : "未訪問") : trivia)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
    }
}
