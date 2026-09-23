import Foundation
import os

/// 都道府県・市区町村の代表画像を日本語版Wikipediaから探す、ベストエフォートのサービス。
///
/// 記事名の解決もフィルタリングも簡易なヒューリスティックであり、完全ではない(見出し語の曖昧さ
/// までは解決しきれないケースがある)。失敗しても例外を投げず空配列を返すことで、呼び出し側は
/// 「0枚だった場合」だけを考えればよいようにしている。失敗理由はログに残す(握りつぶさない)。
actor WikipediaImageService {
    static let shared = WikipediaImageService()

    private var cache: [String: [URL]] = [:]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WAGhack", category: "WikipediaImage")
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // 演出を待たせたくないので、応答が途絶えたら早めに諦めて「0枚」にフォールバックする。
        config.timeoutIntervalForRequest = 10
        // Wikimediaは識別できるUser-Agentを要求しており、空だと403を返す。標準のCFNetwork表記でも
        // 通るが、ポリシーに沿ってアプリ名を明示しておく。
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let bundleID = Bundle.main.bundleIdentifier ?? "WAGhack"
        config.httpAdditionalHeaders = ["User-Agent": "Yorimichi/\(version) (\(bundleID); iOS)"]
        session = URLSession(configuration: config)
    }

    /// ファイル名を直接指定して1枚だけ取得する。検索結果任せだと狙った絵にならない
    /// (季節違いの富士山、鳥居が写っていない伏見稲荷など)場面向け。日本儀式のように
    /// 表示が1箇所しかなく、厳選した1枚を確実に出したいケースで使う。
    func curatedImage(fileTitle: String) async -> URL? {
        let cacheKey = "file:\(fileTitle)"
        if let cached = cache[cacheKey]?.first { return cached }
        do {
            let data = try await requestAPI(queryItems: [
                URLQueryItem(name: "titles", value: "File:\(fileTitle)"),
                URLQueryItem(name: "prop", value: "imageinfo"),
                URLQueryItem(name: "iiprop", value: "url"),
                // 帯の1枠は約104×92pt(3倍で約312×276px)。横長写真を高さに合わせて切り抜いても500pxで足りる。
                // 800pxではデコードが重く表示時にコマ落ちするため、都道府県・市区町村の画像と同じ幅に揃える
                // (Wikimediaは決まった幅のサムネイルをキャッシュしているので、既存の値に合わせておく)。
                URLQueryItem(name: "iiurlwidth", value: "500"),
            ])
            let response = try JSONDecoder().decode(ImagesResponse.self, from: data)
            guard let urlString = response.query?.pages?.first?.imageinfo?.first?.thumburl,
                  let url = URL(string: urlString)
            else {
                logger.info("curatedImage 見つからない: \(fileTitle, privacy: .public)")
                return nil
            }
            cache[cacheKey] = [url]
            return url
        } catch {
            logger.error("curatedImage \(fileTitle, privacy: .public): 失敗 \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// `municipalityName`を渡すと市区町村の画像、nilなら都道府県自体の画像を探す。
    func images(prefectureName: String, municipalityName: String? = nil) async -> [URL] {
        let cacheKey = municipalityName.map { "\(prefectureName)|\($0)" } ?? prefectureName
        if let cached = cache[cacheKey] { return cached }
        do {
            let urls = try await fetchImages(prefectureName: prefectureName, municipalityName: municipalityName)
            // 成功した結果だけキャッシュする。キャンセル(シートを早く閉じた等)や一時的な通信失敗を
            // 空配列としてキャッシュすると、その市区町村は再起動まで二度と画像が出なくなってしまう。
            cache[cacheKey] = urls
            logger.info("\(cacheKey, privacy: .public): \(urls.count)枚")
            return urls
        } catch is CancellationError {
            logger.info("\(cacheKey, privacy: .public): キャンセル")
            return []
        } catch {
            logger.error("\(cacheKey, privacy: .public): 失敗 \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func fetchImages(prefectureName: String, municipalityName: String?) async throws -> [URL] {
        let title: String?
        if let municipalityName {
            title = try await resolveMunicipalityTitle(prefectureName: prefectureName, municipalityName: municipalityName)
        } else {
            title = try await searchTopTitle(query: prefectureName)
        }
        guard let title else {
            logger.info("記事が見つからない: \(prefectureName, privacy: .public) \(municipalityName ?? "", privacy: .public)")
            return []
        }
        logger.debug("記事名を解決: \(title, privacy: .public)")
        return try await fetchArticleImages(title: title)
    }

    /// 「都道府県名+市区町村名」で検索すると同名市区町村(例:府中市)を正しく区別できる一方、
    /// 小さな町村では逆に都道府県自体の記事に負けることがある(記事の情報量で負けるため)。
    /// そこで「結果のタイトルに市区町村名そのものが含まれているか」だけを検証し、含まれて
    /// いなければ市区町村名単独の検索に取り直す。
    private func resolveMunicipalityTitle(prefectureName: String, municipalityName: String) async throws -> String? {
        if let combined = try await searchTopTitle(query: prefectureName + municipalityName),
           combined.contains(municipalityName) {
            return combined
        }
        return try await searchTopTitle(query: municipalityName)
    }

    private func searchTopTitle(query: String) async throws -> String? {
        let data = try await requestAPI(queryItems: [
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: "1"),
        ])
        return try JSONDecoder().decode(SearchResponse.self, from: data).query.search.first?.title
    }

    /// 記事内で使われている画像を取得し、実写真らしいものだけに絞る。ロゴ・旗・紋章・地図・
    /// アイコン類はほぼ全てSVGで配信されているため、拡張子をjpg/jpegに限定するだけで
    /// 驚くほどよく除外できる(実際のWikipedia記事で検証済み)。
    private func fetchArticleImages(title: String) async throws -> [URL] {
        let data = try await requestAPI(queryItems: [
            URLQueryItem(name: "titles", value: title),
            URLQueryItem(name: "generator", value: "images"),
            URLQueryItem(name: "gimlimit", value: "40"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url"),
            URLQueryItem(name: "iiurlwidth", value: "500"),
        ])
        let response = try JSONDecoder().decode(ImagesResponse.self, from: data)
        let photoExtensions = [".jpg", ".jpeg"]
        let urls = (response.query?.pages ?? [])
            .filter { page in photoExtensions.contains { page.title.lowercased().hasSuffix($0) } }
            .compactMap { $0.imageinfo?.first?.thumburl }
            .compactMap(URL.init(string:))
        return Array(urls.prefix(3))
    }

    private func requestAPI(queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(string: "https://ja.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ] + queryItems
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return data
    }

    private struct SearchResponse: Decodable {
        struct Query: Decodable { let search: [Result] }
        struct Result: Decodable { let title: String }
        let query: Query
    }

    private struct ImagesResponse: Decodable {
        struct Query: Decodable { let pages: [Page]? }
        struct Page: Decodable {
            let title: String
            let imageinfo: [ImageInfo]?
        }
        struct ImageInfo: Decodable { let thumburl: String? }
        let query: Query?
    }
}
