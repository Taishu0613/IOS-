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

    var body: some Scene {
        WindowGroup {
            ContentView(modelContainer: sharedModelContainer)
        }
        .modelContainer(sharedModelContainer)
    }
}
