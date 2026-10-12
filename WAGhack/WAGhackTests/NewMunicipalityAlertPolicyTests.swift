import Foundation
import Testing
@testable import WAGhack

@MainActor
struct NewMunicipalityAlertPolicyTests {
    private let policy = NewMunicipalityAlertPolicy()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func 記録の無い市区町村に入ったら通知する() {
        let decision = policy.decide(
            municipalityCode: "13101", recordedCodes: ["13102"], history: NewMunicipalityAlertHistory(),
            canPresentNotification: true, now: now
        )
        #expect(decision.shouldNotify)
        #expect(decision.updatedHistory.lastMunicipalityCode == "13101")
        #expect(decision.updatedHistory.notifiedAt["13101"] == now)
    }

    @Test func 記録済みの市区町村では通知しない() {
        let decision = policy.decide(
            municipalityCode: "13101", recordedCodes: ["13101"], history: NewMunicipalityAlertHistory(),
            canPresentNotification: true, now: now
        )
        #expect(!decision.shouldNotify)
        #expect(decision.updatedHistory.lastMunicipalityCode == "13101")
        #expect(decision.updatedHistory.notifiedAt.isEmpty)
    }

    @Test func 親市だけの記録では区を記録済みとみなさない() {
        // 札幌市(01100)の記録はあるが、札幌市中央区(01101)の記録は無い。
        let decision = policy.decide(
            municipalityCode: "01101", recordedCodes: ["01100"], history: NewMunicipalityAlertHistory(),
            canPresentNotification: true, now: now
        )
        #expect(decision.shouldNotify)
    }

    @Test func 同じ市区町村の中で位置が変わっただけでは通知しない() {
        let history = NewMunicipalityAlertHistory(lastMunicipalityCode: "13101")
        let decision = policy.decide(
            municipalityCode: "13101", recordedCodes: [], history: history,
            canPresentNotification: true, now: now
        )
        #expect(!decision.shouldNotify)
    }

    @Test func 境界を行き来しても再通知の間隔内なら同じ市区町村を通知しない() {
        let history = NewMunicipalityAlertHistory(
            lastMunicipalityCode: "13102",
            notifiedAt: ["13101": now.addingTimeInterval(-60 * 60)]
        )
        let decision = policy.decide(
            municipalityCode: "13101", recordedCodes: [], history: history,
            canPresentNotification: true, now: now
        )
        #expect(!decision.shouldNotify)
        #expect(decision.updatedHistory.lastMunicipalityCode == "13101")
    }

    @Test func 再通知の間隔を過ぎた市区町村は再び通知し古い履歴を捨てる() {
        let old = now.addingTimeInterval(-NewMunicipalityAlertPolicy.renotifyInterval)
        let history = NewMunicipalityAlertHistory(
            lastMunicipalityCode: "13102",
            notifiedAt: ["13101": old, "13103": old]
        )
        let decision = policy.decide(
            municipalityCode: "13101", recordedCodes: [], history: history,
            canPresentNotification: true, now: now
        )
        #expect(decision.shouldNotify)
        #expect(decision.updatedHistory.notifiedAt == ["13101": now])
    }

    @Test func アプリが前面にある間は通知せず知らせた扱いで履歴に残す() {
        let foreground = policy.decide(
            municipalityCode: "13101", recordedCodes: [], history: NewMunicipalityAlertHistory(lastMunicipalityCode: "13102"),
            canPresentNotification: false, now: now
        )
        #expect(!foreground.shouldNotify)
        #expect(foreground.updatedHistory.notifiedAt["13101"] == now)

        // 裏へ回った後に隣へ出て戻ってきても、地図画面で誘った市区町村は通知しない。
        let neighbor = policy.decide(
            municipalityCode: "13102", recordedCodes: ["13102"], history: foreground.updatedHistory,
            canPresentNotification: true, now: now.addingTimeInterval(600)
        )
        let back = policy.decide(
            municipalityCode: "13101", recordedCodes: ["13102"], history: neighbor.updatedHistory,
            canPresentNotification: true, now: now.addingTimeInterval(1_200)
        )
        #expect(!back.shouldNotify)
    }

    @Test func 履歴は保存して読み戻せる() throws {
        let history = NewMunicipalityAlertHistory(lastMunicipalityCode: "13101", notifiedAt: ["13101": now])
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(NewMunicipalityAlertHistory.self, from: data) == history)
    }
}
