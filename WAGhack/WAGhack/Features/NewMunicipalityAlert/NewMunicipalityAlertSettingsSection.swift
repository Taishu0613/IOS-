import SwiftUI
import UIKit

/// 「旅の記録」画面に置く、初めての場所の通知のモード(オフ／市区町村ごと／都道府県のみ)。
/// 許可が足りない場合は、何が足りないかを脚注で伝え、設定アプリへの導線を出す。
struct NewMunicipalityAlertSettingsSection: View {
    /// アプリのルートで渡される。プレビューなど渡されない場所では何も出さない。
    @Environment(NewMunicipalityAlertMonitor.self) private var monitor: NewMunicipalityAlertMonitor?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let monitor {
            Section {
                Picker(selection: Binding(get: { monitor.mode }, set: { monitor.setMode($0) })) {
                    ForEach(NewMunicipalityAlertMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Label("初訪問の通知", systemImage: "bell.badge")
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
                Text(Self.footerText(for: monitor.status, mode: monitor.mode))
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

    private static func footerText(for status: NewMunicipalityAlertMonitor.Status, mode: NewMunicipalityAlertMode) -> String {
        switch status {
        case .off:
            "まだ記録していない市区町村、または都道府県に入ったとき、アプリを閉じていてもお知らせします。位置情報を「常に」許可する必要があります。"
        case .awaitingLocationPermission:
            "\(areaDescription(for: mode))に入ったとき、アプリを閉じていてもお知らせします。位置情報を「常に」許可する必要があります。"
        case .active:
            "\(areaDescription(for: mode))に入ったとき、アプリを閉じていてもお知らせします。大まかな位置で判定するため、境界を越えてから少し遅れることがあります。"
        case .needsAlwaysLocation:
            "アプリを閉じている間も判定するには、設定アプリで位置情報を「常に」にしてください。"
        case .locationDenied:
            "位置情報が許可されていないため判定できません。設定アプリで位置情報を「常に」にしてください。"
        case .notificationsDenied:
            "通知が許可されていません。設定アプリで通知を許可してください。"
        }
    }

    private static func areaDescription(for mode: NewMunicipalityAlertMode) -> String {
        switch mode {
        case .prefecture: "まだ記録していない都道府県"
        case .municipality, .off: "まだ記録していない市区町村"
        }
    }
}
