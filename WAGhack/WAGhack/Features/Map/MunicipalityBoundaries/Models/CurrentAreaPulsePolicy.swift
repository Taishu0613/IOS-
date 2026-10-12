import MapKit

/// 現在地の区域の脈打ち(`MapAreaEffectTimeline.currentAreaPulse`)を止めるべき画面の状態。
/// どれか1つでも当てはまれば脈打ちを始めない・途中なら止める。
struct CurrentAreaPulseEnvironment: Equatable {
    /// 視差効果を減らす設定。点滅に近い動きなので出さない。
    var reduceMotion = false
    /// アプリが前面で操作可能か(scenePhaseが.active)。
    var isSceneActive = true
    /// シートを中段・全画面に広げているか。地図の大半が隠れていて見えない。
    var isSheetExpanded = false
    /// 地図のピンを選んでいるか。地図が別の場所を映している。
    var hasSelectedPlace = false
    /// お祝い・都道府県・日本の儀式シートを出しているか。シートの主役を邪魔しない。
    var isPresentingCeremony = false
    /// 全国(都道府県の制覇率)の表示か。市区町村のピースを描いていない。
    var isNationwideDisplay = false
    /// 「日本」の儀式がまだ済んでいないか。誘いシートは儀式の後に回されるため、先に脈打ちだけ見せても繋がらない。
    var isJapanIntroPending = false
}

/// 脈打ちを出してよいかを決める。
struct CurrentAreaPulsePolicy {
    /// 区域が画面上でこれより小さければ出さない。縮小しすぎて点のような区域では、線の太さの変化が
    /// 形の変化に見えず、何が起きたか分からないため。値はタップ領域の最小寸法(HIG)に揃えた。
    static let minimumOnScreenLength: CGFloat = 44

    /// - Parameters:
    ///   - isLowPowerModeEnabled: 低電力モードか。繰り返しの描画を伴う装飾なので省く
    ///     (記録したときの「はまる」演出は1回きりで記録の手応えそのものなので、低電力モードでも残す)。
    func canPulse(in environment: CurrentAreaPulseEnvironment, isLowPowerModeEnabled: Bool) -> Bool {
        !environment.reduceMotion
            && environment.isSceneActive
            && !environment.isSheetExpanded
            && !environment.hasSelectedPlace
            && !environment.isPresentingCeremony
            && !environment.isNationwideDisplay
            && !environment.isJapanIntroPending
            && !isLowPowerModeEnabled
    }

    /// 区域が画面に入っていて、十分な大きさに見えているか。
    /// - Parameters:
    ///   - areaRect: 区域を囲む範囲。形が未読込ならnil(見えていないものとして扱う)。
    ///   - visibleRect: 地図の表示範囲。まだ一度もカメラが止まっていなければnil。
    ///   - mapWidth: 地図の横幅(pt)。表示範囲の横幅と対応させて、地図座標を画面上の長さに換算する。
    func isAreaOnScreen(_ areaRect: MKMapRect?, visibleRect: MKMapRect?, mapWidth: CGFloat) -> Bool {
        guard let areaRect, let visibleRect, mapWidth > 0, visibleRect.width > 0 else { return false }
        let visiblePart = areaRect.intersection(visibleRect)
        guard !visiblePart.isNull, !visiblePart.isEmpty else { return false }
        let pointsPerMapPoint = Double(mapWidth) / visibleRect.width
        // 長い方の辺で判定する。細長い区域でも、長い方向に十分見えていれば縁取りの変化は目に入る。
        let onScreenLength = max(visiblePart.width, visiblePart.height) * pointsPerMapPoint
        return onScreenLength >= Double(Self.minimumOnScreenLength)
    }
}
