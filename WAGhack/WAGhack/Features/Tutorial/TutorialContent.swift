import SwiftUI

/// 詩の1連。先頭行だけ強調して見せたいことがあるため、連単位で強調可否を持つ。
struct TutorialStanza {
    let lines: [String]
    var isLead = false
}

/// チュートリアルの1ページ。冒頭は詩、以降は実際の機能に紐づく短い説明で構成する。
enum TutorialPage {
    case story(stanzas: [TutorialStanza])
    case feature(icon: String, title: String, body: String, tint: Color)

    static let all: [TutorialPage] = [
        .story(stanzas: introStanzas),
        .feature(
            icon: "mappin.and.ellipse",
            title: "訪れた街を、記録しよう",
            body: "現在地の「この場所を記録する」をタップするだけで、その街があなたの旅の記録に加わります。記録はいつでも何度でも見返せて、市区町村はもちろん都道府県単位でも制覇としてカウント。訪れるたびに、まっさらな日本地図が少しずつ塗り替わっていきます。",
            tint: .teal
        ),
        .feature(
            icon: "book.pages",
            title: "みどころも、怪奇・都市伝説も",
            body: "訪れた街の記録には、意外なみどころや、地元でささやかれる怪奇・都市伝説がまとめられています。新しい発見はきっと話の種に。「今度はあそこへ寄ってみようか」——そんな寄り道のきっかけをくれるはずです。",
            tint: .indigo
        ),
        .feature(
            icon: "location.circle.fill",
            title: "現在地を使って、旅をはじめよう",
            body: "次に出る確認で位置情報の使用を許可すると、今いる場所をすぐ記録できます。あなただけの市区町村探検が、いま始まります！",
            tint: .red
        ),
    ]

    private static let introStanzas: [TutorialStanza] = [
        TutorialStanza(lines: [
            "ようこそ、日本へ。",
            "この国には、47の都道府県と、",
            "1,700を超える市区町村があります。",
        ], isLead: true),
        TutorialStanza(lines: [
            "ネオンが輝く大都市。",
            "海へ続く坂道と踏切。",
            "桜舞う古い町並み。",
            "雪明かりに包まれた山里。",
        ]),
        TutorialStanza(lines: [
            "映画のワンシーンのような風景は、",
            "物語の中だけにあるものではありません。",
        ]),
        TutorialStanza(lines: [
            "いつもの道を少し外れれば、",
            "まだ知らない景色や、",
            "気づかなかった物語に出会えるかもしれない。",
        ]),
        TutorialStanza(lines: [
            "さあ、「よりみち」と一緒に、",
            "日本のまちを歩いてみましょう。",
        ]),
        TutorialStanza(lines: [
            "あなただけの市区町村探検が、",
            "いま、始まります。",
        ]),
    ]
}
