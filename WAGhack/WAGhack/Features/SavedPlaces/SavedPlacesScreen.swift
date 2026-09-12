import SwiftData
import SwiftUI

struct SavedPlacesScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @Query(sort: \Municipality.code) private var municipalities: [Municipality]
    @State private var store = SavedPlacesStore()

    var body: some View {
        let summary = store.summary(municipalities: municipalities, savedPlaces: savedPlaces)
        let excludedPlaces = store.excludedPlaces(savedPlaces, summary: summary)

        NavigationStack {
            List {
                Section {
                    ExplorationProgressCard(
                        title: "日本の訪れた都道府県",
                        progress: summary.prefectureProgress,
                        unit: "都道府県",
                        emphasizesCount: true
                    )
                    Label(
                        "\(summary.progress.visited) / \(summary.progress.total) 市区町村を訪問",
                        systemImage: "building.2"
                    )
                } footer: {
                    Text("1つでも市区町村を訪れた都道府県を制覇としてカウントします。政令指定都市は区単位で数えます。")
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
            }
            .navigationTitle("旅の記録")
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
}

#Preview {
    SavedPlacesScreen()
        .modelContainer(for: [SavedPlace.self, Municipality.self], inMemory: true)
}
