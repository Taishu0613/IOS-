/// 都道府県の塗りの濃さの段階。都道府県内の市区町村踏破率から決める。
///
/// 率をそのまま濃さにせず段階に丸めるのは、隣り合う県の差(例: 31%と34%)が見分けられず、
/// 地図が「なんとなくまだら」に見えるだけになるため。区切りは達成バッジ(`ExplorationCount.achievementText`)の
/// 25% / 50% / 75% / 完全踏破と揃え、「あと少しで次の段階」の感覚がバッジと地図で一致するようにしている。
///
/// caseは段階の低い順に並べる(`Comparable`の順序になる。記録で段階が上がったかの判定に使う)。
enum PrefectureConquestLevel: Comparable {
    /// 市区町村の記録も、都道府県単独の記録も無い。
    case unvisited
    /// 訪れたが25%未満。都道府県単独の記録(市区町村0件)もここに入る。
    case started
    case quarter
    case half
    case threeQuarters
    case complete

    init(_ prefecture: PrefectureExploration) {
        guard prefecture.isVisited else {
            self = .unvisited
            return
        }
        let progress = prefecture.progress
        let fraction = progress.fraction
        if progress.total > 0 && progress.visited == progress.total {
            self = .complete
        } else if fraction >= 0.75 {
            self = .threeQuarters
        } else if fraction >= 0.5 {
            self = .half
        } else if fraction >= 0.25 {
            self = .quarter
        } else {
            self = .started
        }
    }
}

extension PrefectureConquestLevel {
    /// `prefecture`に市区町村`code`の記録を1件足したときの段階。記録済みのコードや、踏破率の分母に入らない
    /// コード(区を持つ政令指定都市の親など)なら今と同じ段階になる。
    static func afterRecording(municipalityCode code: String, in prefecture: PrefectureExploration) -> PrefectureConquestLevel {
        guard prefecture.municipalities.contains(where: { $0.code == code }) else { return PrefectureConquestLevel(prefecture) }
        return PrefectureConquestLevel(PrefectureExploration(
            code: prefecture.code, name: prefecture.name, municipalities: prefecture.municipalities,
            visitedCodes: prefecture.visitedCodes.union([code]), isExplicitlyVisited: prefecture.isExplicitlyVisited
        ))
    }

    /// `prefecture`に都道府県単独の記録をつけたときの段階。
    static func afterRecordingPrefecture(_ prefecture: PrefectureExploration) -> PrefectureConquestLevel {
        PrefectureConquestLevel(PrefectureExploration(
            code: prefecture.code, name: prefecture.name, municipalities: prefecture.municipalities,
            visitedCodes: prefecture.visitedCodes, isExplicitlyVisited: true
        ))
    }
}
