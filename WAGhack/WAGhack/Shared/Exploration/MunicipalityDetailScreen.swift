import SwiftUI

struct MunicipalityDetailScreen: View {
    let municipality: Municipality?
    let fallbackName: String

    var body: some View {
        List {
            Section("市区町村") {
                LabeledContent("都道府県", value: municipality?.prefectureName ?? "")
                LabeledContent("市区町村", value: municipality?.municipalityName ?? fallbackName)
                LabeledContent("行政区域コード", value: municipality?.code ?? "")
            }

            TriviaSection(
                title: "みどころ",
                content: municipality?.famousThingsTrivia ?? ""
            )

            TriviaSection(
                title: "怪奇・都市伝説",
                content: municipality?.historyTrivia ?? ""
            )

        }
        .navigationTitle(municipality?.municipalityName ?? "市区町村")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TriviaSection: View {
    let title: String
    let content: String

    var body: some View {
        Section(title) {
            // マスタが空欄の場合も「情報なし」へ置き換えず、空欄のまま表示する。
            Text(content)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }
}

