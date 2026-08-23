//
//  SavedPlacesScreen.swift
//  WAGhack
//

import SwiftData
import SwiftUI

struct SavedPlacesScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var savedPlaces: [SavedPlace]

    @State private var deletionErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if savedPlaces.isEmpty {
                    ContentUnavailableView(
                        "保存した市区町村はありません",
                        systemImage: "building.2.crop.circle",
                        description: Text("マップ右上の＋ボタンから現在地の市区町村を保存できます。")
                    )
                } else {
                    List {
                        ForEach(savedPlaces) { place in
                            NavigationLink {
                                MunicipalityDetailScreen(place: place)
                            } label: {
                                SavedPlaceRow(place: place)
                            }
                        }
                        .onDelete(perform: deletePlaces)
                    }
                }
            }
            .navigationTitle("保存した市区町村")
            .toolbar {
                if !savedPlaces.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
            .alert(
                "削除できませんでした",
                isPresented: Binding(
                    get: { deletionErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            deletionErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deletionErrorMessage ?? "不明なエラーが発生しました。")
            }
        }
    }

    private func deletePlaces(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(savedPlaces[index])
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            deletionErrorMessage = error.localizedDescription
        }
    }
}

private struct SavedPlaceRow: View {
    let place: SavedPlace

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(place.displayName, systemImage: "building.2")
                .font(.headline)

            if let prefectureName = place.municipality?.prefectureName {
                Text(prefectureName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(place.savedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct MunicipalityDetailScreen: View {
    let place: SavedPlace

    private var municipality: Municipality? {
        place.municipality
    }

    var body: some View {
        List {
            Section("市区町村") {
                LabeledContent("都道府県", value: municipality?.prefectureName ?? "")
                LabeledContent("市区町村", value: municipality?.municipalityName ?? place.address)
                LabeledContent("行政区域コード", value: municipality?.code ?? "")
            }

            TriviaSection(
                title: "豆知識（歴史）",
                content: municipality?.historyTrivia ?? ""
            )

            TriviaSection(
                title: "豆知識（有名なもの）",
                content: municipality?.famousThingsTrivia ?? ""
            )
        }
        .navigationTitle(municipality?.municipalityName ?? "市区町村")
        .navigationBarTitleDisplayMode(.inline)
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

#Preview {
    SavedPlacesScreen()
        .modelContainer(for: [SavedPlace.self, Municipality.self], inMemory: true)
}
