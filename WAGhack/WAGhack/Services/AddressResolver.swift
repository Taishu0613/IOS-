//
//  AddressResolver.swift
//  WAGhack
//

import CoreLocation
import Foundation
import MapKit

struct AddressResolver {
    static var preferredLocale: Locale { .current }

    func address(for location: CLLocation) async throws -> String {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw AddressResolverError.invalidLocation
        }

        // 端末やシミュレータの言語・地域設定に合わせた住所を取得する。
        request.preferredLocale = Self.preferredLocale

        guard let mapItem = try await request.mapItems.first else {
            throw AddressResolverError.addressNotFound
        }

        if let address = mapItem.addressRepresentations?.fullAddress(
            includingRegion: true,
            singleLine: true
        ), !address.isEmpty {
            return address
        }

        if let address = mapItem.address?.fullAddress, !address.isEmpty {
            return address
        }

        return Self.coordinateFallback(for: location)
    }

    static func coordinateFallback(for location: CLLocation) -> String {
        String(
            format: "現在地（%.5f, %.5f）",
            locale: Locale(identifier: "en_US_POSIX"),
            location.coordinate.latitude,
            location.coordinate.longitude
        )
    }
}

enum AddressResolverError: LocalizedError {
    case addressNotFound
    case invalidLocation

    var errorDescription: String? {
        switch self {
        case .addressNotFound:
            "現在地に対応する住所が見つかりませんでした。"
        case .invalidLocation:
            "取得した位置情報が正しくありません。"
        }
    }
}
