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

    enum Operation: Equatable {
        case idle, locating
        /// どの経路の保存かも持つ。再記録だけはシートに進行状況の行を出さず、ボタン自身で見せるため。
        case saving(MapVisitSaveTrigger)

        /// 折りたたみシートに出す進行状況の文言。nilの間はシートを「旅の記録」1行の高さのまま保つ。
        var statusText: String? {
            switch self {
            case .idle: nil
            case .locating: "現在地の市区町村を確認しています…"
            // 再記録ボタンが「記録中」に変わって進行を伝えるため、文言の行を足してシートを伸ばさない。
            // 伸ばすと行が差し替わって、押した再記録ボタン自体が消えてしまう。
            case .saving(.rerecordButton): nil
            case .saving(.firstVisitInvitation): "訪問を記録しています…"
            }
        }
    }

    var isBusy: Bool { operation != .idle }
    var isRerecording: Bool { operation == .saving(.rerecordButton) }
    var statusText: String? { operation.statusText }

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

    /// 保存できた時だけ結果を返す。呼び出し側は`await`の直後(同じMainActorの処理の続き)で完了時の見せ方を
    /// 決めること。`successFeedback`のonChangeで受けると、operationが.idleに戻った描画が先に1回挟まり、
    /// 再記録ボタンが一瞬「再記録」に戻ってから「更新済み」に変わるちらつきになる。
    @discardableResult
    func save(municipalities: [Municipality], context: ModelContext, trigger: MapVisitSaveTrigger) async -> MapVisitResult? {
        guard !isBusy else { return nil }
        operation = .saving(trigger)
        errorMessage = nil
        result = nil
        // 再記録では保存前の現在地を残し、成功したら新しい現在地で上書きする。nilにするとisCurrentPlaceVisitedが
        // falseになり、押した再記録ボタン自体と現在地バッジが消え、ヘッダーの都道府県ページも切り替わってしまうため。
        if trigger != .rerecordButton {
            currentVisit = nil
        }
        var hasResolvedVisit = false
        defer {
            operation = .idle
            // 現在地を取り直せないまま終わった(失敗・中断)場合は、誘いシート経路と同じくnilに揃える。
            // 残しておいた保存前の現在地が、取得に失敗した後も「今いる場所」として表示され続けないようにする。
            if trigger == .rerecordButton, !hasResolvedVisit {
                currentVisit = nil
            }
        }
        do {
            // 表示中の古い位置や、選択したピンではなく、操作時の現在地を記録する。
            let visit = try await resolveCurrentVisit(municipalities: municipalities)
            try Task.checkCancellation()
            currentVisit = visit
            hasResolvedVisit = true
            let visitResult = try MapVisitRecorder().record(visit, municipalities: municipalities, context: context)
            result = visitResult
            successFeedback += 1
            return visitResult
        } catch is CancellationError {
            // タブ移動などで中断した操作には失敗通知を出さない。
            return nil
        } catch {
            errorMessage = error.localizedDescription
            errorFeedback += 1
            return nil
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
