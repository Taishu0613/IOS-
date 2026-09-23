import Testing
@testable import WAGhack

@MainActor
struct MapVisitFeedbackPolicyTests {
    // MARK: - MapVisitResult.kind

    @Test func 節目を跨いだ初訪問は節目として扱う() {
        let result = MapVisitResult(municipalityName: "千代田区", isFirstVisit: true, milestone: 25)
        #expect(result.kind == .milestone)
    }

    @Test func 節目の無い初訪問は初訪問として扱う() {
        let result = MapVisitResult(municipalityName: "千代田区", isFirstVisit: true, milestone: nil)
        #expect(result.kind == .firstVisit)
    }

    @Test func 初訪問でも節目でもなければ更新として扱う() {
        let result = MapVisitResult(municipalityName: "千代田区", isFirstVisit: false, milestone: nil)
        #expect(result.kind == .update)
    }

    // MARK: - MapVisitFeedbackPolicy

    @Test func 折りたたみ中でピン未選択の再記録による更新はボタンと吹き出しで伝える() {
        let feedback = MapVisitFeedbackPolicy().updateFeedback(
            for: .update, trigger: .rerecordButton, isSheetExpanded: false, hasSelectedPlace: false
        )
        #expect(feedback == MapVisitUpdateFeedback.inlineConfirmation)
    }

    @Test func 保存完了時にシートを広げていれば再記録の更新も読み上げだけにする() {
        let feedback = MapVisitFeedbackPolicy().updateFeedback(
            for: .update, trigger: .rerecordButton, isSheetExpanded: true, hasSelectedPlace: false
        )
        #expect(feedback == MapVisitUpdateFeedback.announcementOnly)
    }

    @Test func 保存完了時にピンを選択していれば再記録の更新も読み上げだけにする() {
        let feedback = MapVisitFeedbackPolicy().updateFeedback(
            for: .update, trigger: .rerecordButton, isSheetExpanded: false, hasSelectedPlace: true
        )
        #expect(feedback == MapVisitUpdateFeedback.announcementOnly)
    }

    @Test func 誘いシートからの保存が更新だった場合は読み上げだけにする() {
        let feedback = MapVisitFeedbackPolicy().updateFeedback(
            for: .update, trigger: .firstVisitInvitation, isSheetExpanded: false, hasSelectedPlace: false
        )
        #expect(feedback == MapVisitUpdateFeedback.announcementOnly)
    }

    @Test func 初訪問と節目は経路や画面の状態に関わらず儀式シートに任せて何もしない() {
        let policy = MapVisitFeedbackPolicy()
        for kind in [MapVisitResult.Kind.firstVisit, .milestone] {
            for trigger in [MapVisitSaveTrigger.rerecordButton, .firstVisitInvitation] {
                for isSheetExpanded in [false, true] {
                    for hasSelectedPlace in [false, true] {
                        let feedback = policy.updateFeedback(
                            for: kind, trigger: trigger, isSheetExpanded: isSheetExpanded, hasSelectedPlace: hasSelectedPlace
                        )
                        #expect(feedback == MapVisitUpdateFeedback.none)
                    }
                }
            }
        }
    }

    // MARK: - MapViewModel.Operation.statusText

    @Test func 再記録の保存中はシートを伸ばす進行文言を出さない() {
        #expect(MapViewModel.Operation.saving(.rerecordButton).statusText == nil)
    }

    @Test func 誘いシートからの保存中は進行文言を出す() {
        #expect(MapViewModel.Operation.saving(.firstVisitInvitation).statusText == "訪問を記録しています…")
    }
}
