//
//  ContentView.swift
//  WAGhack
//
//  Created by 若杉泰周 on 2026/08/23.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    private let modelContainer: ModelContainer?

    @State private var selectedTab: AppTab = .map
    @State private var masterLoadState: MasterLoadState

    init(modelContainer: ModelContainer? = nil) {
        self.modelContainer = modelContainer
        _masterLoadState = State(initialValue: modelContainer == nil ? .ready : .idle)
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab("マップ", systemImage: "map", value: .map) {
                    MapScreen()
                }

                Tab("市区町村", systemImage: "building.2", value: .savedPlaces) {
                    SavedPlacesScreen()
                }
            }
            .disabled(masterLoadState.isBlocking)

            masterLoadOverlay
        }
        .task {
            guard case .idle = masterLoadState else { return }
            await loadMunicipalityMaster()
        }
    }

    @ViewBuilder
    private var masterLoadOverlay: some View {
        switch masterLoadState {
        case .ready:
            EmptyView()
        case .idle, .loading:
            MasterLoadBackdrop {
                ProgressView("市区町村データを準備しています")
            }
        case .failed(let message):
            MasterLoadBackdrop {
                ContentUnavailableView {
                    Label("データを準備できません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("再試行") {
                        Task {
                            await loadMunicipalityMaster()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func loadMunicipalityMaster() async {
        guard let modelContainer else {
            masterLoadState = .ready
            return
        }

        masterLoadState = .loading

        do {
            let records = try MunicipalityMasterImporter().records()
            let masterStore = MunicipalityMasterStore(modelContainer: modelContainer)
            try await masterStore.synchronize(records: records)
            masterLoadState = .ready
        } catch {
            masterLoadState = .failed(error.localizedDescription)
        }
    }
}

private struct MasterLoadBackdrop<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            content
                .padding(24)
        }
    }
}

private enum MasterLoadState {
    case idle
    case loading
    case ready
    case failed(String)

    var isBlocking: Bool {
        switch self {
        case .idle, .loading, .failed:
            true
        case .ready:
            false
        }
    }
}

private enum AppTab: Hashable {
    case map
    case savedPlaces
}

#Preview {
    ContentView()
        .modelContainer(for: [SavedPlace.self, Municipality.self], inMemory: true)
}
