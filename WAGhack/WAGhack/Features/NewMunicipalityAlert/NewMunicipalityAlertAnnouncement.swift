import Observation
import SwiftUI

/// 通知機能が追加されたことを、この機能を含む版を初めて起動したときに1回だけ知らせるためのゲート。
/// 版番号ではなく「見たかどうか」を保存するので、新規インストールでも、以降の版から使い始めた人でも1回出る。
/// 既にいずれかのモードを選んでいる人(機能を知っている人)には出さない。
@MainActor
@Observable
final class NewMunicipalityAlertAnnouncementGate {
    private static let seenKey = "announcement.newMunicipalityAlert.seen"

    private(set) var isPresented: Bool

    private let userDefaults: UserDefaults

    /// TutorialGateと同じく初期値をここで同期的に確定させる。初回描画で一瞬でもfalseになると、
    /// その隙に地図が有効扱いになり、シートや位置情報の許可ダイアログが先に出てしまうため。
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        isPresented = !userDefaults.bool(forKey: Self.seenKey)
            && NewMunicipalityAlertMonitor.loadMode(from: userDefaults) == .off
    }

    func markSeen() {
        userDefaults.set(true, forKey: Self.seenKey)
        isPresented = false
    }
}

/// 「通知機能が追加されました」のお知らせ。チュートリアルの後、地図が操作できるようになる前に重ねて出す。
/// その場でモードを選べるようにし、選んだ直後に通知・位置情報の許可を求める(何のための許可かが分かる場面のため)。
/// 地図の常駐シートや儀式シートと競合しないよう、シートではなくContentViewのZStackに重ねる(チュートリアルと同じ方式)。
struct NewMunicipalityAlertAnnouncement: View {
    let choose: (NewMunicipalityAlertMode) -> Void

    var body: some View {
        ZStack {
            // 裏の地図は操作できない(ContentViewがisActive=falseにしている)ことを、暗くして伝える。
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            ScrollView {
                card
                    .padding(.horizontal, 24)
                    .padding(.vertical, 40)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
            }
            // 大きな文字でもボタンへ届くようスクロールできるようにしつつ、収まる時は中央に置く。
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
        }
    }

    private var card: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Circle().fill(.teal))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("通知機能が追加されました")
                    .font(.title2.weight(.bold))
                Text("まだ記録していない市区町村や都道府県に入ると、アプリを閉じていても通知でお知らせします。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button {
                    choose(.municipality)
                } label: {
                    Text("市区町村ごとに通知する")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    choose(.prefecture)
                } label: {
                    Text("都道府県のみ通知する")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button("今はしない") {
                    choose(.off)
                }
                .padding(.top, 4)
            }
            .controlSize(.large)
            .tint(.teal)

            Text("「旅の記録」からいつでも変更できます。オンにすると、通知と位置情報（常に）の許可を確認します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

#Preview {
    NewMunicipalityAlertAnnouncement(choose: { _ in })
}
