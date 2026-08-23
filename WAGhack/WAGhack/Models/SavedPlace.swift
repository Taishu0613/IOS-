//
//  SavedPlace.swift
//  WAGhack
//

import CoreLocation
import Foundation
import SwiftData

@Model
final class SavedPlace {
    var address: String
    var latitude: Double
    var longitude: Double
    var savedAt: Date
    var municipality: Municipality?

    init(
        address: String,
        latitude: Double,
        longitude: Double,
        savedAt: Date = .now,
        municipality: Municipality? = nil
    ) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.savedAt = savedAt
        self.municipality = municipality
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayName: String {
        municipality?.municipalityName ?? address
    }

    func update(with visit: MunicipalityVisit) {
        address = visit.localizedAddress
        latitude = visit.location.coordinate.latitude
        longitude = visit.location.coordinate.longitude
        savedAt = .now
        municipality = visit.municipality
    }
}
