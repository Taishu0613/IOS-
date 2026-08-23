//
//  SavedLocation.swift
//  WAGhack
//

import Foundation
import SwiftData

// リスト画面に表示・保存する「保存した場所」1件分のデータモデル
@Model
final class SavedLocation {
    // 逆ジオコーディングで得られた住所文字列
    var address: String
    // マップ画面へジャンプする際にカメラの中心として使う座標
    var latitude: Double
    var longitude: Double
    // 保存した日時（リストの並び替えにも使用）
    var timestamp: Date

    init(address: String, latitude: Double, longitude: Double, timestamp: Date) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}
