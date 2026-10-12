import Foundation
import Observation

/// アプリ更新時にチュートリアルを出すためのゲート。前回見せたバージョンをUserDefaultsに保存し、
/// 現在のバージョン(CFBundleShortVersionString)と食い違えば「初回起動 or アップデート後」とみなして表示する。
@MainActor
@Observable
final class TutorialGate {
    private static let lastSeenVersionKey = "tutorial.lastSeenVersion"

    var isPresented: Bool

    private let bundle: Bundle
    private let userDefaults: UserDefaults

    /// 初期値をここで同期的に確定させる。@State初期化からbody初回描画までの一瞬でも
    /// isPresented=falseのまま描画されると、その隙にMapScreenが有効扱いになって現在地取得
    /// (位置情報の許可ダイアログ)まで自動で走ってしまうため、評価を後回しにできない。
    init(bundle: Bundle = .main, userDefaults: UserDefaults = .standard) {
        self.bundle = bundle
        self.userDefaults = userDefaults
        let currentVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        isPresented = currentVersion != nil && userDefaults.string(forKey: Self.lastSeenVersionKey) != currentVersion
    }

    private var currentVersion: String? {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    func markSeen() {
        if let currentVersion {
            userDefaults.set(currentVersion, forKey: Self.lastSeenVersionKey)
        }
        isPresented = false
    }
}
