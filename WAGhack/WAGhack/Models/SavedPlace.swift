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

    init(
        address: String,
        latitude: Double,
        longitude: Double,
        savedAt: Date = .now
    ) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.savedAt = savedAt
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
