import SwiftUI

struct MapProgressHeader: View {
    let prefecture: PrefectureExploration?
    let summary: ExplorationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let prefecture {
                Text("\(prefecture.name)  \(prefecture.progress.visited) / \(prefecture.progress.total) 市区町村")
                    .font(.subheadline.weight(.semibold))
                ProgressView(value: prefecture.progress.fraction)
                    .tint(.teal)
                    .accessibilityLabel("市区町村踏破率")
                    .accessibilityValue(prefecture.progress.percentageText)
                Text("\(prefecture.progress.percentageText) · \(prefecture.progress.nextGoalText(unit: "市区町村"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("\(summary.visitedPrefectureCount) / \(summary.prefectures.count) 都道府県を訪問", systemImage: "map")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct MapCurrentPlaceCard: View {
    let name: String?
    let isVisited: Bool
    let statusText: String?
    let errorMessage: String?
    let result: MapVisitResult?
    let save: () -> Void
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let result {
                Label(result.title, systemImage: result.milestone == nil ? "checkmark.seal.fill" : "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(.teal)
            }
            if let statusText {
                ProgressView(statusText).font(.subheadline)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                Button("現在地を再確認", action: refresh)
                    .buttonStyle(.borderedProminent)
            } else {
                Text(name ?? "現在地から旅をはじめよう")
                    .font(.headline)
                Text(isVisited ? "訪問済み · 再訪問も記録できます" : "この場所で、図鑑の1ページを増やそう")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: save) {
                    Label(isVisited ? "再訪問を記録する" : "この場所を記録する", systemImage: isVisited ? "arrow.clockwise" : "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MapSelectedPlaceCard: View {
    let place: SavedPlace
    let close: () -> Void
    let showDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.displayName).font(.headline)
                    Text(place.municipality?.prefectureName ?? "訪問記録")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("選択を解除", systemImage: "xmark.circle.fill", action: close)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(minWidth: 44, minHeight: 44)
            }
            Label("訪問済み", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.teal)
            Text("最終訪問：\(place.savedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
            Button("みどころ・豆知識を見る", systemImage: "book", action: showDetails)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
