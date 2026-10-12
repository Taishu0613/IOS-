import SwiftUI

/// 行政区域データの出典表示。元データ(国土数値情報 N03)はCC BY 4.0のため、アプリ内への表示が必須。
///
/// 文面はデータと一緒に生成される`attribution.txt`を正とし、アプリ側に書き写さない。
struct BoundaryAttributionView: View {
    private let text = Self.bundledText()

    var body: some View {
        if let text {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    /// 同梱ファイルが無い(境界データを組み込まずにビルドした)・読めない場合はnilを返し、何も表示しない。
    /// 出典は補助的な表示で、読めなくても他の機能に影響しないためエラーは伝播させない。
    private static func bundledText(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "attribution", withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

#Preview {
    BoundaryAttributionView()
}
