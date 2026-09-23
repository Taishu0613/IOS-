import Foundation
import Testing
@testable import WAGhack

final class MunicipalityMasterSyncGateTests {
    private let suiteName = "MunicipalityMasterSyncGateTests.\(UUID().uuidString)"
    private let userDefaults: UserDefaults
    private let gate: MunicipalityMasterSyncGate

    init() throws {
        userDefaults = try #require(UserDefaults(suiteName: suiteName))
        gate = MunicipalityMasterSyncGate(userDefaults: userDefaults)
    }

    deinit {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    @Test func 一度も同期していなければ同期が必要() {
        let fingerprint = MunicipalityMasterSyncGate.fingerprint(of: Data("code,name".utf8))

        #expect(gate.needsSynchronization(fingerprint: fingerprint, storedMunicipalityCount: 1_965))
    }

    @Test func 同期済みのCSVと中身が同じなら同期を飛ばす() {
        let fingerprint = MunicipalityMasterSyncGate.fingerprint(of: Data("code,name".utf8))
        gate.markSynchronized(fingerprint: fingerprint)

        let sameContent = MunicipalityMasterSyncGate.fingerprint(of: Data("code,name".utf8))

        #expect(!gate.needsSynchronization(fingerprint: sameContent, storedMunicipalityCount: 1_965))
    }

    @Test func CSVの中身が変われば同期が必要() {
        gate.markSynchronized(fingerprint: MunicipalityMasterSyncGate.fingerprint(of: Data("code,name".utf8)))

        let changed = MunicipalityMasterSyncGate.fingerprint(of: Data("code,name,kana".utf8))

        #expect(gate.needsSynchronization(fingerprint: changed, storedMunicipalityCount: 1_965))
    }

    @Test func 中身が同じでも保存済みのマスタが空なら同期が必要() {
        let fingerprint = MunicipalityMasterSyncGate.fingerprint(of: Data("code,name".utf8))
        gate.markSynchronized(fingerprint: fingerprint)

        #expect(gate.needsSynchronization(fingerprint: fingerprint, storedMunicipalityCount: 0))
    }

    @Test func CSVを読めず指紋が無ければ同期が必要() {
        gate.markSynchronized(fingerprint: MunicipalityMasterSyncGate.fingerprint(of: Data("code,name".utf8)))

        #expect(gate.needsSynchronization(fingerprint: nil, storedMunicipalityCount: 1_965))
    }

    @Test func 指紋には読み込み形式の版数が含まれる() {
        let fingerprint = MunicipalityMasterSyncGate.fingerprint(of: Data("code,name".utf8))

        #expect(fingerprint.hasPrefix("\(MunicipalityMasterSyncGate.formatVersion)-"))
    }
}
