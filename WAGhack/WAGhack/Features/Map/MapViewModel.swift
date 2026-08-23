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
    private let municipalityMatcher: MunicipalityMatcher

    private(set) var currentLocation: CLLocation?
    private(set) var isLocating = false
    private(set) var isSaving = false

    init() {
        self.locationService = LocationService()
        self.addressResolver = AddressResolver()
        self.municipalityMatcher = MunicipalityMatcher()
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

    func makeMunicipalityVisit(from municipalities: [Municipality]) async throws -> MunicipalityVisit {
        isSaving = true
        defer { isSaving = false }

        let location = try await locationService.currentLocation()
        currentLocation = location

        let addresses = try await addressResolver.addresses(for: location)
        guard let municipality = municipalityMatcher.match(
            japaneseAddress: addresses.japaneseAddressForMatching,
            municipalities: municipalities
        ) else {
            throw MunicipalityVisitError.municipalityNotFound
        }

        return MunicipalityVisit(
            localizedAddress: addresses.localizedAddress,
            location: location,
            municipality: municipality
        )
    }
}

struct MunicipalityVisit {
    let localizedAddress: String
    let location: CLLocation
    let municipality: Municipality
}

enum MunicipalityVisitError: LocalizedError {
    case municipalityNotFound

    var errorDescription: String? {
        switch self {
        case .municipalityNotFound:
            "現在地に対応する市区町村がマスタに見つかりませんでした。"
        }
    }
}
