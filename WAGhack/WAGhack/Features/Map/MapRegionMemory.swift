import Foundation
import MapKit

/// 最後に地図のカメラが止まった時の表示範囲を端末に保存し、次の起動で最初に見せる範囲として使う。
///
/// 起動直後は現在地が分かるまで数秒かかる。その間のカメラを`.automatic`(記録したピン全体が収まる範囲、
/// 多くは日本全体)にすると、全国ファイル(LOD0)を読み込んでから現在地の範囲を読み直すことになり、
/// 境界が出るまでが遅くなる。前回見ていた範囲は現在地の近くであることが多く、県単位の小さなファイルだけで済む。
/// 表示の好みに近い一時的な情報なのでSwiftDataには持たない(`map.showsPlacePins`などと同じ扱い)。
enum MapRegionMemory {
    private static let key = "map.lastRegion"

    /// 保存した範囲。未保存・壊れた値ならnil。
    static func load(from defaults: UserDefaults = .standard) -> MKCoordinateRegion? {
        guard let values = defaults.array(forKey: key) as? [Double], values.count == 4 else { return nil }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: values[0], longitude: values[1]),
            span: MKCoordinateSpan(latitudeDelta: values[2], longitudeDelta: values[3])
        )
        guard CLLocationCoordinate2DIsValid(region.center),
              region.span.latitudeDelta > 0, region.span.latitudeDelta <= 180,
              region.span.longitudeDelta > 0, region.span.longitudeDelta <= 360
        else { return nil }
        return region
    }

    /// カメラが止まるたびに呼ぶ。UserDefaultsへの書き込みは軽く、止まった時だけなので回数も少ない。
    static func save(_ region: MKCoordinateRegion, to defaults: UserDefaults = .standard) {
        defaults.set(
            [region.center.latitude, region.center.longitude, region.span.latitudeDelta, region.span.longitudeDelta],
            forKey: key
        )
    }
}
