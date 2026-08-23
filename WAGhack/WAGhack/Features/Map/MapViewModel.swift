//
//  MapViewModel.swift
//  WAGhack
//

import CoreLocation
import Observation

@MainActor
@Observable
final class MapViewModel {
    private let locationService: LocationService
    private let addressResolver: AddressResolver

    private(set) var currentLocation: CLLocation?
    private(set) var isLocating = false
    private(set) var isSaving = false

    init() {
        self.locationService = LocationService()
        self.addressResolver = AddressResolver()
    }

    var isBusy: Bool {
        isLocating || isSaving
    }

    func updateCurrentLocation() async throws -> CLLocation {
        isLocating = true
        defer { isLocating = false }

        let location = try await locationService.currentLocation()
        currentLocation = location
        return location
    }

    func makeSavedPlace() async throws -> SavedPlace {
        isSaving = true
        defer { isSaving = false }

        let location = try await locationService.currentLocation()
        currentLocation = location

        let address = try await addressResolver.address(for: location)
        return SavedPlace(
            address: address,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
}
