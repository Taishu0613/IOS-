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
                        "保存した住所はありません",
                        systemImage: "bookmark.slash",
                        description: Text("マップ右上の＋ボタンから現在地を保存できます。")
                    )
                } else {
                    List {
                        ForEach(savedPlaces) { place in
                            SavedPlaceRow(place: place)
                        }
                        .onDelete(perform: deletePlaces)
                    }
                }
            }
            .navigationTitle("保存した住所")
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
        VStack(alignment: .leading, spacing: 8) {
            Label(place.address, systemImage: "mappin.and.ellipse")
                .font(.headline)

            Text(place.savedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(
                "緯度 \(place.latitude, format: .number.precision(.fractionLength(5)))・経度 \(place.longitude, format: .number.precision(.fractionLength(5)))"
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SavedPlacesScreen()
        .modelContainer(for: SavedPlace.self, inMemory: true)
}
