import SwiftData
import SwiftUI

struct PrefectureExplorationScreen: View {
    let prefectureCode: String
    let name: String

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Municipality.code) private var municipalities: [Municipality]
    @Query private var savedPlaces: [SavedPlace]
    @State private var store = SavedPlacesStore()

    var body: some View {
        let summary = store.summary(municipalities: municipalities, savedPlaces: savedPlaces)
        let prefecture = summary.prefectures.first { $0.code == prefectureCode }

        List {
            if let prefecture {
                Section {
                    ExplorationProgressCard(title: "\(name)の市区町村制覇率", progress: prefecture.progress)
                }
                Section {
                    let entries = prefecture.visitedMunicipalities
                    if entries.isEmpty {
                        Text("マップの＋から、最初の訪問を記録しよう")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        if let municipality = municipalities.first(where: { $0.code == entry.code }) {
                            NavigationLink {
                                MunicipalityDetailScreen(municipality: municipality, fallbackName: entry.name)
                            } label: {
                                MunicipalityExplorationRow(name: entry.name, trivia: municipality.famousThingsTrivia)
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
                    Text("訪れた市区町村がここに集まります。みどころは訪問後に確認できます。")
                }
            }
        }
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.teal)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(trivia.isEmpty ? "訪問済み" : trivia)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
    }
}
