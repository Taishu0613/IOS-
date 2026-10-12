import CoreLocation
import Foundation
import Observation
import os
import SwiftData
import UIKit
import UserNotifications

/// 記録が一度もない市区町村(または都道府県)に入ったら、アプリを閉じていてもローカル通知で知らせる。
/// どちらで知らせるかは`NewMunicipalityAlertMode`でユーザーが選ぶ。
///
/// 地図画面の移動中の判定(`MapViewModel.monitorMunicipalityChanges`)は前面にある間だけ動くため、
/// 裏ではCore Locationの「大幅な位置の変化」(significant-change location service)で起こしてもらう。
/// - 約500m以上の移動でしか届かず、GPSを常時動かさないので電池への負担が小さい。市区町村単位の判定には十分な粒度。
/// - アプリが終了していても、位置が変わればシステムが裏で起動し直してくれる。そのためには起動のたびに
///   監視を開始し直す必要があり、`WAGhackApp`の初期化で`startIfEnabled()`を呼ぶ。
/// - 裏で位置を受け取るには位置情報の「常に」許可が要る。「使用中のみ」では前面にある間しか届かない。
///
/// 却下した案: `CLBackgroundActivitySession`+`CLLocationUpdate.liveUpdates`による常時追跡は、GPSを動かし続け
/// 電池を大きく使う割に、市区町村の判定には精度が過剰なため採らなかった。
///
/// 前面にある間は地図画面が自前の誘いシートを出すので通知は出さない(判定の履歴だけ進める)。
@Observable
final class NewMunicipalityAlertMonitor: NSObject {
    enum Status: Equatable {
        case off
        case active
        /// 位置情報の許可をまだ確認していない(許可のダイアログに答える前)。
        case awaitingLocationPermission
        /// 位置情報が「使用中のみ」で、アプリを閉じている間は判定できない。
        case needsAlwaysLocation
        case locationDenied
        case notificationsDenied
    }

    private static let modeKey = "newMunicipalityAlert.mode"
    /// 市区町村のオン/オフしか無かった版の設定。読み替えたら消す。
    private static let legacyIsEnabledKey = "newMunicipalityAlert.isEnabled"
    /// 市区町村モードの履歴は、市区町村だけだった版と同じキーを使い続ける(出入りの記録を引き継ぐため)。
    private static let municipalityHistoryKey = "newMunicipalityAlert.history"
    private static let prefectureHistoryKey = "newMunicipalityAlert.prefectureHistory"
    /// 判定に使う位置の精度の上限(m)。大幅な位置の変化は基地局・Wi-Fiによる粗い位置で届くことが多く、
    /// 地図画面の自動判定(100m)と同じ基準では大半を捨ててしまうため緩めてある。
    /// これより粗い位置では境界付近で隣の市区町村と取り違えやすい。仮の値で、実機で調整する。
    private static let maximumHorizontalAccuracy: CLLocationAccuracy = 1_000

    /// ユーザーが選んだモード。端末ごとの設定なのでUserDefaultsに保存する。
    private(set) var mode: NewMunicipalityAlertMode
    private(set) var locationAuthorization: CLAuthorizationStatus
    private(set) var notificationAuthorization: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let modelContainer: ModelContainer
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: "com.wakasugi.yorimichi", category: "NewMunicipalityAlert")
    /// 判定中に次の位置が届いても重ねて判定しない。大幅な位置の変化は数分おきにしか届かないため取りこぼしは小さい。
    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    var isEnabled: Bool { mode != .off }

    var status: Status {
        guard isEnabled else { return .off }
        if notificationAuthorization == .denied { return .notificationsDenied }
        switch locationAuthorization {
        case .authorizedAlways: return .active
        case .authorizedWhenInUse: return .needsAlwaysLocation
        case .denied, .restricted: return .locationDenied
        case .notDetermined: return .awaitingLocationPermission
        @unknown default: return .needsAlwaysLocation
        }
    }

    /// CLLocationManagerは生成したスレッドのRunLoopへdelegateを呼ぶため、メインスレッドで生成すること
    /// (このクラスはMainActorに隔離されている)。
    init(modelContainer: ModelContainer, userDefaults: UserDefaults = .standard) {
        self.modelContainer = modelContainer
        self.userDefaults = userDefaults
        mode = Self.loadMode(from: userDefaults)
        locationAuthorization = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    /// オンになっていて許可もあれば監視を始める。裏で起動し直された場合も位置を受け取れるよう、起動直後に呼ぶこと。
    func startIfEnabled() {
        guard isEnabled, CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startMonitoringSignificantLocationChanges()
        default:
            break
        }
    }

    /// 設定の選択・お知らせのボタンから呼ぶ。オンにしたときは、通知と位置情報(「常に」)の許可をこの時点で求める。
    /// 何のための許可かが分かる操作の直後に求めるため、起動時には求めない。
    func setMode(_ mode: NewMunicipalityAlertMode) {
        self.mode = mode
        userDefaults.set(mode.rawValue, forKey: Self.modeKey)
        guard isEnabled else {
            locationManager.stopMonitoringSignificantLocationChanges()
            return
        }
        Task {
            await requestNotificationAuthorization()
            // 未確認・「使用中のみ」のどちらからでも「常に」を求められる。「使用中のみ」からの格上げの確認は
            // OSが1回しか出さず、断られた後は何も表示されないため、その場合は設定画面へ案内する(`Status`)。
            if locationManager.authorizationStatus == .notDetermined
                || locationManager.authorizationStatus == .authorizedWhenInUse {
                locationManager.requestAlwaysAuthorization()
            }
            startIfEnabled()
        }
    }

    /// 保存されたモードを読む。市区町村のオン/オフしか無かった版でオンにしていた場合は、市区町村モードとして引き継ぐ。
    static func loadMode(from userDefaults: UserDefaults) -> NewMunicipalityAlertMode {
        if let rawValue = userDefaults.string(forKey: modeKey) {
            return NewMunicipalityAlertMode(rawValue: rawValue) ?? .off
        }
        let mode: NewMunicipalityAlertMode = userDefaults.bool(forKey: legacyIsEnabledKey) ? .municipality : .off
        userDefaults.set(mode.rawValue, forKey: modeKey)
        userDefaults.removeObject(forKey: legacyIsEnabledKey)
        return mode
    }

    /// 設定アプリで許可を変えて戻ってきた場合に表示を合わせるため、前面に戻るたびに呼ぶ。
    func refreshNotificationAuthorization() async {
        notificationAuthorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func requestNotificationAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("通知の許可を求められませんでした: \(error.localizedDescription, privacy: .public)")
        }
        await refreshNotificationAuthorization()
    }

    private func check(_ location: CLLocation) async {
        let mode = mode
        guard mode != .off, !isChecking,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= Self.maximumHorizontalAccuracy
        else { return }
        isChecking = true
        // 裏で起こされた場合、位置を渡された後すぐに停止されることがあるため、住所の確認(通信あり)を
        // 終えるまでの実行時間を願い出る。
        beginBackgroundTime()
        defer {
            isChecking = false
            endBackgroundTime()
        }

        do {
            let context = modelContainer.mainContext
            let municipalities = try context.fetch(FetchDescriptor<Municipality>(predicate: #Predicate { !$0.isPrefecture }))
            // マスタの同期前(初回起動の途中など)は判定できない。
            guard !municipalities.isEmpty else { return }

            let addresses = try await AddressResolver().addresses(for: location)
            guard let municipality = MunicipalityMatcher().match(
                japaneseAddress: addresses.japaneseAddressForMatching, municipalities: municipalities
            ) else {
                logger.notice("現在地に対応する市区町村がマスタに見つかりませんでした")
                return
            }

            // 住所の確認を待つ間に記録された場合も反映するため、記録は判定の直前に読む。
            let area = try alertArea(for: municipality, mode: mode, context: context)
            let decision = NewMunicipalityAlertPolicy().decide(
                areaCode: area.code,
                recordedCodes: area.recordedCodes,
                history: loadHistory(for: mode),
                canPresentNotification: UIApplication.shared.applicationState != .active,
                now: .now
            )
            saveHistory(decision.updatedHistory, for: mode)
            if decision.shouldNotify {
                try await postNotification(identifier: area.notificationIdentifier, areaName: area.name)
            }
        } catch {
            // 裏の処理なのでユーザーには見せない。次に位置が届いたときに判定し直す。
            logger.error("初めての区域の判定に失敗しました: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct AlertArea {
        let code: String
        let name: String
        let recordedCodes: Set<String>
        let notificationIdentifier: String
    }

    /// モードに合わせて、判定する区域と記録済みとみなす区域を決める。
    /// 都道府県は地図画面の「初めての都道府県」と同じく、県内の市区町村の記録か都道府県だけの記録があれば記録済みとする。
    private func alertArea(for municipality: Municipality, mode: NewMunicipalityAlertMode, context: ModelContext) throws -> AlertArea {
        let savedPlaces = try context.fetch(FetchDescriptor<SavedPlace>())
        switch mode {
        case .prefecture:
            let explicitCodes = try context.fetch(FetchDescriptor<VisitedPrefecture>()).map(\.code)
            return AlertArea(
                code: municipality.prefectureCode,
                name: municipality.prefectureName,
                recordedCodes: Set(savedPlaces.compactMap { $0.municipality?.prefectureCode } + explicitCodes),
                notificationIdentifier: "newPrefecture.\(municipality.prefectureCode)"
            )
        case .municipality, .off:
            return AlertArea(
                code: municipality.code,
                name: municipality.prefectureName + municipality.municipalityName,
                recordedCodes: Set(savedPlaces.compactMap { $0.municipality?.code }),
                notificationIdentifier: "newMunicipality.\(municipality.code)"
            )
        }
    }

    private func postNotification(identifier: String, areaName: String) async throws {
        let content = UNMutableNotificationContent()
        // タイトルは付けない。アプリ名(よりみち)はOSが添えるため、本文の一文だけで伝わる。
        content.body = NewMunicipalityAlertMessage.body(areaName: areaName)
        content.sound = .default
        content.threadIdentifier = "newMunicipality"
        // 同じ区域の通知が残っていれば置き換える。タップするとアプリが開き、地図画面が現在地を確認して誘いシートを出す。
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }

    private static func historyKey(for mode: NewMunicipalityAlertMode) -> String {
        mode == .prefecture ? prefectureHistoryKey : municipalityHistoryKey
    }

    private func loadHistory(for mode: NewMunicipalityAlertMode) -> NewMunicipalityAlertHistory {
        guard let data = userDefaults.data(forKey: Self.historyKey(for: mode)) else { return NewMunicipalityAlertHistory() }
        do {
            return try JSONDecoder().decode(NewMunicipalityAlertHistory.self, from: data)
        } catch {
            // 壊れていても失うのは再通知の抑止だけなので、空から始め直す。
            logger.error("通知の履歴を読めませんでした: \(error.localizedDescription, privacy: .public)")
            return NewMunicipalityAlertHistory()
        }
    }

    private func saveHistory(_ history: NewMunicipalityAlertHistory, for mode: NewMunicipalityAlertMode) {
        do {
            userDefaults.set(try JSONEncoder().encode(history), forKey: Self.historyKey(for: mode))
        } catch {
            logger.error("通知の履歴を保存できませんでした: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func beginBackgroundTime() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "NewMunicipalityAlert") { [weak self] in
            // 時間切れ。判定の途中でも終えないとアプリが強制終了される。
            self?.endBackgroundTime()
        }
    }

    private func endBackgroundTime() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}

// delegateはメインスレッドで生成したCLLocationManagerから、メインスレッドで呼ばれる。
extension NewMunicipalityAlertMonitor: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthorization = manager.authorizationStatus
        startIfEnabled()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { await check(location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        logger.error("大幅な位置の変化を受け取れませんでした: \(error.localizedDescription, privacy: .public)")
    }
}
