//
//  LocationService.swift
//  WAGhack
//

import CoreLocation
import Foundation

@MainActor
final class LocationService {
    private let locationManager = CLLocationManager()

    func currentLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationServiceError.servicesDisabled
        }

        switch locationManager.authorizationStatus {
        case .denied:
            throw LocationServiceError.authorizationDenied
        case .restricted:
            throw LocationServiceError.authorizationRestricted
        default:
            break
        }

        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        // iOS 17以降のAsyncSequenceを使い、必要な1件を得た時点で監視を終了する。
        for try await update in CLLocationUpdate.liveUpdates(.default) {
            if update.authorizationDenied || update.authorizationDeniedGlobally {
                throw LocationServiceError.authorizationDenied
            }

            if update.authorizationRestricted {
                throw LocationServiceError.authorizationRestricted
            }

            if update.locationUnavailable {
                throw LocationServiceError.locationUnavailable
            }

            if let location = update.location, location.horizontalAccuracy >= 0 {
                return location
            }
        }

        throw LocationServiceError.locationUnavailable
    }
}

enum LocationServiceError: LocalizedError {
    case authorizationDenied
    case authorizationRestricted
    case locationUnavailable
    case servicesDisabled

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "位置情報の使用が許可されていません。設定アプリから位置情報を許可してください。"
        case .authorizationRestricted:
            "この端末では位置情報の使用が制限されています。"
        case .locationUnavailable:
            "現在地を取得できませんでした。屋外など、位置情報を取得しやすい場所で再度お試しください。"
        case .servicesDisabled:
            "端末の位置情報サービスがオフになっています。"
        }
    }
}
