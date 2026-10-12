import Foundation

// 地図の区域(市区町村のピース・都道府県の面)に重ねる演出の値と段階表。
// 見た目の値と「いつ何を出すか」をここに集め、`MapAreaEffectController`は時間どおりに適用するだけにする。
// SwiftUIの`Color`に変換するのは`MunicipalityPuzzleLayer`側(テストで値を比べられるよう、ここでは数値で持つ)。

/// 演出で使う色。色相はアプリのテーマ色(teal)と未訪問の灰色だけに限り、変化は濃さで伝える
/// (`PrefectureConquestStyle`と同じく、色覚の個人差に左右されないようにするため)。
struct MapAreaPaint: Equatable {
    enum Tint {
        case teal
        case gray
    }

    let tint: Tint
    let opacity: Double

    /// 塗りを消す。区域が一瞬「空いた穴」になり、次の段階で色がはまる対比を作る。
    static let clear = MapAreaPaint(tint: .teal, opacity: 0)

    static func teal(_ opacity: Double) -> MapAreaPaint {
        MapAreaPaint(tint: .teal, opacity: opacity)
    }

    static func gray(_ opacity: Double) -> MapAreaPaint {
        MapAreaPaint(tint: .gray, opacity: opacity)
    }
}

/// 線の色と太さ(pt)。
struct MapAreaStroke: Equatable {
    let paint: MapAreaPaint
    let width: Double
}

/// ある瞬間の区域の見た目。nilの項目は通常の見た目(`MunicipalityPieceStyle`などの値)のまま描く。
struct MapAreaEffectLook: Equatable {
    /// 面の塗り。
    var fill: MapAreaPaint?
    /// 市区町村のピースの細い線。都道府県の面は線を持たない(県境は別の線)ので使わない。
    var pieceStroke: MapAreaStroke?
    /// 地名より上の階層に重ねる強調線(現在地の縁取り・塗られた都道府県の縁取り)。
    var outline: MapAreaStroke?
}

/// 演出中の区域と、その見た目。`MunicipalityPuzzleLayer`はこの値だけを見て、該当する区域のスタイルを差し替える。
struct MunicipalityEmphasis: Equatable {
    /// 同じ「コード」でも、市区町村(5桁)と都道府県(2桁)のどちらを指すかを取り違えないよう明示する。
    enum Scope {
        case municipality
        case prefecture
    }

    let scope: Scope
    let code: String
    let look: MapAreaEffectLook
}

/// 演出の段階に合わせて鳴らす触覚。
enum MapAreaHaptic {
    /// 初めての市区町村。
    case success
    /// 節目(25/50/75/100%)の達成・都道府県の記録。アプリ内で最も重い達成として扱う。
    case levelChange
}

/// 演出の段階表。始まり(S)からの経過時間と、その時点で切り替える見た目・鳴らす触覚を並べる。
struct MapAreaEffectTimeline: Equatable {
    struct Step: Equatable {
        let offset: Duration
        /// nilなら強調をやめて通常の見た目に戻す。
        let look: MapAreaEffectLook?
        var haptic: MapAreaHaptic?
    }

    let steps: [Step]
    /// 始まりから、次のシート(お祝い・誘い)を出してよいまでの時間。最後の段階より後にして、
    /// 色が落ち着いたのを見届けてからシートが上がってくるようにする。
    let completionOffset: Duration

    /// 最初に鳴らす触覚。段階を省いて一度に落ち着かせる場合も、これだけは鳴らす。
    var firstHaptic: MapAreaHaptic? {
        steps.lazy.compactMap(\.haptic).first
    }

    /// 地名が読める上限。塗りはラベルより下の階層だが、これより濃いと地名の文字が沈む。
    static let municipalityFillLimit = 0.62
    /// 都道府県の面の塗りの上限。県は広く地名ラベルの間隔も大きいので、市区町村より少し濃くまで許す。
    static let prefectureFillLimit = 0.70

    // MARK: - 記録中(押してから演出が始まるまで)

    /// 記録ボタンを押してから演出が始まるまで、市区町村のピースを未訪問の見た目に保つ。保存の途中で@Queryが
    /// 反映されて先に色が付くと、演出で「はまる」前に答えが見えてしまうため。
    /// 塗りと線は`MunicipalityPieceStyle`の未訪問、強調線は`CurrentMunicipalityOutlineStyle`と同じ値。
    static let recordingMunicipalityLook = MapAreaEffectLook(
        fill: .gray(0.22),
        pieceStroke: MapAreaStroke(paint: .gray(0.55), width: 0.7),
        outline: MapAreaStroke(paint: .teal(1.0), width: 2.5)
    )

    /// 都道府県の表示で記録している間は、記録前の段階の塗りに保つ(理由は市区町村と同じ)。
    static func recordingPrefectureLook(level: PrefectureConquestLevel) -> MapAreaEffectLook {
        MapAreaEffectLook(fill: PrefectureConquestStyle.fillPaint(for: level))
    }

    // MARK: - はまる演出

    /// 初めての市区町村。塗りを一度抜いてから濃い色で「はめ」、通常の濃さへ落ち着かせる。
    static let municipalityFirstVisit = MapAreaEffectTimeline(
        steps: [
            Step(offset: .zero, look: MapAreaEffectLook(
                fill: .clear,
                pieceStroke: MapAreaStroke(paint: .teal(0.5), width: 0.7),
                outline: MapAreaStroke(paint: .teal(1.0), width: 2.5)
            )),
            Step(offset: .milliseconds(100), look: MapAreaEffectLook(
                fill: .teal(0.55),
                pieceStroke: MapAreaStroke(paint: .teal(0.9), width: 0.7),
                outline: MapAreaStroke(paint: .teal(1.0), width: 4.5)
            ), haptic: .success),
            Step(offset: .milliseconds(400), look: MapAreaEffectLook(
                fill: .teal(0.45),
                pieceStroke: MapAreaStroke(paint: .teal(0.9), width: 0.7),
                outline: MapAreaStroke(paint: .teal(0.9), width: 3.5)
            )),
            Step(offset: .milliseconds(700), look: nil),
        ],
        completionOffset: .milliseconds(800)
    )

    /// 節目の達成。初訪問より濃く・太く・長く光らせて、報酬の違いを見た目でも伝える。
    static let municipalityMilestone = MapAreaEffectTimeline(
        steps: [
            Step(offset: .zero, look: MapAreaEffectLook(
                fill: .clear,
                pieceStroke: MapAreaStroke(paint: .teal(0.5), width: 0.7),
                outline: MapAreaStroke(paint: .teal(1.0), width: 2.5)
            )),
            Step(offset: .milliseconds(100), look: MapAreaEffectLook(
                fill: .teal(municipalityFillLimit),
                pieceStroke: MapAreaStroke(paint: .teal(0.9), width: 0.7),
                outline: MapAreaStroke(paint: .teal(1.0), width: 6)
            ), haptic: .levelChange),
            Step(offset: .milliseconds(500), look: MapAreaEffectLook(
                fill: .teal(0.50),
                pieceStroke: MapAreaStroke(paint: .teal(0.9), width: 0.7),
                outline: MapAreaStroke(paint: .teal(1.0), width: 4.5)
            )),
            Step(offset: .milliseconds(800), look: MapAreaEffectLook(
                fill: .teal(0.42),
                pieceStroke: MapAreaStroke(paint: .teal(0.9), width: 0.7),
                outline: MapAreaStroke(paint: .teal(0.9), width: 3.5)
            )),
            Step(offset: .milliseconds(1000), look: nil),
        ],
        completionOffset: .milliseconds(1050)
    )

    /// 都道府県の表示で段階が上がった(または初めて記録した)とき。新しい段階の塗りより一時的に濃くしてから戻す。
    static func prefectureLevelUp(to level: PrefectureConquestLevel, haptic: MapAreaHaptic) -> MapAreaEffectTimeline {
        let settledOpacity = PrefectureConquestStyle.fillPaint(for: level).opacity
        return MapAreaEffectTimeline(
            steps: [
                Step(offset: .zero, look: MapAreaEffectLook(fill: .clear)),
                Step(offset: .milliseconds(100), look: MapAreaEffectLook(
                    fill: .teal(min(settledOpacity + 0.15, prefectureFillLimit)),
                    outline: MapAreaStroke(paint: .teal(1.0), width: 3.5)
                ), haptic: haptic),
                Step(offset: .milliseconds(450), look: MapAreaEffectLook(
                    fill: .teal(min(settledOpacity + 0.07, prefectureFillLimit)),
                    outline: MapAreaStroke(paint: .teal(1.0), width: 2.4)
                )),
                Step(offset: .milliseconds(750), look: nil),
            ],
            completionOffset: .milliseconds(800)
        )
    }

    /// 段階を踏まず、始まりの時点で通常の見た目に戻して触覚だけ鳴らす。
    static func settledAtOnce(haptic: MapAreaHaptic?, completionOffset: Duration) -> MapAreaEffectTimeline {
        MapAreaEffectTimeline(steps: [Step(offset: .zero, look: nil, haptic: haptic)], completionOffset: completionOffset)
    }

    // MARK: - 現在地の脈打ち

    /// 未訪問の区域に入ったときの「ホワンホワン」。強調線だけを変え、塗り(未訪問の灰色)は変えない。
    static let currentAreaPulse: MapAreaEffectTimeline = {
        let period = 800
        let cycleCount = 3
        var steps: [Step] = []
        for cycle in 0..<cycleCount {
            let start = cycle * period
            steps.append(Step(offset: .milliseconds(start), look: MapAreaEffectLook(
                outline: MapAreaStroke(paint: .teal(0.75), width: 4)
            )))
            steps.append(Step(offset: .milliseconds(start + 180), look: MapAreaEffectLook(
                outline: MapAreaStroke(paint: .teal(0.4), width: 6)
            )))
            // 通常の縁取り(2.5pt)と同じ値に戻し、周期の残りは休ませる。
            steps.append(Step(offset: .milliseconds(start + 360), look: MapAreaEffectLook(
                outline: MapAreaStroke(paint: .teal(1.0), width: 2.5)
            )))
        }
        let end = Duration.milliseconds(period * cycleCount)
        steps.append(Step(offset: end, look: nil))
        return MapAreaEffectTimeline(steps: steps, completionOffset: end)
    }()
}

// MARK: - 記録の演出の決め方

/// 記録が完了したときの演出の出し方。
enum MapAreaPlacementPresentation: Equatable {
    /// 段階表どおりに見せる。
    case animated
    /// 視差効果を減らす設定。段階を踏まず、始まりの時点で一度に通常の見た目へ切り替える。
    case reducedMotion
    /// 演出が目に入らない状況。カメラの到着も待たずに、保存完了の時点で触覚だけ鳴らして落ち着かせる。
    case immediate
}

/// 何を記録したか。
enum MapAreaRecord: Equatable {
    case municipality(MapVisitResult.Kind)
    /// 都道府県単独の記録(`VisitedPrefecture`)。
    case prefecture
}

/// 記録の演出を決めるための、その時点の画面の状態。
struct MapAreaPlacementRequest {
    let record: MapAreaRecord
    let municipalityCode: String
    let prefectureCode: String
    /// 地図が都道府県の制覇率で塗り分けられているか(falseなら市区町村のパズル表示)。
    let isPrefectureDisplay: Bool
    /// 記録する前と後の、その都道府県の塗りの段階。都道府県の表示でだけ使う。
    let previousPrefectureLevel: PrefectureConquestLevel
    let prefectureLevel: PrefectureConquestLevel
    let reduceMotion: Bool
    let isSheetExpanded: Bool
    let hasSelectedPlace: Bool
    /// 演出する区域の形を読み込み済みか。
    let isBoundaryLoaded: Bool
}

/// 決まった演出。
struct MapAreaPlacementPlan: Equatable {
    let scope: MunicipalityEmphasis.Scope
    let code: String
    let timeline: MapAreaEffectTimeline
    /// 地図のカメラが区域へ寄り終わるのを待ってから始めるか。
    let waitsForCamera: Bool
}

/// 記録が完了した時点の画面の状態から、演出の出し方を決める。
struct MapAreaPlacementPolicy {
    /// 演出を省いたときに、次のシートを出すまでの間。直前のシートのdismissアニメーションと
    /// 重ならないよう、他の儀式シート遷移と同じ一呼吸を置く(従来の350ms)。
    static let immediateSheetDelay: Duration = .milliseconds(350)
    /// 視差効果を減らす設定で、色が切り替わってから次のシートを出すまでの間。
    static let reducedMotionSheetDelay: Duration = .milliseconds(400)

    /// 記録ボタンを押してから演出が始まるまでの見た目。
    func recordingEmphasis(
        municipalityCode: String,
        prefectureCode: String,
        isPrefectureDisplay: Bool,
        prefectureLevel: PrefectureConquestLevel
    ) -> MunicipalityEmphasis {
        if isPrefectureDisplay {
            return MunicipalityEmphasis(
                scope: .prefecture, code: prefectureCode,
                look: MapAreaEffectTimeline.recordingPrefectureLook(level: prefectureLevel)
            )
        }
        return MunicipalityEmphasis(
            scope: .municipality, code: municipalityCode, look: MapAreaEffectTimeline.recordingMunicipalityLook
        )
    }

    /// nilなら演出も触覚も出さない(単なる更新。更新は再記録ボタンと吹き出しで伝える)。
    func plan(for request: MapAreaPlacementRequest) -> MapAreaPlacementPlan? {
        let scope: MunicipalityEmphasis.Scope = request.isPrefectureDisplay ? .prefecture : .municipality
        let code = request.isPrefectureDisplay ? request.prefectureCode : request.municipalityCode
        switch effect(for: request) {
        case nil:
            return nil
        case .hapticOnly(let haptic):
            let timeline = MapAreaEffectTimeline.settledAtOnce(haptic: haptic, completionOffset: Self.immediateSheetDelay)
            return MapAreaPlacementPlan(scope: scope, code: code, timeline: timeline, waitsForCamera: false)
        case .visible(let fullTimeline):
            switch presentation(for: request) {
            case .animated:
                return MapAreaPlacementPlan(scope: scope, code: code, timeline: fullTimeline, waitsForCamera: true)
            case .reducedMotion:
                let timeline = MapAreaEffectTimeline.settledAtOnce(
                    haptic: fullTimeline.firstHaptic, completionOffset: Self.reducedMotionSheetDelay
                )
                return MapAreaPlacementPlan(scope: scope, code: code, timeline: timeline, waitsForCamera: true)
            case .immediate:
                let timeline = MapAreaEffectTimeline.settledAtOnce(
                    haptic: fullTimeline.firstHaptic, completionOffset: Self.immediateSheetDelay
                )
                return MapAreaPlacementPlan(scope: scope, code: code, timeline: timeline, waitsForCamera: false)
            }
        }
    }

    /// 見た目の変わる演出を、今の画面の状態でどう出すか。
    func presentation(for request: MapAreaPlacementRequest) -> MapAreaPlacementPresentation {
        // シートを広げている・ピンを選んでいる間は区域が隠れているか別の場所を映しているため、見せても届かない。
        // 形が未読込なら描く相手が無い。どちらも待たせずに落ち着かせる。
        guard !request.isSheetExpanded, !request.hasSelectedPlace, request.isBoundaryLoaded else {
            return .immediate
        }
        return request.reduceMotion ? .reducedMotion : .animated
    }

    private enum Effect {
        /// 地図の見た目を段階表どおりに変える。
        case visible(MapAreaEffectTimeline)
        /// 地図の見た目は変わらないので、触覚だけ鳴らす(従来どおりの見せ方)。
        case hapticOnly(MapAreaHaptic)
    }

    private func effect(for request: MapAreaPlacementRequest) -> Effect? {
        let haptic: MapAreaHaptic
        switch request.record {
        case .municipality(.update):
            return nil
        case .municipality(.firstVisit):
            haptic = .success
        case .municipality(.milestone), .prefecture:
            haptic = .levelChange
        }

        if request.isPrefectureDisplay {
            // 段階が変わらない記録は、都道府県の塗りの見た目も変わらない。
            guard request.prefectureLevel > request.previousPrefectureLevel else { return .hapticOnly(haptic) }
            return .visible(.prefectureLevelUp(to: request.prefectureLevel, haptic: haptic))
        }
        switch request.record {
        case .municipality(.milestone):
            return .visible(.municipalityMilestone)
        case .municipality:
            return .visible(.municipalityFirstVisit)
        // 市区町村の表示では都道府県の面を描かないので、都道府県の記録は触覚だけにする。
        case .prefecture:
            return .hapticOnly(haptic)
        }
    }
}
