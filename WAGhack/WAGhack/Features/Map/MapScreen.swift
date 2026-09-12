import MapKit
import SwiftData
import SwiftUI

struct MapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @Query(sort: \Municipality.code) private var municipalities: [Municipality]

    @State private var cameraPosition: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var viewModel = MapViewModel()
    @State private var selectedPlaceID: PersistentIdentifier?
    @State private var detailPlace: SavedPlace?
    @State private var actionTask: Task<Void, Never>?

    private var selectedPlace: SavedPlace? {
        savedPlaces.first { $0.persistentModelID == selectedPlaceID }
    }

    var body: some View {
        let summary = ExplorationProgressCalculator().summarize(models: municipalities, savedPlaces: savedPlaces)
        let municipality = selectedPlace?.municipality ?? viewModel.currentVisit?.municipality
        let prefecture = summary.prefectures.first { $0.code == municipality?.prefectureCode }
        let isVisited = savedPlaces.contains { $0.municipality?.code == viewModel.currentVisit?.municipality.code && $0.municipality != nil }

        NavigationStack {
            Map(position: $cameraPosition, selection: $selectedPlaceID) {
                UserAnnotation()
                ForEach(savedPlaces) { place in
                    Marker(place.displayName, systemImage: "checkmark", coordinate: place.coordinate)
                        .tint(selectedPlaceID == place.persistentModelID ? .teal : .orange)
                        .tag(place.persistentModelID)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                // safeAreaInsetだとMapの表示領域そのものが縮むため、overlayで地図の上に浮かせる。
                VStack(alignment: .trailing, spacing: 8) {
                    MapProgressHeader(prefecture: prefecture, summary: summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("現在地へ戻る", systemImage: "location.fill") {
                        selectedPlaceID = nil
                        refreshLocation()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .disabled(viewModel.isBusy)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .bottom) {
                // 地図のセーフエリアを確保し、カードでピンや地図の法的表示を隠さない。
                ScrollView {
                    if let selectedPlace {
                        MapSelectedPlaceCard(place: selectedPlace, close: { selectedPlaceID = nil }, showDetails: { detailPlace = selectedPlace })
                    } else {
                        MapCurrentPlaceCard(
                            name: viewModel.currentVisit?.municipality.municipalityName,
                            isVisited: isVisited,
                            statusText: viewModel.statusText,
                            errorMessage: viewModel.errorMessage,
                            result: viewModel.result,
                            save: saveVisit,
                            refresh: refreshLocation
                        )
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 210)
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .sensoryFeedback(.success, trigger: viewModel.successFeedback)
            .sensoryFeedback(.error, trigger: viewModel.errorFeedback)
            .sensoryFeedback(.selection, trigger: selectedPlaceID) { _, newValue in newValue != nil }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.successFeedback)
            .onChange(of: selectedPlaceID) { _, _ in
                if let selectedPlace {
                    focusMap(on: selectedPlace.coordinate)
                }
            }
            .sheet(item: $detailPlace) { place in
                NavigationStack {
                    MunicipalityDetailScreen(municipality: place.municipality, fallbackName: place.address)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("閉じる") { detailPlace = nil }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .task(id: municipalities.count) {
                guard !municipalities.isEmpty, viewModel.currentVisit == nil else { return }
                await viewModel.refresh(municipalities: municipalities)
                if let location = viewModel.currentLocation { focusMap(on: location.coordinate) }
            }
            .onDisappear { actionTask?.cancel() }
        }
    }

    private func refreshLocation() {
        guard !viewModel.isBusy else { return }
        actionTask = Task {
            await viewModel.refresh(municipalities: municipalities)
            if let location = viewModel.currentLocation, selectedPlaceID == nil {
                focusMap(on: location.coordinate)
            }
        }
    }

    private func saveVisit() {
        guard !viewModel.isBusy else { return }
        actionTask = Task {
            await viewModel.save(municipalities: municipalities, context: modelContext)
            if let location = viewModel.currentLocation, selectedPlaceID == nil {
                focusMap(on: location.coordinate)
            }
        }
    }

    private func focusMap(on coordinate: CLLocationCoordinate2D) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate, latitudinalMeters: 1_200, longitudinalMeters: 1_200
            ))
        }
    }
}

#Preview {
    MapScreen().modelContainer(for: [SavedPlace.self, Municipality.self], inMemory: true)
}
