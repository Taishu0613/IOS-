import MapKit

/// 地図を区域へ寄せるカメラアニメーションの長さの決め方。
///
/// 長さが一定だと、1km四方から県全体(数百km)まで引くような大きな縮尺の変化が一瞬で終わり、
/// 「パッと切り替わった」ように見える。そこで、縮尺の変化(倍率の2を底とする対数=何段ズームしたか)と
/// 移動距離が大きいほど長くする。長すぎると操作の応答が鈍く感じるため上限を設ける。
nonisolated enum MapCameraMoveDuration {
    /// 近い区域へ寄せるときの長さ。従来の区域へ寄せる移動と同じ。
    static let minimum: TimeInterval = 0.5
    /// 県全体まで引くような大きな変化でも、これより長くしない。
    static let maximum: TimeInterval = 1.2
    /// ズーム1段(表示範囲が2倍・半分)あたりに足す長さ。
    static let secondsPerStep: TimeInterval = 0.12

    /// 今の表示範囲`current`から`target`へ動かすときの長さ。今の範囲が分からなければ最小の長さにする。
    static func duration(from current: MKMapRect?, to target: MKMapRect) -> TimeInterval {
        guard let current, current.width > 0, target.width > 0 else { return minimum }
        let zoomSteps = abs(log2(target.width / current.width))
        // 中心の移動量は、広い方の範囲の幅を1とした割合で測る。画面数個ぶんの移動を1段ほどに数える。
        let centerDistance = hypot(target.midX - current.midX, target.midY - current.midY)
        let panSteps = log2(1 + centerDistance / max(current.width, target.width))
        let duration = minimum + (zoomSteps + panSteps) * secondsPerStep
        return min(max(duration, minimum), maximum)
    }
}
