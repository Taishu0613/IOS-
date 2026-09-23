import Foundation

/// 訪問の保存をどの操作から始めたか。同じ「更新」という結果でも、どこから保存したかで見せ方を変えるために区別する。
enum MapVisitSaveTrigger {
    /// 初めての市区町村で出る誘いシート(MunicipalityFirstVisitSheet)の「記録する」。
    case firstVisitInvitation
    /// 折りたたんだ常駐シートの「再記録」ボタン。
    case rerecordButton
}

/// 結果が「更新」だった時の伝え方。
enum MapVisitUpdateFeedback {
    /// 何もしない。初訪問・節目は専用の儀式シートが祝うため、ここでは重ねて伝えない。
    case none
    /// 再記録ボタンを「更新済み」に変え、地図のピンの上に吹き出しを出す(VoiceOverの読み上げも行う)。
    case inlineConfirmation
    /// 画面には何も足さず、VoiceOverの読み上げだけ行う。
    case announcementOnly
}

/// 記録が完了した時点の画面の状態から、結果の伝え方を決める。
struct MapVisitFeedbackPolicy {
    /// - Parameters:
    ///   - isSheetExpanded: 保存完了の時点でシートを中段以上に広げているか。
    ///   - hasSelectedPlace: 保存完了の時点で地図のピンを選択しているか。
    func updateFeedback(
        for kind: MapVisitResult.Kind,
        trigger: MapVisitSaveTrigger,
        isSheetExpanded: Bool,
        hasSelectedPlace: Bool
    ) -> MapVisitUpdateFeedback {
        guard kind == .update else { return .none }
        // 「更新済み」ボタンと吹き出しは、押した再記録ボタンと現在地のピンが両方見えている時にだけ意味を持つ。
        // 保存中(位置の取得に数秒かかる)にシートを広げた・ピンを選んだ場合は、ボタンが隠れているか
        // 地図が別の場所を映しているため、画面には出さず読み上げだけにする。誘いシート経路で結果が
        // 更新だった場合(誘いを出した後に別の経路で記録済みになった等)も、押したボタンが無いので同じ扱い。
        guard trigger == .rerecordButton, !isSheetExpanded, !hasSelectedPlace else { return .announcementOnly }
        return .inlineConfirmation
    }
}
