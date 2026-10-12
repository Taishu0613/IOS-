import Foundation

/// 「記録が一度もない市区町村に入った」通知の判定に使う、これまでの判定の履歴。
/// アプリは位置の変化で裏で起こされては終了されるため、UserDefaultsに保存して起動をまたいで引き継ぐ。
struct NewMunicipalityAlertHistory: Codable, Equatable {
    /// 最後に判定した市区町村のコード。同じ市区町村の中で位置が変わっただけでは通知しないために使う。
    var lastMunicipalityCode: String?
    /// 知らせた市区町村のコードと日時。境界付近で行き来したときに同じ市区町村を何度も通知しないために使う。
    /// アプリが前面にあって地図画面の誘いシートに任せた場合も「知らせた」に含める。
    /// `NewMunicipalityAlertPolicy.renotifyInterval`より古いものは判定のたびに捨てる。
    var notifiedAt: [String: Date] = [:]
}

/// 判定した市区町村について通知するかどうかを決める。位置情報・通知・SwiftDataには依存しない。
///
/// 「初めて」の判定は既存の記録(`SavedPlace`)をそのまま使う。政令指定都市は区のコードで記録されるため、
/// 親市だけの記録があっても区は未記録として扱う(踏破率の規則と同じ)。
struct NewMunicipalityAlertPolicy {
    /// 一度通知した市区町村を、出入りしても再び通知しない期間。
    /// 境界沿いの道を走ると数分おきに出入りするため、少なくともその日のうちは繰り返さない長さにしてある。
    /// 仮の値。実機で使って調整する。
    static let renotifyInterval: TimeInterval = 12 * 60 * 60

    struct Decision: Equatable {
        let shouldNotify: Bool
        /// 判定後に保存し直す履歴。通知しなかった場合も「最後に判定した市区町村」は進める。
        let updatedHistory: NewMunicipalityAlertHistory
    }

    /// - Parameters:
    ///   - municipalityCode: 現在地の市区町村のコード。
    ///   - recordedCodes: 記録済みの市区町村のコード。
    ///   - canPresentNotification: 通知を出してよい状況か。アプリが前面にある間は地図画面が自前の誘いシートを
    ///     出すためfalseにする。falseでも知らせたものとして履歴に残し、裏へ回った後に同じ市区町村を改めて通知しないようにする。
    func decide(
        municipalityCode: String,
        recordedCodes: Set<String>,
        history: NewMunicipalityAlertHistory,
        canPresentNotification: Bool,
        now: Date
    ) -> Decision {
        var updatedHistory = history
        updatedHistory.notifiedAt = history.notifiedAt.filter { _, notifiedAt in
            now.timeIntervalSince(notifiedAt) < Self.renotifyInterval
        }
        updatedHistory.lastMunicipalityCode = municipalityCode

        let hasEnteredAnotherMunicipality = municipalityCode != history.lastMunicipalityCode
        let isRecorded = recordedCodes.contains(municipalityCode)
        let wasNotifiedRecently = updatedHistory.notifiedAt[municipalityCode] != nil
        let shouldInform = hasEnteredAnotherMunicipality && !isRecorded && !wasNotifiedRecently

        if shouldInform {
            updatedHistory.notifiedAt[municipalityCode] = now
        }
        return Decision(shouldNotify: shouldInform && canPresentNotification, updatedHistory: updatedHistory)
    }
}
