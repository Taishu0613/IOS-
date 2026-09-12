import CoreLocation
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class MapViewModel {
    private let locationService = LocationService()
    private let addressResolver = AddressResolver()
    private let municipalityMatcher = MunicipalityMatcher()

    private(set) var currentLocation: CLLocation?
    private(set) var currentVisit: MunicipalityVisit?
    private(set) var operation: Operation = .idle
    private(set) var result: MapVisitResult?
    private(set) var successFeedback = 0
    private(set) var errorFeedback = 0
    private(set) var errorMessage: String?

    enum Operation {
        case idle, locating, saving
    }

    var isBusy: Bool { operation != .idle }
    var statusText: String? {
        switch operation {
        case .idle: nil
        case .locating: "現在地の市区町村を確認しています…"
        case .saving: "訪問を記録しています…"
        }
    }

    func refresh(municipalities: [Municipality]) async {
        guard !isBusy else { return }
        operation = .locating
        errorMessage = nil
        result = nil
        currentVisit = nil
        defer { operation = .idle }
        do {
            currentVisit = try await resolveCurrentVisit(municipalities: municipalities)
        } catch is CancellationError {
            // 画面が閉じられた場合のキャンセルはユーザー向けエラーにしない。
            return
        } catch {
            errorMessage = error.localizedDescription
            errorFeedback += 1
        }
    }

    func save(municipalities: [Municipality], context: ModelContext) async {
        guard !isBusy else { return }
        operation = .saving
        errorMessage = nil
        result = nil
        currentVisit = nil
        defer { operation = .idle }
        do {
            // 表示中の古い位置や、選択したピンではなく、操作時の現在地を記録する。
            let visit = try await resolveCurrentVisit(municipalities: municipalities)
            try Task.checkCancellation()
            currentVisit = visit
            result = try MapVisitRecorder().record(visit, municipalities: municipalities, context: context)
            successFeedback += 1
        } catch is CancellationError {
            // タブ移動などで中断した操作には失敗通知を出さない。
            return
        } catch {
            errorMessage = error.localizedDescription
            errorFeedback += 1
        }
    }

    private func resolveCurrentVisit(municipalities: [Municipality]) async throws -> MunicipalityVisit {
        let location = try await locationService.currentLocation()
        try Task.checkCancellation()
        currentLocation = location
        let addresses = try await addressResolver.addresses(for: location)
        try Task.checkCancellation()
        guard let municipality = municipalityMatcher.match(
            japaneseAddress: addresses.japaneseAddressForMatching, municipalities: municipalities
        ) else { throw MunicipalityVisitError.municipalityNotFound }
        return MunicipalityVisit(localizedAddress: addresses.localizedAddress, location: location, municipality: municipality)
    }
}

struct MunicipalityVisit {
    let localizedAddress: String
    let location: CLLocation
    let municipality: Municipality
}

enum MunicipalityVisitError: LocalizedError {
    case municipalityNotFound

    var errorDescription: String? {
        "現在地に対応する市区町村がマスタに見つかりませんでした。"
    }
}
