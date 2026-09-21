import Foundation

/// 一条搜索结果。各家返回的字段名千奇百怪，统一收敛成这三样
struct SearchResult: Equatable {
    let title: String
    let url: String
    /// 摘要。有的家给全文，有的只给一两句——统一在适配器里截断
    let snippet: String
}

/// 一家搜索服务。
///
/// 之所以要这一层：Claude 有官方的 `web_search`，但**换到 DeepSeek / GPT
/// 就完全没有搜索了**。抽出协议之后，搜索能力跟模型供应商解耦——
/// 用哪家模型都能搜，用户自己填 key。
protocol SearchProvider {
    /// 适配器都是无状态的 struct，要求一个空 init 才能从元类型把它建出来
    /// （`SearchSettings.all` 存的是类型，不是实例）
    init()

    /// 存 key 用的稳定标识，别跟着显示名改
    static var id: String { get }
    static var displayName: String { get }
    /// 需不需要 API Key。SearXNG 是自建的，不需要
    static var needsKey: Bool { get }
    /// 需不需要填地址（自建服务才要）
    static var needsBaseURL: Bool { get }
    /// 去哪儿申请 key，显示在设置里
    static var keyHint: String { get }

    /// 搜。抛错就抛错——上层会把原因显示给用户，不要吞
    func search(_ query: String, limit: Int, key: String, baseURL: String) async throws -> [SearchResult]
}

/// 各家共用的 HTTP 收发。把「发请求 + 认状态码 + 解 JSON」这段重复代码收进来，
/// 每个适配器只剩「怎么拼请求」和「怎么读结果」两件事
enum SearchHTTP {
    static func json(url: URL,
                     method: String = "GET",
                     headers: [String: String] = [:],
                     body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SearchError.badResponse }
        guard (200...299).contains(http.statusCode) else {
            throw SearchError.http(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // 有的家顶层直接给数组，包一层再交出去
            if let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
                return ["_array": array]
            }
            throw SearchError.badResponse
        }
        return json
    }

    /// 摘要统一截断。搜索结果是要塞进上下文的，一条几千字会把窗口吃光
    static func trim(_ text: String, _ limit: Int = 500) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count <= limit ? clean : String(clean.prefix(limit)) + "…"
    }

    static func encode(_ query: String) -> String {
        query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    }
}

enum SearchError: LocalizedError {
    case notConfigured(String)
    case badResponse
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .notConfigured(let name):
            return "还没配好 \(name)，去「设置 → 搜索」里填一下"
        case .badResponse:
            return "搜索服务回的内容看不懂"
        case .http(let code, let body):
            return body.isEmpty ? "搜索服务返回 HTTP \(code)" : "HTTP \(code)：\(body)"
        case .empty:
            return "没搜到东西"
        }
    }
}

/// 用哪家、key 存哪儿。
///
/// key 一律进 Keychain（复用 `APIKeyStore`，用 `search:<id>` 当标识），
/// 跟模型的 API Key 一个待遇，也不会跟着备份文件流出去。
enum SearchSettings {
    private static let providerKey = "search_provider_id"
    private static let enabledKey = "search_enabled"
    private static let baseURLPrefix = "search_base_url_"

    /// 支持的服务。顺序就是设置页里的顺序
    static let all: [any SearchProvider.Type] = [
        TavilySearch.self, BraveSearch.self, ExaSearch.self,
        SerperSearch.self, JinaSearch.self, SearXNGSearch.self,
    ]

    static func provider(for id: String) -> (any SearchProvider.Type)? {
        all.first { $0.id == id }
    }

    /// 当前选的那家。没选过就是 nil——**不给默认值**：
    /// 默认选一家但没填 key，用户会看到一个一直失败的搜索工具
    static var selectedID: String? {
        get { UserDefaults.standard.string(forKey: providerKey) }
        set { UserDefaults.standard.set(newValue, forKey: providerKey) }
    }

    static var enabled: Bool {
        get { (UserDefaults.standard.object(forKey: enabledKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func key(for id: String) -> String { APIKeyStore.key(for: "search:" + id) }
    static func setKey(_ key: String, for id: String) { APIKeyStore.setKey(key, for: "search:" + id) }

    static func baseURL(for id: String) -> String {
        UserDefaults.standard.string(forKey: baseURLPrefix + id) ?? ""
    }
    static func setBaseURL(_ url: String, for id: String) {
        UserDefaults.standard.set(url, forKey: baseURLPrefix + id)
    }

    /// 配好了没：选了一家，而且它要的东西都填了
    static var isReady: Bool {
        guard enabled, let id = selectedID, let type = provider(for: id) else { return false }
        if type.needsKey && key(for: id).trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if type.needsBaseURL && baseURL(for: id).trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    static var activeName: String? {
        guard let id = selectedID, let type = provider(for: id) else { return nil }
        return type.displayName
    }
}
