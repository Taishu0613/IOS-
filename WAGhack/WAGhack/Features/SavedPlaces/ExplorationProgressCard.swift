import SwiftUI

struct ExplorationProgressCard: View {
    let title: String
    let progress: ExplorationCount
    var unit: String = "市区町村"
    /// trueならプログレスバー上の主表示を「訪問数 / 総数」に、割合はサブ表示に回す。都道府県のように総数が少なく、実数の方が伝わりやすい場合に使う。
    var emphasizesCount: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(emphasizesCount ? "\(progress.visited) / \(progress.total)　達成" : progress.percentageText)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.teal)
                .monospacedDigit()
            ProgressView(value: progress.fraction)
                .tint(.teal)
                .accessibilityLabel("\(unit)踏破率")
                .accessibilityValue(progress.percentageText)
            Text(emphasizesCount ? "\(progress.percentageText)訪問済み" : "\(progress.visited) / \(progress.total) \(unit)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(progress.achievementText, systemImage: "seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.teal)
            Text(progress.nextGoalText(unit: unit))
                .font(.subheadline)
        }
        .padding(.vertical, 8)
    }
}

struct PrefectureExplorationRow: View {
    let prefecture: PrefectureExploration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(prefecture.name).font(.headline)
                    Spacer()
                    Text(prefecture.progress.percentageText).monospacedDigit()
                }
                VStack(alignment: .leading) {
                    Text(prefecture.name).font(.headline)
                    Text(prefecture.progress.percentageText).monospacedDigit()
                }
            }
            ProgressView(value: prefecture.progress.fraction)
                .tint(.teal)
                .accessibilityLabel("市区町村踏破率")
                .accessibilityValue(prefecture.progress.percentageText)
            Text("\(prefecture.progress.visited) / \(prefecture.progress.total) 市区町村 · \(prefecture.progress.achievementText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
