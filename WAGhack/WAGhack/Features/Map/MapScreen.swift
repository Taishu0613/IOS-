//
//  MapScreen.swift
//  WAGhack
//

import MapKit
import SwiftData
import SwiftUI

struct MapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var savedPlaces: [SavedPlace]

    @State private var cameraPosition: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .automatic
    )
    @State private var viewModel = MapViewModel()
    @State private var notice: MapNotice?
    @State private var successfulSaves = 0

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                UserAnnotation()

                ForEach(savedPlaces) { place in
                    Marker(place.address, coordinate: place.coordinate)
                        .tint(.orange)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .navigationTitle("現在地")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await saveCurrentAddress()
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "plus")
                        }
                    }
                    .disabled(viewModel.isBusy)
                    .accessibilityLabel("現在地の住所を保存")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.isLocating || viewModel.isSaving {
                    Label(
                        viewModel.isSaving ? "住所を確認しています" : "現在地を取得しています",
                        systemImage: "location.fill"
                    )
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(in: .capsule)
                    .padding(.bottom, 8)
                }
            }
            .sensoryFeedback(.success, trigger: successfulSaves)
            .task {
                await locateUserIfNeeded()
            }
            .alert(item: $notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func locateUserIfNeeded() async {
        guard viewModel.currentLocation == nil else { return }

        do {
            let location = try await viewModel.updateCurrentLocation()
            focusMap(on: location)
        } catch {
            notice = MapNotice(
                title: "現在地を表示できません",
                message: error.localizedDescription
            )
        }
    }

    private func saveCurrentAddress() async {
        do {
            let place = try await viewModel.makeSavedPlace()
            modelContext.insert(place)

            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw error
            }

            focusMap(on: viewModel.currentLocation)
            successfulSaves += 1
            notice = MapNotice(
                title: "住所を保存しました",
                message: place.address
            )
        } catch {
            notice = MapNotice(
                title: "住所を保存できません",
                message: error.localizedDescription
            )
        }
    }

    private func focusMap(on location: CLLocation?) {
        guard let location else { return }

        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 800,
                    longitudinalMeters: 800
                )
            )
        }
    }
}

private struct MapNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    MapScreen()
        .modelContainer(for: SavedPlace.self, inMemory: true)
}
