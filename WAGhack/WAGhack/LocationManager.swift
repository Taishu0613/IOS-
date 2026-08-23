//
//  LocationManager.swift
//  WAGhack
//

import CoreLocation
import Observation

// CLLocationManagerをSwiftUIから使いやすくラップしたクラス
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    // 最新の現在地（未取得のうちはnil）
    var currentLocation: CLLocationCoordinate2D?
    // 位置情報の利用許可状態
    var authorizationStatus: CLAuthorizationStatus

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // 位置情報取得許可のリクエスト
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    // 位置情報取得開始
    func startUpdating() {
        manager.startUpdatingLocation()
    }

    // 位置情報取得許可状態の変更時イベント
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        // 使用中のみ許可 or 常に許可 の場合は位置情報取得開始
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    // 位置情報が更新されるたびに呼ばれる: 最新の1件をcurrentLocationに反映
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
    }

    // 取得に失敗した場合（機内モードなど）は握りつぶさずログに出す
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
}
