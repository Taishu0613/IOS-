//
//  LocationService.swift
//  WAGhack
//

import CoreLocation
import Foundation
import os

@MainActor
final class LocationService {
    private let locationManager = CLLocationManager()
    private let logger = Logger(subsystem: "com.wakasugi.yorimichi", category: "Location")

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

    /// 画面を開いている間の移動を見張るための、精度の足りた現在地の列。呼び出し側のループを抜ける
    /// (タスクがキャンセルされる)と監視も止まる。
    ///
    /// - 受け手の処理(住所の確認は通信を挟む)が終わるまでに届いた位置は最新の1件だけ残す。古い位置を
    ///   順に処理していくと、移動に対して判定がどんどん遅れていくため。
    /// - 許可が無い・取り消された場合は黙って終了する。ユーザーへの案内は現在地ボタン側の`currentLocation()`が担う。
    /// - 静止中はCore Locationが自動で更新を止めるため、止まっている間に電池を使い続けることはない。
    func accurateLocationUpdates(maximumHorizontalAccuracy: CLLocationAccuracy) -> AsyncStream<CLLocation> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { [logger] in
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.default) {
                        if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                            break
                        }
                        guard let location = update.location,
                              location.horizontalAccuracy >= 0,
                              location.horizontalAccuracy <= maximumHorizontalAccuracy
                        else { continue }
                        continuation.yield(location)
                    }
                } catch {
                    logger.error("現在地の監視が終了しました: \(error.localizedDescription, privacy: .public)")
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
