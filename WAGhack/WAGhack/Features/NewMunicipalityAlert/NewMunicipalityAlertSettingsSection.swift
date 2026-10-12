import SwiftUI
import UIKit

/// 「旅の記録」画面に置く、初めての市区町村の通知のオン/オフ。
/// 許可が足りない場合は、何が足りないかを脚注で伝え、設定アプリへの導線を出す。
struct NewMunicipalityAlertSettingsSection: View {
    /// アプリのルートで渡される。プレビューなど渡されない場所では何も出さない。
    @Environment(NewMunicipalityAlertMonitor.self) private var monitor: NewMunicipalityAlertMonitor?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let monitor {
            Section {
                Toggle(isOn: Binding(get: { monitor.isEnabled }, set: { monitor.setEnabled($0) })) {
                    Label("初めての市区町村で通知", systemImage: "bell.badge")
                }
                .tint(.teal)
                if Self.needsSettingsApp(monitor.status) {
                    Button("設定アプリを開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            } footer: {
                Text(Self.footerText(for: monitor.status))
            }
            // 設定アプリで通知の許可を変えて戻ってきたときに脚注を合わせる。位置情報の許可はdelegateで届く。
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await monitor.refreshNotificationAuthorization()
            }
        }
    }

    private static func needsSettingsApp(_ status: NewMunicipalityAlertMonitor.Status) -> Bool {
        switch status {
        case .needsAlwaysLocation, .locationDenied, .notificationsDenied: true
        case .off, .active, .awaitingLocationPermission: false
        }
    }

    private static func footerText(for status: NewMunicipalityAlertMonitor.Status) -> String {
        switch status {
        case .off, .awaitingLocationPermission:
            "まだ記録していない市区町村に入ったとき、アプリを閉じていてもお知らせします。位置情報を「常に」許可する必要があります。"
        case .active:
            "まだ記録していない市区町村に入ったとき、アプリを閉じていてもお知らせします。大まかな位置で判定するため、境界を越えてから少し遅れることがあります。"
        case .needsAlwaysLocation:
            "アプリを閉じている間も判定するには、設定アプリで位置情報を「常に」にしてください。"
        case .locationDenied:
            "位置情報が許可されていないため判定できません。設定アプリで位置情報を「常に」にしてください。"
        case .notificationsDenied:
            "通知が許可されていません。設定アプリで通知を許可してください。"
        }
    }
}
