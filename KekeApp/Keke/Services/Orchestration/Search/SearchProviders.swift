import Foundation

// 六家搜索服务的适配器。每个只干两件事：怎么拼请求、怎么读结果。
// 收发和截断都在 SearchHTTP 里，不重复写。

/// Tavily：给 AI 用的搜索，返回的摘要本身就是整理过的
struct TavilySearch: SearchProvider {
    static let id = "tavily"
    static let displayName = "Tavily"
    static let needsKey = true
    static let needsBaseURL = false
    static let keyHint = "app.tavily.com"

    func search(_ query: String, limit: Int, key: String, baseURL: String) async throws -> [SearchResult] {
        guard let url = URL(string: "https://api.tavily.com/search") else { throw SearchError.badResponse }
        let json = try await SearchHTTP.json(
            url: url, method: "POST",
            headers: ["Authorization": "Bearer \(key)"],
            body: ["query": query, "max_results": limit, "search_depth": "basic"])
        let results = (json["results"] as? [[String: Any]]) ?? []
        return results.compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            return SearchResult(title: (item["title"] as? String) ?? url, url: url,
                                snippet: SearchHTTP.trim((item["content"] as? String) ?? ""))
        }
    }
}

/// Brave：独立索引，不转 Google
struct BraveSearch: SearchProvider {
    static let id = "brave"
    static let displayName = "Brave Search"
    static let needsKey = true
    static let needsBaseURL = false
    static let keyHint = "brave.com/search/api"

    func search(_ query: String, limit: Int, key: String, baseURL: String) async throws -> [SearchResult] {
        let q = SearchHTTP.encode(query)
        guard let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(q)&count=\(limit)")
        else { throw SearchError.badResponse }
        let json = try await SearchHTTP.json(
            url: url, headers: ["X-Subscription-Token": key, "Accept": "application/json"])
        let web = json["web"] as? [String: Any]
        let results = (web?["results"] as? [[String: Any]]) ?? []
        return results.compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            return SearchResult(title: (item["title"] as? String) ?? url, url: url,
                                snippet: SearchHTTP.trim((item["description"] as? String) ?? ""))
        }
    }
}

/// Exa：语义检索，能直接把正文取回来
struct ExaSearch: SearchProvider {
    static let id = "exa"
    static let displayName = "Exa"
    static let needsKey = true
    static let needsBaseURL = false
    static let keyHint = "exa.ai"

    func search(_ query: String, limit: Int, key: String, baseURL: String) async throws -> [SearchResult] {
        guard let url = URL(string: "https://api.exa.ai/search") else { throw SearchError.badResponse }
        let json = try await SearchHTTP.json(
            url: url, method: "POST", headers: ["x-api-key": key],
            body: ["query": query, "numResults": limit,
                   // 让它顺带把正文截一段回来，省一次 web_fetch
                   "contents": ["text": ["maxCharacters": 600]]])
        let results = (json["results"] as? [[String: Any]]) ?? []
        return results.compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            return SearchResult(title: (item["title"] as? String) ?? url, url: url,
                                snippet: SearchHTTP.trim((item["text"] as? String) ?? ""))
        }
    }
}

/// Serper：Google 的结果，便宜
struct SerperSearch: SearchProvider {
    static let id = "serper"
    static let displayName = "Serper (Google)"
    static let needsKey = true
    static let needsBaseURL = false
    static let keyHint = "serper.dev"

    func search(_ query: String, limit: Int, key: String, baseURL: String) async throws -> [SearchResult] {
        guard let url = URL(string: "https://google.serper.dev/search") else { throw SearchError.badResponse }
        let json = try await SearchHTTP.json(
            url: url, method: "POST", headers: ["X-API-KEY": key],
            body: ["q": query, "num": limit])
        let results = (json["organic"] as? [[String: Any]]) ?? []
        return results.compactMap { item in
            guard let url = item["link"] as? String else { return nil }
            return SearchResult(title: (item["title"] as? String) ?? url, url: url,
                                snippet: SearchHTTP.trim((item["snippet"] as? String) ?? ""))
        }
    }
}

/// Jina Reader 的搜索端点：直接返回抓好的正文
struct JinaSearch: SearchProvider {
    static let id = "jina"
    static let displayName = "Jina"
    static let needsKey = true
    static let needsBaseURL = false
    static let keyHint = "jina.ai"

    func search(_ query: String, limit: Int, key: String, baseURL: String) async throws -> [SearchResult] {
        let q = SearchHTTP.encode(query)
        guard let url = URL(string: "https://s.jina.ai/\(q)") else { throw SearchError.badResponse }
        let json = try await SearchHTTP.json(
            url: url, headers: ["Authorization": "Bearer \(key)", "Accept": "application/json"])
        let results = (json["data"] as? [[String: Any]]) ?? []
        return results.prefix(limit).compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            return SearchResult(title: (item["title"] as? String) ?? url, url: url,
                                snippet: SearchHTTP.trim((item["content"] as? String) ?? ""))
        }
    }
}

/// SearXNG：自建的元搜索，不用 key，但要填自己那台的地址
struct SearXNGSearch: SearchProvider {
    static let id = "searxng"
    static let displayName = "SearXNG（自建）"
    static let needsKey = false
    static let needsBaseURL = true
    static let keyHint = "填你自己那台的地址"

    func search(_ query: String, limit: Int, key: String, baseURL: String) async throws -> [SearchResult] {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        let q = SearchHTTP.encode(query)
        guard let url = URL(string: "\(base)/search?q=\(q)&format=json") else {
            throw SearchError.badResponse
        }
        let json = try await SearchHTTP.json(url: url)
        let results = (json["results"] as? [[String: Any]]) ?? []
        return results.prefix(limit).compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            return SearchResult(title: (item["title"] as? String) ?? url, url: url,
                                snippet: SearchHTTP.trim((item["content"] as? String) ?? ""))
        }
    }
}
