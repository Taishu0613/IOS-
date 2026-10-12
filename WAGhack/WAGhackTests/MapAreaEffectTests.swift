import MapKit
import Testing
@testable import WAGhack

@MainActor
struct MapAreaEffectTimelineTests {
    @Test func 節目の強調は初訪問より太い() {
        #expect(maximumOutlineWidth(of: .municipalityMilestone) > maximumOutlineWidth(of: .municipalityFirstVisit))
    }

    @Test func 節目の塗りは初訪問より濃い() {
        #expect(maximumFillOpacity(of: .municipalityMilestone) > maximumFillOpacity(of: .municipalityFirstVisit))
    }

    @Test func 市区町村の塗りは地名が読める上限を超えない() {
        for timeline in [MapAreaEffectTimeline.municipalityFirstVisit, .municipalityMilestone] {
            #expect(maximumFillOpacity(of: timeline) <= 0.62)
        }
    }

    @Test func 演出の色はtealと灰色だけを使う() {
        let timelines: [MapAreaEffectTimeline] = [
            .municipalityFirstVisit, .municipalityMilestone, .currentAreaPulse,
            .prefectureLevelUp(to: .complete, haptic: .levelChange),
        ]
        for timeline in timelines {
            for look in timeline.steps.compactMap(\.look) {
                let paints = [look.fill, look.pieceStroke?.paint, look.outline?.paint].compactMap { $0 }
                #expect(paints.allSatisfy { $0.tint == .teal || $0.tint == .gray })
            }
        }
    }

    @Test func 初訪問は塗りを抜いてから100ミリ秒後に光らせて触覚を鳴らす() {
        let steps = MapAreaEffectTimeline.municipalityFirstVisit.steps
        #expect(steps[0].offset == .zero)
        #expect(steps[0].look?.fill == .clear)
        #expect(steps[0].haptic == nil)
        #expect(steps[1].offset == .milliseconds(100))
        #expect(steps[1].look?.fill == .teal(0.55))
        #expect(steps[1].look?.outline == MapAreaStroke(paint: .teal(1.0), width: 4.5))
        #expect(steps[1].haptic == .success)
    }

    @Test func 初訪問は700ミリ秒で通常の見た目に戻り800ミリ秒でシートを出す() {
        let timeline = MapAreaEffectTimeline.municipalityFirstVisit
        #expect(timeline.steps.last?.offset == .milliseconds(700))
        #expect(timeline.steps.last?.look == nil)
        #expect(timeline.completionOffset == .milliseconds(800))
    }

    @Test func 節目は重い触覚で1000ミリ秒かけて戻り1050ミリ秒でシートを出す() {
        let timeline = MapAreaEffectTimeline.municipalityMilestone
        #expect(timeline.firstHaptic == .levelChange)
        #expect(timeline.steps.last?.offset == .milliseconds(1000))
        #expect(timeline.steps.last?.look == nil)
        #expect(timeline.completionOffset == .milliseconds(1050))
    }

    @Test func 都道府県は新しい段階の塗りより一時的に濃く光らせてから少しずつ戻す() {
        let steps = MapAreaEffectTimeline.prefectureLevelUp(to: .quarter, haptic: .levelChange).steps
        // .quarterの塗りは0.27なので、光る段階は+0.15の0.42、戻る途中は+0.07の0.34。
        #expect(steps[0].look?.fill == .clear)
        #expect(isClose(steps[1].look?.fill?.opacity, 0.42))
        #expect(steps[1].look?.outline == MapAreaStroke(paint: .teal(1.0), width: 3.5))
        #expect(steps[1].haptic == .levelChange)
        #expect(isClose(steps[2].look?.fill?.opacity, 0.34))
        #expect(steps[2].look?.outline?.width == 2.4)
        #expect(steps[3].offset == .milliseconds(750))
        #expect(steps[3].look == nil)
    }

    @Test func 都道府県の塗りは上限を超えない() {
        let timeline = MapAreaEffectTimeline.prefectureLevelUp(to: .complete, haptic: .levelChange)
        #expect(maximumFillOpacity(of: timeline) <= 0.70)
    }

    @Test func 脈打ちは周期800ミリ秒で3回繰り返し2400ミリ秒で終わる() {
        let timeline = MapAreaEffectTimeline.currentAreaPulse
        let peaks = timeline.steps.filter { $0.look?.outline?.width == 6 }
        #expect(peaks.map(\.offset) == [.milliseconds(180), .milliseconds(980), .milliseconds(1780)])
        #expect(timeline.steps.last?.offset == .milliseconds(2400))
        #expect(timeline.steps.last?.look == nil)
        #expect(timeline.completionOffset == .milliseconds(2400))
    }

    @Test func 脈打ちは強調線だけを変え塗りとピースの線は変えない() {
        for look in MapAreaEffectTimeline.currentAreaPulse.steps.compactMap(\.look) {
            #expect(look.fill == nil)
            #expect(look.pieceStroke == nil)
            #expect(look.outline != nil)
        }
    }

    @Test func 脈打ちは触覚を鳴らさない() {
        #expect(MapAreaEffectTimeline.currentAreaPulse.firstHaptic == nil)
    }

    @Test func 記録中は未訪問のピースの見た目に保つ() {
        let look = MapAreaEffectTimeline.recordingMunicipalityLook
        #expect(look.fill == .gray(0.22))
        #expect(look.pieceStroke == MapAreaStroke(paint: .gray(0.55), width: 0.7))
        #expect(look.outline == MapAreaStroke(paint: .teal(1.0), width: 2.5))
    }

    private func maximumOutlineWidth(of timeline: MapAreaEffectTimeline) -> Double {
        timeline.steps.compactMap { $0.look?.outline?.width }.max() ?? 0
    }

    private func maximumFillOpacity(of timeline: MapAreaEffectTimeline) -> Double {
        timeline.steps.compactMap { $0.look?.fill?.opacity }.max() ?? 0
    }

    private func isClose(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.0001
    }
}

@MainActor
struct MapAreaPlacementPolicyTests {
    private let policy = MapAreaPlacementPolicy()

    @Test func 更新は演出も触覚も出さない() {
        #expect(policy.plan(for: request(record: .municipality(.update))) == nil)
    }

    @Test func 市区町村の表示の初訪問はカメラの到着を待って段階どおりに見せる() {
        let plan = policy.plan(for: request(record: .municipality(.firstVisit)))
        #expect(plan == MapAreaPlacementPlan(
            scope: .municipality, code: "13101", timeline: .municipalityFirstVisit, waitsForCamera: true
        ))
    }

    @Test func 市区町村の表示の節目は節目の段階表で見せる() {
        let plan = policy.plan(for: request(record: .municipality(.milestone)))
        #expect(plan?.timeline == .municipalityMilestone)
    }

    @Test func 保存完了時にシートを広げていれば触覚だけ鳴らして従来どおり350ミリ秒後にシートを出す() {
        let plan = policy.plan(for: request(record: .municipality(.firstVisit), isSheetExpanded: true))
        #expect(plan?.timeline == .settledAtOnce(haptic: .success, completionOffset: .milliseconds(350)))
        #expect(plan?.waitsForCamera == false)
    }

    @Test func 保存完了時にピンを選んでいれば触覚だけ鳴らす() {
        let plan = policy.plan(for: request(record: .municipality(.milestone), hasSelectedPlace: true))
        #expect(plan?.timeline == .settledAtOnce(haptic: .levelChange, completionOffset: .milliseconds(350)))
        #expect(plan?.waitsForCamera == false)
    }

    @Test func 区域の形が未読込なら触覚だけ鳴らす() {
        let plan = policy.plan(for: request(record: .municipality(.firstVisit), isBoundaryLoaded: false))
        #expect(plan?.timeline == .settledAtOnce(haptic: .success, completionOffset: .milliseconds(350)))
    }

    @Test func 視差効果を減らす設定では段階を踏まず一度で戻して400ミリ秒後にシートを出す() {
        let plan = policy.plan(for: request(record: .municipality(.firstVisit), reduceMotion: true))
        #expect(plan?.timeline == .settledAtOnce(haptic: .success, completionOffset: .milliseconds(400)))
        #expect(plan?.waitsForCamera == true)
    }

    @Test func 都道府県の表示で段階が変わらない初訪問は触覚とシートだけ() {
        let plan = policy.plan(for: request(
            record: .municipality(.firstVisit), isPrefectureDisplay: true, previous: .started, current: .started
        ))
        #expect(plan?.timeline == .settledAtOnce(haptic: .success, completionOffset: .milliseconds(350)))
        #expect(plan?.waitsForCamera == false)
    }

    @Test func 都道府県の表示で段階が上がると都道府県の面で見せる() {
        let plan = policy.plan(for: request(
            record: .municipality(.milestone), isPrefectureDisplay: true, previous: .started, current: .quarter
        ))
        #expect(plan == MapAreaPlacementPlan(
            scope: .prefecture, code: "13",
            timeline: .prefectureLevelUp(to: .quarter, haptic: .levelChange), waitsForCamera: true
        ))
    }

    @Test func 都道府県の表示で初めての都道府県を記録すると都道府県の面で見せ800ミリ秒後に次へ進む() {
        let plan = policy.plan(for: request(
            record: .prefecture, isPrefectureDisplay: true, previous: .unvisited, current: .started
        ))
        #expect(plan?.scope == .prefecture)
        #expect(plan?.timeline.firstHaptic == .levelChange)
        #expect(plan?.timeline.completionOffset == .milliseconds(800))
    }

    @Test func 市区町村の表示で都道府県を記録したときは触覚だけで従来どおり350ミリ秒後に次へ進む() {
        let plan = policy.plan(for: request(record: .prefecture, previous: .unvisited, current: .started))
        #expect(plan?.timeline == .settledAtOnce(haptic: .levelChange, completionOffset: .milliseconds(350)))
    }

    @Test func 記録中の見た目は表示に合わせて市区町村か都道府県の区域に付ける() {
        let municipality = policy.recordingEmphasis(
            municipalityCode: "13101", prefectureCode: "13", isPrefectureDisplay: false, prefectureLevel: .started
        )
        #expect(municipality == MunicipalityEmphasis(
            scope: .municipality, code: "13101", look: MapAreaEffectTimeline.recordingMunicipalityLook
        ))
        let prefecture = policy.recordingEmphasis(
            municipalityCode: "13101", prefectureCode: "13", isPrefectureDisplay: true, prefectureLevel: .half
        )
        #expect(prefecture == MunicipalityEmphasis(
            scope: .prefecture, code: "13", look: MapAreaEffectLook(fill: .teal(0.39))
        ))
    }

    private func request(
        record: MapAreaRecord,
        isPrefectureDisplay: Bool = false,
        previous: PrefectureConquestLevel = .started,
        current: PrefectureConquestLevel = .started,
        reduceMotion: Bool = false,
        isSheetExpanded: Bool = false,
        hasSelectedPlace: Bool = false,
        isBoundaryLoaded: Bool = true
    ) -> MapAreaPlacementRequest {
        MapAreaPlacementRequest(
            record: record, municipalityCode: "13101", prefectureCode: "13",
            isPrefectureDisplay: isPrefectureDisplay,
            previousPrefectureLevel: previous, prefectureLevel: current,
            reduceMotion: reduceMotion, isSheetExpanded: isSheetExpanded,
            hasSelectedPlace: hasSelectedPlace, isBoundaryLoaded: isBoundaryLoaded
        )
    }
}

@MainActor
struct CurrentAreaPulsePolicyTests {
    private let policy = CurrentAreaPulsePolicy()

    @Test func 止める条件が1つも無ければ脈打つ() {
        #expect(policy.canPulse(in: CurrentAreaPulseEnvironment(), isLowPowerModeEnabled: false))
    }

    @Test func 止める条件のどれか1つに当たれば脈打たない() {
        let blockers: [(inout CurrentAreaPulseEnvironment) -> Void] = [
            { $0.reduceMotion = true },
            { $0.isSceneActive = false },
            { $0.isSheetExpanded = true },
            { $0.hasSelectedPlace = true },
            { $0.isPresentingCeremony = true },
            { $0.isNationwideDisplay = true },
            { $0.isJapanIntroPending = true },
        ]
        for block in blockers {
            var environment = CurrentAreaPulseEnvironment()
            block(&environment)
            #expect(!policy.canPulse(in: environment, isLowPowerModeEnabled: false))
        }
    }

    @Test func 低電力モードでは脈打たない() {
        #expect(!policy.canPulse(in: CurrentAreaPulseEnvironment(), isLowPowerModeEnabled: true))
    }

    @Test func 区域が画面上で44pt以上に見えていれば画面内とみなす() {
        // 横幅400ptの地図に、地図座標で幅4,000の範囲を映している(1pt = 10)。
        let visible = MKMapRect(x: 0, y: 0, width: 4_000, height: 8_000)
        let area = MKMapRect(x: 100, y: 100, width: 440, height: 100)
        #expect(policy.isAreaOnScreen(area, visibleRect: visible, mapWidth: 400))
    }

    @Test func 区域が画面上で44pt未満なら画面内とみなさない() {
        let visible = MKMapRect(x: 0, y: 0, width: 4_000, height: 8_000)
        let area = MKMapRect(x: 100, y: 100, width: 430, height: 430)
        #expect(!policy.isAreaOnScreen(area, visibleRect: visible, mapWidth: 400))
    }

    @Test func 画面からはみ出した部分は大きさに数えない() {
        let visible = MKMapRect(x: 0, y: 0, width: 4_000, height: 8_000)
        // 幅2,000のうち画面内は右端の300(30pt)だけ。
        let area = MKMapRect(x: 3_700, y: 100, width: 2_000, height: 300)
        #expect(!policy.isAreaOnScreen(area, visibleRect: visible, mapWidth: 400))
    }

    @Test func 区域が画面外なら画面内とみなさない() {
        let visible = MKMapRect(x: 0, y: 0, width: 4_000, height: 8_000)
        let area = MKMapRect(x: 10_000, y: 10_000, width: 2_000, height: 2_000)
        #expect(!policy.isAreaOnScreen(area, visibleRect: visible, mapWidth: 400))
    }

    @Test func 形や表示範囲がまだ分からなければ画面内とみなさない() {
        let visible = MKMapRect(x: 0, y: 0, width: 4_000, height: 8_000)
        #expect(!policy.isAreaOnScreen(nil, visibleRect: visible, mapWidth: 400))
        #expect(!policy.isAreaOnScreen(visible, visibleRect: nil, mapWidth: 400))
        #expect(!policy.isAreaOnScreen(visible, visibleRect: visible, mapWidth: 0))
    }
}

@MainActor
struct PrefectureConquestLevelAfterRecordingTests {
    /// 市区町村を`total`件持ち、そのうち先頭`visited`件を訪れた都道府県。
    private func prefecture(visited: Int, total: Int, isExplicitlyVisited: Bool = false) -> PrefectureExploration {
        let municipalities = (0..<total).map { index in
            ExplorationMunicipality(
                code: String(format: "13%03d", index), name: "市\(index)",
                prefectureCode: "13", prefectureName: "東京都", isPrefecture: false
            )
        }
        return PrefectureExploration(
            code: "13", name: "東京都", municipalities: municipalities,
            visitedCodes: Set(municipalities.prefix(visited).map(\.code)),
            isExplicitlyVisited: isExplicitlyVisited
        )
    }

    @Test func 段階の順序は未訪問から完全踏破へ上がっていく() {
        #expect(PrefectureConquestLevel.unvisited < .started)
        #expect(PrefectureConquestLevel.threeQuarters < .complete)
    }

    @Test func 未訪問の市区町村を記録すると次の段階に上がることがある() {
        // 8件中1件→2件で25%に届く。
        let level = PrefectureConquestLevel.afterRecording(municipalityCode: "13001", in: prefecture(visited: 1, total: 8))
        #expect(level == .quarter)
    }

    @Test func 記録済みの市区町村をもう一度記録しても段階は変わらない() {
        let level = PrefectureConquestLevel.afterRecording(municipalityCode: "13000", in: prefecture(visited: 1, total: 8))
        #expect(level == .started)
    }

    @Test func 踏破率の分母に入らないコードを記録しても段階は変わらない() {
        let level = PrefectureConquestLevel.afterRecording(municipalityCode: "13999", in: prefecture(visited: 1, total: 8))
        #expect(level == .started)
    }

    @Test func 都道府県単独の記録をつけると未訪問から最初の段階になる() {
        #expect(PrefectureConquestLevel.afterRecordingPrefecture(prefecture(visited: 0, total: 8)) == .started)
    }
}

@MainActor
struct MapAreaEffectControllerTests {
    @Test func 記録を始めると記録中の見た目を出し取り消すと通常の見た目に戻る() {
        let controller = MapAreaEffectController()
        let emphasis = MunicipalityEmphasis(
            scope: .municipality, code: "13101", look: MapAreaEffectTimeline.recordingMunicipalityLook
        )

        controller.beginRecording(emphasis)
        #expect(controller.phase == .placing)
        #expect(controller.emphasis == emphasis)

        controller.cancelRecording()
        #expect(controller.phase == .idle)
        #expect(controller.emphasis == nil)
    }

    @Test func 演出を省く場合は触覚を鳴らして通常の見た目に戻ってから戻ってくる() async {
        let controller = MapAreaEffectController()
        controller.beginRecording(MunicipalityEmphasis(
            scope: .municipality, code: "13101", look: MapAreaEffectTimeline.recordingMunicipalityLook
        ))
        let plan = MapAreaPlacementPlan(
            scope: .municipality, code: "13101",
            timeline: .settledAtOnce(haptic: .success, completionOffset: .milliseconds(10)), waitsForCamera: false
        )

        await controller.play(plan, cameraArrival: nil)

        #expect(controller.emphasis == nil)
        #expect(controller.hapticTrigger?.haptic == .success)
        #expect(controller.phase == .idle)
    }

    @Test func 演出の途中で落ち着かせても待っている側に戻ってくる() async {
        let controller = MapAreaEffectController()
        let plan = MapAreaPlacementPlan(
            scope: .municipality, code: "13101", timeline: .municipalityMilestone, waitsForCamera: false
        )

        async let finished: Void = controller.play(plan, cameraArrival: nil)
        try? await Task.sleep(for: .milliseconds(150))
        controller.settleImmediately()
        await finished

        #expect(controller.emphasis == nil)
        #expect(controller.phase == .idle)
    }

    @Test func 区域が画面に見えていなければ脈打たずにすぐ戻る() async {
        let controller = MapAreaEffectController()

        // カメラが一度も止まっておらず表示範囲が分からない。
        await controller.playArrivalPulse(code: "13101") { MKMapRect(x: 0, y: 0, width: 100, height: 100) }

        #expect(controller.phase == .idle)
        #expect(controller.emphasis == nil)
    }

    @Test func 同じ区域では脈打ちを一度しか試みない() async {
        let controller = MapAreaEffectController()
        let area = MKMapRect(x: 0, y: 0, width: 2_000, height: 2_000)

        // 1回目は表示範囲が分からず見送る。
        await controller.playArrivalPulse(code: "13101") { area }
        // 区域が見えるようになっても、同じ区域ではもう脈打たずにすぐ戻る(時間のかかる脈打ちを待たない)。
        controller.updateMapWidth(400)
        controller.cameraDidSettle(visibleRect: MKMapRect(x: 0, y: 0, width: 4_000, height: 8_000))
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await controller.playArrivalPulse(code: "13101") { area }
        }

        #expect(elapsed < .milliseconds(800))
        #expect(!controller.isPulsing)
        #expect(controller.emphasis == nil)
    }
}
