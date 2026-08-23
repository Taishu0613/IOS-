//
//  AddressResolver.swift
//  WAGhack
//

import CoreLocation
import Foundation
import MapKit

struct AddressResolver {
    static var preferredLocale: Locale { .current }
    private static let masterLookupLocale = Locale(identifier: "ja_JP")

    func addresses(for location: CLLocation) async throws -> ResolvedAddresses {
        let localizedAddress = try await address(for: location, locale: Self.preferredLocale)

        guard !Self.preferredLocale.identifier.hasPrefix("ja") else {
            return ResolvedAddresses(
                localizedAddress: localizedAddress,
                japaneseAddressForMatching: localizedAddress
            )
        }

        // 表示は端末設定に追従させつつ、日本語マスタ照合用の住所だけを別途取得する。
        let japaneseAddress = try await address(for: location, locale: Self.masterLookupLocale)
        return ResolvedAddresses(
            localizedAddress: localizedAddress,
            japaneseAddressForMatching: japaneseAddress
        )
    }

    private func address(for location: CLLocation, locale: Locale) async throws -> String {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw AddressResolverError.invalidLocation
        }

        request.preferredLocale = locale

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

struct ResolvedAddresses: Equatable {
    let localizedAddress: String
    let japaneseAddressForMatching: String
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
