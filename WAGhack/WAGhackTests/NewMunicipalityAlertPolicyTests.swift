import Foundation
import Testing
@testable import WAGhack

@MainActor
struct NewMunicipalityAlertPolicyTests {
    private let policy = NewMunicipalityAlertPolicy()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func 記録の無い市区町村に入ったら通知する() {
        let decision = policy.decide(
            areaCode: "13101", recordedCodes: ["13102"], history: NewMunicipalityAlertHistory(),
            canPresentNotification: true, now: now
        )
        #expect(decision.shouldNotify)
        #expect(decision.updatedHistory.lastAreaCode == "13101")
        #expect(decision.updatedHistory.notifiedAt["13101"] == now)
    }

    @Test func 記録済みの市区町村では通知しない() {
        let decision = policy.decide(
            areaCode: "13101", recordedCodes: ["13101"], history: NewMunicipalityAlertHistory(),
            canPresentNotification: true, now: now
        )
        #expect(!decision.shouldNotify)
        #expect(decision.updatedHistory.lastAreaCode == "13101")
        #expect(decision.updatedHistory.notifiedAt.isEmpty)
    }

    @Test func 親市だけの記録では区を記録済みとみなさない() {
        // 札幌市(01100)の記録はあるが、札幌市中央区(01101)の記録は無い。
        let decision = policy.decide(
            areaCode: "01101", recordedCodes: ["01100"], history: NewMunicipalityAlertHistory(),
            canPresentNotification: true, now: now
        )
        #expect(decision.shouldNotify)
    }

    @Test func 同じ市区町村の中で位置が変わっただけでは通知しない() {
        let history = NewMunicipalityAlertHistory(lastAreaCode: "13101")
        let decision = policy.decide(
            areaCode: "13101", recordedCodes: [], history: history,
            canPresentNotification: true, now: now
        )
        #expect(!decision.shouldNotify)
    }

    @Test func 境界を行き来しても再通知の間隔内なら同じ市区町村を通知しない() {
        let history = NewMunicipalityAlertHistory(
            lastAreaCode: "13102",
            notifiedAt: ["13101": now.addingTimeInterval(-60 * 60)]
        )
        let decision = policy.decide(
            areaCode: "13101", recordedCodes: [], history: history,
            canPresentNotification: true, now: now
        )
        #expect(!decision.shouldNotify)
        #expect(decision.updatedHistory.lastAreaCode == "13101")
    }

    @Test func 再通知の間隔を過ぎた市区町村は再び通知し古い履歴を捨てる() {
        let old = now.addingTimeInterval(-NewMunicipalityAlertPolicy.renotifyInterval)
        let history = NewMunicipalityAlertHistory(
            lastAreaCode: "13102",
            notifiedAt: ["13101": old, "13103": old]
        )
        let decision = policy.decide(
            areaCode: "13101", recordedCodes: [], history: history,
            canPresentNotification: true, now: now
        )
        #expect(decision.shouldNotify)
        #expect(decision.updatedHistory.notifiedAt == ["13101": now])
    }

    @Test func アプリが前面にある間は通知せず知らせた扱いで履歴に残す() {
        let foreground = policy.decide(
            areaCode: "13101", recordedCodes: [], history: NewMunicipalityAlertHistory(lastAreaCode: "13102"),
            canPresentNotification: false, now: now
        )
        #expect(!foreground.shouldNotify)
        #expect(foreground.updatedHistory.notifiedAt["13101"] == now)

        // 裏へ回った後に隣へ出て戻ってきても、地図画面で誘った市区町村は通知しない。
        let neighbor = policy.decide(
            areaCode: "13102", recordedCodes: ["13102"], history: foreground.updatedHistory,
            canPresentNotification: true, now: now.addingTimeInterval(600)
        )
        let back = policy.decide(
            areaCode: "13101", recordedCodes: ["13102"], history: neighbor.updatedHistory,
            canPresentNotification: true, now: now.addingTimeInterval(1_200)
        )
        #expect(!back.shouldNotify)
    }

    @Test func 履歴は保存して読み戻せる() throws {
        let history = NewMunicipalityAlertHistory(lastAreaCode: "13101", notifiedAt: ["13101": now])
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(NewMunicipalityAlertHistory.self, from: data) == history)
    }

    @Test func 都道府県モードでも同じ規則で記録の無い都道府県だけを通知する() {
        let entered = policy.decide(
            areaCode: "11", recordedCodes: ["13"], history: NewMunicipalityAlertHistory(lastAreaCode: "13"),
            canPresentNotification: true, now: now
        )
        #expect(entered.shouldNotify)
        let recorded = policy.decide(
            areaCode: "13", recordedCodes: ["13"], history: entered.updatedHistory,
            canPresentNotification: true, now: now
        )
        #expect(!recorded.shouldNotify)
    }

    @Test func 市区町村だけだった版で保存した履歴を読める() throws {
        let data = Data(#"{"notifiedAt":{"13102":813492990.4},"lastMunicipalityCode":"13102"}"#.utf8)
        let history = try JSONDecoder().decode(NewMunicipalityAlertHistory.self, from: data)
        #expect(history.lastAreaCode == "13102")
        #expect(history.notifiedAt.keys.sorted() == ["13102"])
    }

    // MARK: - 文言

    @Test func 通知の文言は区域名に初訪問ですと続ける() {
        #expect(NewMunicipalityAlertMessage.body(areaName: "東京都中央区") == "東京都中央区に初訪問です！よりみちを開いて記録しませんか？")
        #expect(NewMunicipalityAlertMessage.body(areaName: "埼玉県") == "埼玉県に初訪問です！よりみちを開いて記録しませんか？")
    }

    // MARK: - モードの保存

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "NewMunicipalityAlertPolicyTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    @Test func 何も保存されていなければモードはオフ() {
        #expect(NewMunicipalityAlertMonitor.loadMode(from: makeUserDefaults()) == .off)
    }

    @Test func オンオフだけの版でオンにしていた人は市区町村モードとして引き継ぐ() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(true, forKey: "newMunicipalityAlert.isEnabled")
        #expect(NewMunicipalityAlertMonitor.loadMode(from: userDefaults) == .municipality)
        #expect(userDefaults.object(forKey: "newMunicipalityAlert.isEnabled") == nil)
        #expect(NewMunicipalityAlertMonitor.loadMode(from: userDefaults) == .municipality)
    }

    @Test func 保存したモードを読み戻せる() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(NewMunicipalityAlertMode.prefecture.rawValue, forKey: "newMunicipalityAlert.mode")
        #expect(NewMunicipalityAlertMonitor.loadMode(from: userDefaults) == .prefecture)
    }

    // MARK: - お知らせ

    @Test func お知らせは見るまで毎回出し見た後は出さない() {
        let userDefaults = makeUserDefaults()
        let gate = NewMunicipalityAlertAnnouncementGate(userDefaults: userDefaults)
        #expect(gate.isPresented)
        gate.markSeen()
        #expect(!gate.isPresented)
        #expect(!NewMunicipalityAlertAnnouncementGate(userDefaults: userDefaults).isPresented)
    }

    @Test func 既に通知を選んでいる人にはお知らせを出さない() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(NewMunicipalityAlertMode.municipality.rawValue, forKey: "newMunicipalityAlert.mode")
        #expect(!NewMunicipalityAlertAnnouncementGate(userDefaults: userDefaults).isPresented)
    }
}
