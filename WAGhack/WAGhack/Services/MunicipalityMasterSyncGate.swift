//
//  MunicipalityMasterSyncGate.swift
//  WAGhack
//

import CryptoKit
import Foundation

/// 市区町村マスタCSVが、前回SwiftDataへ同期した時から変わっているかを判定するゲート。
///
/// 同期(CSVの全件読み込みと既存データとの比較)は、中身に変更が無くても時間がかかり、その間は
/// 読み込み画面を出すしかない。そこでCSVの中身から作った指紋(fingerprint)を同期の成功時に保存し、
/// 次回起動時に一致すれば同期ごと飛ばして、読み込み画面を出さずに地図へ進めるようにする。
///
/// ビルド番号ではなく中身のハッシュを使うのは、ビルド番号を上げずにCSVだけ差し替えることがあり、
/// ビルド番号で判定すると古いマスタのまま同期が飛ばされてしまうため。
struct MunicipalityMasterSyncGate {
    /// CSVの中身は同じでも、読み込み・変換の仕方(列の対応やMunicipalityへの写し方)を変えた時は
    /// この値を上げること。上げないと、既存ユーザーの端末では同期が飛ばされて変更が反映されない。
    static let formatVersion = 1

    private static let syncedFingerprintKey = "municipalityMaster.syncedFingerprint"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    static func fingerprint(of csvData: Data) -> String {
        let hash = SHA256.hash(data: csvData)
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(formatVersion)-\(hash)"
    }

    /// - Parameters:
    ///   - fingerprint: 現在アプリに同梱しているCSVの指紋。CSVを読めなかった場合はnil。
    ///   - storedMunicipalityCount: SwiftDataに保存済みの市区町村数。
    /// - Returns: 同期(と読み込み画面)が必要ならtrue。
    func needsSynchronization(fingerprint: String?, storedMunicipalityCount: Int) -> Bool {
        // CSVを読めない場合は同期に進ませ、そこで出る正式なエラーを読み込み画面に表示させる。
        guard let fingerprint else { return true }
        // 指紋が一致していても保存済みのマスタが空なら同期する。ストアだけが作り直された場合の保険。
        guard storedMunicipalityCount > 0 else { return true }
        return userDefaults.string(forKey: Self.syncedFingerprintKey) != fingerprint
    }

    /// 同期が保存まで成功した後にだけ呼ぶこと。失敗時に記録すると、次回以降も不完全なマスタのまま同期が飛ばされる。
    func markSynchronized(fingerprint: String) {
        userDefaults.set(fingerprint, forKey: Self.syncedFingerprintKey)
    }
}
