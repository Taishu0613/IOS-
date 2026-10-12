import MapKit
import Observation
import SwiftUI

/// 地図の区域に重ねる演出(記録したときの「はまる」演出と、未訪問の区域に入ったときの脈打ち)の状態を唯一持つ。
///
/// 見た目の値と時刻は`MapAreaEffectTimeline`が、出すかどうかは`MapAreaPlacementPolicy`・`CurrentAreaPulsePolicy`が
/// 決める。この型はそれを時間どおりに適用するだけにし、画面(`MapScreen`)は`emphasis`を`MunicipalityPuzzleLayer`へ、
/// `hapticTrigger`を`sensoryFeedback`へ渡すだけにする。
///
/// 段階は自前のTaskと`Task.sleep`で進め、取り消しもこの型が持つ(`MunicipalityPuzzleStore.loadTask`と同じ形)。
/// 演出は同時に1つだけ。記録(placing)は脈打ち(pulsing)より優先し、記録を始めた時点で脈打ちを止める。
@MainActor
@Observable
final class MapAreaEffectController {
    enum Phase {
        case idle
        /// 現在地の区域の脈打ち中。
        case pulsing
        /// 記録ボタンを押してから、「はまる」演出が終わるまで。
        case placing
    }

    private(set) var phase: Phase = .idle
    /// 演出中の区域と見た目。nilなら全区域が通常の見た目。
    private(set) var emphasis: MunicipalityEmphasis?
    /// 触覚を鳴らすきっかけ。演出の「光る」段階に合わせて鳴らすため、保存の完了(`successFeedback`)とは別に持つ。
    private(set) var hapticTrigger: MapAreaHapticTrigger?

    var isPulsing: Bool { phase == .pulsing }

    @ObservationIgnored private var effectTask: Task<Void, Never>?
    @ObservationIgnored private var hapticCount = 0

    // 以下は脈打ちを出してよいかの判断材料。表示には使わないので観測しない(変わるたびに地図を描き直さない)。
    /// 同じ区域では1回だけ脈打つ。保存や現在地の取り直しで一旦nilを挟んで同じ区域に戻っても繰り返さない。
    @ObservationIgnored private var lastPulsedCode: String?
    @ObservationIgnored private var pulseEnvironment = CurrentAreaPulseEnvironment()
    @ObservationIgnored private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// アプリが地図を動かしている(`MapScreen.focusMap`)場合の、移動が終わる予定の時刻。
    @ObservationIgnored private var cameraArrival: ContinuousClock.Instant?
    @ObservationIgnored private var visibleMapRect: MKMapRect?
    @ObservationIgnored private var mapWidth: CGFloat = 0

    /// カメラの移動が終わる予定の時刻から、表示範囲の通知(`onMapCameraChange(.onEnd)`)が届くまでの余裕。
    private static let cameraSettleAllowance: Duration = .milliseconds(100)

    // MARK: - 記録したときの「はまる」演出

    /// 記録ボタンを押した時点で呼ぶ。演出が始まるまで、区域を記録前の見た目に保つ。
    func beginRecording(_ recordingEmphasis: MunicipalityEmphasis) {
        cancelEffectTask()
        phase = .placing
        emphasis = recordingEmphasis
    }

    /// 保存に失敗・中断した、または結果が更新だったときに呼ぶ。記録中の見た目を取り除く。
    func cancelRecording() {
        guard phase == .placing else { return }
        settleImmediately()
    }

    /// 演出を最後まで(次のシートを出してよい時刻まで)進める。途中で取り消されても(`settleImmediately`)
    /// 待っている側には戻るので、呼び出し側はこの後に必ずシートを出すこと(お祝いを取りこぼさないため)。
    /// - Parameter cameraArrival: 区域へ寄せるカメラの移動が終わる予定の時刻。演出はこれと呼び出し時点
    ///   (保存の完了)の遅い方から始める。`onMapCameraChange`の完了は待たない(同じ位置だと通知が来ないため)。
    func play(_ plan: MapAreaPlacementPlan, cameraArrival: ContinuousClock.Instant?) async {
        cancelEffectTask()
        phase = .placing
        // 押した時と別の区域で保存された場合も、演出が始まるまで保存した区域を記録前の見た目に保つ。
        if let recording = emphasis, recording.scope == plan.scope {
            emphasis = MunicipalityEmphasis(scope: plan.scope, code: plan.code, look: recording.look)
        } else {
            emphasis = nil
        }
        let now = ContinuousClock.now
        let start = plan.waitsForCamera ? max(now, cameraArrival ?? now) : now
        await run(plan.timeline, scope: plan.scope, code: plan.code, from: start)
    }

    /// 進行中の演出を取り消し、すぐに通常の見た目へ戻す。画面から離れる・バックグラウンドへ移るときに呼ぶ。
    func settleImmediately() {
        cancelEffectTask()
        emphasis = nil
        phase = .idle
    }

    // MARK: - 現在地の脈打ち

    /// 未訪問の区域に入ったときに、その区域の縁取りを脈打たせる。終わる(または見送る・途中で止める)まで待つ。
    /// 呼び出し側は、この後に記録の誘いシートを出す(脈打ちを先に見せてから誘う)。
    /// - Parameter areaRect: 区域を囲む範囲。カメラの移動を待った後の、読み込み済みの形で判定するため遅延評価にする。
    func playArrivalPulse(code: String, areaRect: () -> MKMapRect?) async {
        guard code != lastPulsedCode else { return }
        lastPulsedCode = code
        // 現在地へ寄せるカメラの移動が終わってから判断する。移動中は区域が画面に入るか分からないうえ、
        // 始めてしまうと移動そのものが「地図の操作中」として届き、すぐに止めてしまうため。
        if let cameraArrival, cameraArrival > .now {
            do {
                try await Task.sleep(until: cameraArrival + Self.cameraSettleAllowance, clock: .continuous)
            } catch {
                return
            }
        }
        let policy = CurrentAreaPulsePolicy()
        guard phase == .idle,
              policy.canPulse(in: pulseEnvironment, isLowPowerModeEnabled: isLowPowerModeEnabled),
              policy.isAreaOnScreen(areaRect(), visibleRect: visibleMapRect, mapWidth: mapWidth)
        else { return }
        phase = .pulsing
        await run(.currentAreaPulse, scope: .municipality, code: code, from: .now)
    }

    /// 脈打ちを止めて通常の縁取り(2.5pt)に戻す。再開はしない。
    func stopPulse() {
        guard phase == .pulsing else { return }
        settleImmediately()
    }

    /// 画面の状態が変わるたびに呼ぶ。脈打ちの途中で止める条件に当たったら止める。
    func updatePulseEnvironment(_ environment: CurrentAreaPulseEnvironment) {
        pulseEnvironment = environment
        stopPulseIfDisallowed()
    }

    /// アプリが地図を動かし始めたときに呼ぶ。
    func noteCameraMove(arrivingAt arrival: ContinuousClock.Instant) {
        cameraArrival = arrival
    }

    /// 地図のカメラが止まったときに呼ぶ。`visibleRect`はセーフエリアを除いた表示範囲(`MapCameraUpdateContext.rect`)。
    func cameraDidSettle(visibleRect: MKMapRect) {
        visibleMapRect = visibleRect
    }

    func updateMapWidth(_ width: CGFloat) {
        mapWidth = width
    }

    /// 低電力モードの切り替えに追従する。画面の`.task`から呼び、画面が消えると取り消される。
    func monitorLowPowerMode() async {
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
            isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            stopPulseIfDisallowed()
        }
    }

    // MARK: - 段階の進行

    private func stopPulseIfDisallowed() {
        let policy = CurrentAreaPulsePolicy()
        guard phase == .pulsing,
              !policy.canPulse(in: pulseEnvironment, isLowPowerModeEnabled: isLowPowerModeEnabled)
        else { return }
        stopPulse()
    }

    private func run(
        _ timeline: MapAreaEffectTimeline,
        scope: MunicipalityEmphasis.Scope,
        code: String,
        from start: ContinuousClock.Instant
    ) async {
        let task = Task { [weak self] in
            do {
                for step in timeline.steps {
                    try await Task.sleep(until: start + step.offset, clock: .continuous)
                    // 期限が既に過ぎている(最初の段階など)とsleepは取り消しを確かめずに戻ることがあるため、
                    // 適用の直前に改めて確かめる。確かめないと、取り消した後に古い段階の見た目が残る。
                    try Task.checkCancellation()
                    self?.apply(step, scope: scope, code: code)
                }
                try await Task.sleep(until: start + timeline.completionOffset, clock: .continuous)
                try Task.checkCancellation()
                self?.phase = .idle
            } catch {
                // 投げられるのはキャンセルだけ。取り消した側(settleImmediately・次の演出)が
                // 見た目を決め直しているので、ここでは状態を触らない。
                return
            }
        }
        effectTask = task
        await task.value
    }

    private func apply(_ step: MapAreaEffectTimeline.Step, scope: MunicipalityEmphasis.Scope, code: String) {
        emphasis = step.look.map { MunicipalityEmphasis(scope: scope, code: code, look: $0) }
        if let haptic = step.haptic {
            hapticCount += 1
            hapticTrigger = MapAreaHapticTrigger(haptic: haptic, sequence: hapticCount)
        }
    }

    private func cancelEffectTask() {
        effectTask?.cancel()
        effectTask = nil
    }
}

/// `sensoryFeedback(trigger:)`に渡す値。同じ種類の触覚を続けて鳴らせるよう、連番で毎回別の値にする。
struct MapAreaHapticTrigger: Equatable {
    let haptic: MapAreaHaptic
    let sequence: Int
}

extension MapAreaHaptic {
    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .success: .success
        case .levelChange: .levelChange
        }
    }
}
