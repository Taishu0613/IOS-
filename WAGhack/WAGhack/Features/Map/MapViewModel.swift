import CoreLocation
import Foundation
import Observation
import os
import SwiftData

@MainActor
@Observable
final class MapViewModel {
    private let locationService = LocationService()
    private let addressResolver = AddressResolver()
    private let municipalityMatcher = MunicipalityMatcher()
    private let logger = Logger(subsystem: "com.wakasugi.yorimichi", category: "MapLocation")

    // 以下3つの値は仮の値。実機で歩き・車・電車での反応の速さと通信回数を見て調整する。

    /// 移動中の自動判定(`monitorMunicipalityChanges`)をやり直す最小の移動距離。
    /// 住所の確認(逆ジオコーディング)は通信を伴うため、位置が届くたびではなくこれだけ動いた時だけ行う。
    /// 市区町村の境界付近でGPSの揺れによって判定が行き来しないよう、下の精度の上限より十分大きくしてある。
    private static let automaticCheckDistance: CLLocationDistance = 300
    /// 自動判定どうしの最小間隔。車や電車で速く移動していても、住所の確認がこれより頻繁にならないようにする。
    private static let automaticCheckInterval: Duration = .seconds(30)
    /// 自動判定に使う位置の精度の上限(m)。これより粗い位置(屋内・地下など)では判定しない。
    private static let automaticCheckMaximumAccuracy: CLLocationAccuracy = 100

    /// 現在地ボタン・記録による現在地の取り直しが始まるたびに増やす。自動判定の結果が返るまでの間に
    /// 取り直しが始まっていたら、そちらの結果を優先して自動判定の結果は捨てるために使う。
    @ObservationIgnored private var locationRequestGeneration = 0
    @ObservationIgnored private var lastAutomaticCheckAt: ContinuousClock.Instant?

    private(set) var currentLocation: CLLocation?
    private(set) var currentVisit: MunicipalityVisit?
    /// 誘いシート経路の保存中だけ、保存前の現在地の市区町村を持つ(保存中は`currentVisit`がnilになるため)。
    /// 地図画面がヘッダーの都道府県と地図の表示モード(市区町村/全国)を保存中も保つために使う。
    /// 保てないと保存中だけ全国表示に切り替わり、市区町村のピースを読み込み直すことになって、
    /// 記録の演出(`MapAreaEffectController`)を出す時点でピースが無い状態になる。
    private(set) var municipalityBeingSaved: Municipality?
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

    /// - Parameter onLocationResolved: 現在地の座標が分かった時点で、住所の確認(逆ジオコーディング)より先に呼ぶ。
    ///   住所の確認は通信を挟むため数秒かかることがあり、その間も地図だけは先に現在地へ寄せられるようにする。
    ///   取得に失敗した場合は呼ばれない。
    func refresh(municipalities: [Municipality], onLocationResolved: (CLLocation) -> Void = { _ in }) async {
        guard !isBusy else { return }
        locationRequestGeneration += 1
        operation = .locating
        errorMessage = nil
        result = nil
        currentVisit = nil
        defer { operation = .idle }
        do {
            currentVisit = try await resolveCurrentVisit(municipalities: municipalities, onLocationResolved: onLocationResolved)
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
        locationRequestGeneration += 1
        operation = .saving(trigger)
        errorMessage = nil
        result = nil
        // 再記録では保存前の現在地を残し、成功したら新しい現在地で上書きする。nilにするとisCurrentPlaceVisitedが
        // falseになり、押した再記録ボタン自体と現在地バッジが消え、ヘッダーの都道府県ページも切り替わってしまうため。
        if trigger != .rerecordButton {
            municipalityBeingSaved = currentVisit?.municipality
            currentVisit = nil
        }
        var hasResolvedVisit = false
        defer {
            operation = .idle
            municipalityBeingSaved = nil
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

    /// 移動して別の市区町村に入ったことを、現在地ボタンを押さなくても`currentVisit`へ反映し続ける。
    /// 呼び出し側のタスクがキャンセルされるまで戻らない。画面が前面にあり、儀式シートなどを出していない間だけ呼ぶこと。
    ///
    /// 現在地ボタンの`refresh`と違い、判定中も`currentVisit`を消さず、進行状況やエラーも出さない。
    /// ユーザーが操作していない裏の処理で、シートの行が切り替わったりエラーの触覚が鳴ったりしないようにするため。
    /// 市区町村が変わった時だけ`currentVisit`を差し替えるので、既存の`municipality.code`のonChangeがそのまま
    /// 「新しい市区町村に入った」演出(脈打ち→誘い)を始める。
    func monitorMunicipalityChanges(municipalities: [Municipality]) async {
        let updates = locationService.accurateLocationUpdates(
            maximumHorizontalAccuracy: Self.automaticCheckMaximumAccuracy
        )
        for await location in updates {
            guard shouldCheckAutomatically(at: location) else { continue }
            await checkMunicipalitySilently(at: location, municipalities: municipalities)
        }
    }

    private func shouldCheckAutomatically(at location: CLLocation) -> Bool {
        // 起動直後の取得や現在地ボタンの取り直しが進行中なら、そちらに任せる。
        guard !isBusy else { return false }
        if let lastLocation = currentLocation, location.distance(from: lastLocation) < Self.automaticCheckDistance {
            return false
        }
        if let lastAutomaticCheckAt, ContinuousClock.now - lastAutomaticCheckAt < Self.automaticCheckInterval {
            return false
        }
        return true
    }

    private func checkMunicipalitySilently(at location: CLLocation, municipalities: [Municipality]) async {
        let generation = locationRequestGeneration
        lastAutomaticCheckAt = .now
        // 失敗しても次の判定の起点を進める。同じ場所で失敗し続けた時に、位置が届くたびに住所の確認を繰り返さないため。
        currentLocation = location
        do {
            let visit = try await resolveVisit(at: location, municipalities: municipalities)
            try Task.checkCancellation()
            // 確認している間に現在地ボタン・記録が始まっていたら、操作時の現在地を取り直すそちらを優先する。
            guard generation == locationRequestGeneration, !isBusy else { return }
            errorMessage = nil
            guard visit.municipality.code != currentVisit?.municipality.code else { return }
            // 前の市区町村で記録した結果を、新しい市区町村のものとして見せないようにする。
            result = nil
            currentVisit = visit
        } catch is CancellationError {
            return
        } catch {
            // 裏の処理なのでユーザーには見せない。移動を続ければ次の地点で判定し直し、
            // 必要なら現在地ボタンで明示的に取り直せる。
            logger.notice("移動中の市区町村の判定に失敗しました: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func resolveCurrentVisit(
        municipalities: [Municipality],
        onLocationResolved: (CLLocation) -> Void = { _ in }
    ) async throws -> MunicipalityVisit {
        let location = try await locationService.currentLocation()
        try Task.checkCancellation()
        currentLocation = location
        onLocationResolved(location)
        return try await resolveVisit(at: location, municipalities: municipalities)
    }

    private func resolveVisit(at location: CLLocation, municipalities: [Municipality]) async throws -> MunicipalityVisit {
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
