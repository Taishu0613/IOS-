//
//  AppNavigator.swift
//  WAGhack
//

import CoreLocation
import Observation

// TabViewで切り替える2つの画面を表す
enum AppTab: Hashable {
    case map
    case list
}

// CLLocationCoordinate2DはEquatableではないため、onChangeで検知できるように緯度経度だけを持つラッパーを用意する
struct FocusTarget: Equatable {
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// マップ画面とリスト画面をまたいだ状態（今どのタブにいるか、地図をどこにフォーカスするか）を管理するクラス
@Observable
final class AppNavigator {
    var selectedTab: AppTab = .map
    // リスト画面で住所がタップされたときに、その座標を一時的に保持する
    var focusTarget: FocusTarget?

    // リスト画面から呼ばれる: 指定した座標にマップを移動させつつ、マップタブへ切り替える
    func focus(on coordinate: CLLocationCoordinate2D) {
        focusTarget = FocusTarget(latitude: coordinate.latitude, longitude: coordinate.longitude)
        selectedTab = .map
    }
}
