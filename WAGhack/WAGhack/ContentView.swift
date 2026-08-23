//
//  ContentView.swift
//  WAGhack
//
//  Created by 若杉泰周 on 2026/08/23.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab: AppTab = .map

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("マップ", systemImage: "map", value: .map) {
                MapScreen()
            }

            Tab("保存済み", systemImage: "bookmark", value: .savedPlaces) {
                SavedPlacesScreen()
            }
        }
    }
}

private enum AppTab: Hashable {
    case map
    case savedPlaces
}

#Preview {
    ContentView()
        .modelContainer(for: SavedPlace.self, inMemory: true)
}
