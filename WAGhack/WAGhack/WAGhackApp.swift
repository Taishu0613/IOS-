//
//  WAGhackApp.swift
//  WAGhack
//
//  Created by 若杉泰周 on 2026/08/23.
//

import SwiftUI
import SwiftData

@main
struct WAGhackApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SavedPlace.self,
            Municipality.self,
            VisitedPrefecture.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("SwiftDataの準備に失敗しました: \(error)")
        }
    }()

    /// 初めての市区町村に入ったときの通知。位置の変化で裏で起動し直された場合も位置を受け取れるよう、
    /// 画面(Scene)が作られるのを待たずアプリの初期化で監視を始め直す。
    @State private var newMunicipalityAlert: NewMunicipalityAlertMonitor

    init() {
        let monitor = NewMunicipalityAlertMonitor(modelContainer: sharedModelContainer)
        monitor.startIfEnabled()
        _newMunicipalityAlert = State(initialValue: monitor)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(modelContainer: sharedModelContainer)
                .environment(newMunicipalityAlert)
        }
        .modelContainer(sharedModelContainer)
    }
}
