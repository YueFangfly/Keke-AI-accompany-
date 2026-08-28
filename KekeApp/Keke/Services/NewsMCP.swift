import Foundation

// MARK: - News Article Model

struct NewsArticle: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let link: String
    let source: String
    let pubDate: Date?
}

// MARK: - News Feed Sources

struct NewsFeed: Identifiable, Codable, Equatable {
    var id: String { url }
    let name: String
    let nameEN: String
    let url: String
    let category: String
}

// MARK: - News MCP Module

struct NewsMCP: MCPModule {
    let id = "news"
    let name = "新闻热搜"
    let nameEN = "News & Trending"
    let icon = "newspaper.fill"
    let descriptionZH = "BBC / CNN / Reuters 等主流媒体 + Google 热门头条"
    let descriptionEN = "BBC, CNN, Reuters feeds + Google News trending headlines"

    static let rssFeeds: [NewsFeed] = [
        NewsFeed(name: "BBC 新闻", nameEN: "BBC News", url: "https://feeds.bbci.co.uk/news/rss.xml", category: "rss"),
        NewsFeed(name: "BBC 科技", nameEN: "BBC Tech", url: "https://feeds.bbci.co.uk/news/technology/rss.xml", category: "rss"),
        NewsFeed(name: "CNN 头条", nameEN: "CNN Top", url: "http://rss.cnn.com/rss/edition.rss", category: "rss"),
        NewsFeed(name: "Reuters 头条", nameEN: "Reuters Top", url: "https://www.reutersagency.com/feed/?taxonomy=best-sectors&post_type=best", category: "rss"),
        NewsFeed(name: "NPR 新闻", nameEN: "NPR News", url: "https://feeds.npr.org/1001/rss.xml", category: "rss"),
        NewsFeed(name: "The Guardian", nameEN: "The Guardian", url: "https://www.theguardian.com/world/rss", category: "rss"),
    ]

    static let googleNewsFeeds: [NewsFeed] = [
        NewsFeed(name: "Google 热门（美国）", nameEN: "Google Trending (US)", url: "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en", category: "google"),
        NewsFeed(name: "Google 热门（英国）", nameEN: "Google Trending (UK)", url: "https://news.google.com/rss?hl=en-GB&gl=GB&ceid=GB:en", category: "google"),
        NewsFeed(name: "Google 热门（中文）", nameEN: "Google Trending (CN)", url: "https://news.google.com/rss?hl=zh-CN&gl=CN&ceid=CN:zh-Hans", category: "google"),
    ]

    static var allFeeds: [NewsFeed] { rssFeeds + googleNewsFeeds }

    var toolSchemas: [[String: Any]] {
        [
            ClaudeService.toolSchema(
                name: "get_news",
                description: "获取最新新闻头条。可以从 BBC / CNN / Reuters / NPR / Guardian 的 RSS，"
                    + "或者 Google News 的热门头条来获取。只有她让你看新闻或者问最近有什么事的时候才调用。",
                properties: [
                    "source": ClaudeService.stringSchema(
                        enumValues: ["bbc", "cnn", "reuters", "npr", "guardian", "google_us", "google_uk", "google_cn", "all"],
                        description: "新闻来源：bbc/cnn/reuters/npr/guardian 是具体媒体 RSS，"
                            + "google_us/google_uk/google_cn 是 Google 热门头条，all 返回所有来源的前几条"),
                    "count": ClaudeService.intSchema(description: "返回几条，默认 5，最多 10"),
                ],
                required: ["source"]
            ),
        ]
    }

    func execute(toolName: String, input: [String: Any]) async -> String {
        guard toolName == "get_news" else { return "不认识这个工具" }
        let source = input["source"] as? String ?? "all"
        let count = min(input["count"] as? Int ?? 5, 10)
        let feeds = feedsForSource(source)
        guard !feeds.isEmpty else { return "不认识这个来源：\(source)" }

        var allArticles: [NewsArticle] = []
        for feed in feeds {
            if let articles = await Self.fetchRSS(url: feed.url, sourceName: feed.nameEN) {
                allArticles.append(contentsOf: articles)
            }
        }
        guard !allArticles.isEmpty else { return "新闻加载失败，可能是网络问题" }

        let sorted = allArticles.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        let top = sorted.prefix(count)
        var lines: [String] = []
        for (i, article) in top.enumerated() {
            lines.append("\(i+1). [\(article.source)] \(article.title)")
            if !article.description.isEmpty {
                let desc = article.description.prefix(100)
                lines.append("   \(desc)\(article.description.count > 100 ? "…" : "")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func feedsForSource(_ source: String) -> [NewsFeed] {
        switch source {
        case "bbc": return Self.rssFeeds.filter { $0.url.contains("bbc") }
        case "cnn": return Self.rssFeeds.filter { $0.url.contains("cnn") }
        case "reuters": return Self.rssFeeds.filter { $0.url.contains("reuters") }
        case "npr": return Self.rssFeeds.filter { $0.url.contains("npr") }
        case "guardian": return Self.rssFeeds.filter { $0.url.contains("guardian") }
        case "google_us": return Self.googleNewsFeeds.filter { $0.url.contains("US") }
        case "google_uk": return Self.googleNewsFeeds.filter { $0.url.contains("GB") }
        case "google_cn": return Self.googleNewsFeeds.filter { $0.url.contains("CN") }
        case "all": return Self.allFeeds
        default: return []
        }
    }

    static func fetchRSS(url: String, sourceName: String) async -> [NewsArticle]? {
        guard let feedURL = URL(string: url) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            let parser = RSSParser(sourceName: sourceName)
            return parser.parse(data: data)
        } catch {
            return nil
        }
    }
}

// MARK: - RSS XML Parser

private class RSSParser: NSObject, XMLParserDelegate {
    private let sourceName: String
    private var articles: [NewsArticle] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var insideItem = false

    init(sourceName: String) {
        self.sourceName = sourceName
    }

    func parse(data: Data) -> [NewsArticle] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return articles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" || elementName == "entry" {
            insideItem = true
            currentTitle = ""
            currentDescription = ""
            currentLink = ""
            currentPubDate = ""
        }
        if insideItem && elementName == "link", let href = attributes["href"] {
            currentLink = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "description", "summary", "content": currentDescription += string
        case "link": currentLink += string
        case "pubDate", "published", "updated": currentPubDate += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "item" || elementName == "entry" {
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = stripHTML(currentDescription.trimmingCharacters(in: .whitespacesAndNewlines))
            let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            let date = parseRSSDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
            if !title.isEmpty {
                articles.append(NewsArticle(title: title, description: desc, link: link, source: sourceName, pubDate: date))
            }
            insideItem = false
        }
        currentElement = ""
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private func parseRSSDate(_ dateString: String) -> Date? {
        let formatters: [String] = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formatters {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) { return date }
        }
        return nil
    }
}
