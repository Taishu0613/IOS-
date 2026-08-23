//
//  WAGhackTests.swift
//  WAGhackTests
//
//  Created by 若杉泰周 on 2026/08/23.
//

import Testing
import CoreLocation
import Foundation
@testable import WAGhack

struct WAGhackTests {
    @Test func 住所変換では端末の現在ロケールを使用する() {
        #expect(AddressResolver.preferredLocale.identifier == Locale.current.identifier)
    }

    @Test func savedPlaceが住所と座標を保持する() {
        let place = SavedPlace(
            address: "東京都千代田区千代田1-1",
            latitude: 35.685175,
            longitude: 139.752800
        )

        #expect(place.address == "東京都千代田区千代田1-1")
        #expect(place.coordinate.latitude == 35.685175)
        #expect(place.coordinate.longitude == 139.752800)
    }

    @Test func 住所が取得できない場合は座標を表示できる文字列にする() {
        let location = CLLocation(latitude: 35.685175, longitude: 139.752800)

        let fallback = AddressResolver.coordinateFallback(for: location)

        #expect(fallback == "現在地（35.68518, 139.75280）")
    }
}
