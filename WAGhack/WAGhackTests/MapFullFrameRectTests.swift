import MapKit
import Testing
@testable import WAGhack

struct MapFullFrameRectTests {
    /// 高さ600ptぶんの表示範囲(1ptあたり10マップポイント)。
    private let visible = MKMapRect(x: 1_000, y: 2_000, width: 4_000, height: 6_000)

    @Test func ヘッダーとシートの裏の分だけ上下に広げる() {
        let rect = MapFullFrameRect.rect(visibleRect: visible, mapHeight: 900, topInset: 200, bottomInset: 100)

        #expect(rect.minY == visible.minY - 2_000)
        #expect(rect.maxY == visible.maxY + 1_000)
    }

    @Test func 横方向は変えない() {
        let rect = MapFullFrameRect.rect(visibleRect: visible, mapHeight: 900, topInset: 200, bottomInset: 100)

        #expect(rect.minX == visible.minX)
        #expect(rect.width == visible.width)
    }

    @Test func セーフエリアを広げていなければそのまま() {
        #expect(MapFullFrameRect.rect(visibleRect: visible, mapHeight: 600, topInset: 0, bottomInset: 0).isSame(as: visible))
    }

    @Test func レイアウト前で高さが分からなければそのまま() {
        #expect(MapFullFrameRect.rect(visibleRect: visible, mapHeight: 0, topInset: 200, bottomInset: 100).isSame(as: visible))
    }
}

private extension MKMapRect {
    func isSame(as other: MKMapRect) -> Bool {
        MKMapRectEqualToRect(self, other)
    }
}
