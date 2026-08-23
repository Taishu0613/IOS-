//
//  ContentView.swift
//  WAGhack
//

import SwiftUI
import SwiftData

// アプリのルート画面: マップ画面とリスト画面をタブで切り替える
struct ContentView: View {
    // どちらのタブにいるか／マップをどこにフォーカスするかを2画面で共有する
    @State private var navigator = AppNavigator()

    var body: some View {
        TabView(selection: Binding(
            get: { navigator.selectedTab },
            set: { navigator.selectedTab = $0 }
        )) {
            MapScreen()
                .tabItem {
                    Label("マップ", systemImage: "map")
                }
                .tag(AppTab.map)
            LocationListScreen()
                .tabItem {
                    Label("保存した場所", systemImage: "list.bullet")
                }
                .tag(AppTab.list)
        }
        // 子画面（MapScreen/LocationListScreen）からnavigatorを参照できるようにする
        .environment(navigator)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SavedLocation.self, inMemory: true)
}
