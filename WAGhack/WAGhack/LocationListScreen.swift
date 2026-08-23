//
//  LocationListScreen.swift
//  WAGhack
//

import SwiftUI
import SwiftData
import CoreLocation

// 画面2: 保存した住所を一覧表示し、タップでマップへジャンプ、スワイプ/Editで削除できる画面
struct LocationListScreen: View {
    @Environment(\.modelContext) private var modelContext
    // マップ画面へのタブ切り替え・フォーカス指示に使う
    @Environment(AppNavigator.self) private var navigator
    // timestampの新しい順に自動で並び替えて取得される
    @Query(sort: \SavedLocation.timestamp, order: .reverse) private var locations: [SavedLocation]
    // 編集モードのオン/オフを自前で管理する（EditButtonだと表示が英語になるため）
    // ボタンとListの両方に同じバインディングを渡す必要があるため、Environmentの既定値には頼らずここで保持する
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            Group {
                if locations.isEmpty {
                    ContentUnavailableView(
                        "保存された住所はありません",
                        systemImage: "mappin.slash",
                        description: Text("マップ画面で追加ボタンを押すと現在地の住所が保存されます")
                    )
                } else {
                    List {
                        ForEach(locations) { location in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.address)
                                    .font(.headline)
                                Text(location.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            // 行全体をタップ判定にする（テキスト部分だけでなく余白もタップ可能に）
                            .contentShape(Rectangle())
                            // 住所をタップしたらマップ画面に切り替えてその場所へ移動させる
                            .onTapGesture {
                                navigator.focus(on: CLLocationCoordinate2D(
                                    latitude: location.latitude,
                                    longitude: location.longitude
                                ))
                            }
                        }
                        .onDelete(perform: deleteLocations)
                    }
                    // タイトルとリストの間に少し余白を入れる
                    .contentMargins(.top, 12, for: .scrollContent)
                    // ここで明示的にeditModeを共有することで、下のボタンとListの編集状態を一致させる
                    .environment(\.editMode, $editMode)
                }
            }
            .navigationTitle("保存した場所")
            .toolbar {
                if !locations.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        // EditButton()は英語表記になるため、日本語の編集/完了ボタンを自作する
                        // マップ画面の「追加」ボタン（アイコンのみ）とスタイルを揃えるため、テキストではなくアイコンで表示する
                        Button {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
                        } label: {
                            Label(
                                editMode.isEditing ? "完了" : "編集",
                                systemImage: editMode.isEditing ? "checkmark" : "pencil"
                            )
                        }
                    }
                }
            }
        }
    }

    // スワイプ削除・Editモードでの削除（−ボタン）の両方から呼ばれる
    private func deleteLocations(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(locations[index])
            }
        }
    }
}

#Preview {
    LocationListScreen()
        .modelContainer(for: SavedLocation.self, inMemory: true)
        .environment(AppNavigator())
}
