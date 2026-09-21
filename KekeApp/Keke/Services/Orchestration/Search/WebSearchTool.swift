import Foundation

/// 把选中的那家搜索服务包成一个 `Tool`。
///
/// 之前只有 Claude 有搜索（官方的 `web_search`），换到 DeepSeek / GPT 就没有了。
/// 现在搜索跟模型供应商解耦：配好一家，用哪个模型都能搜。
struct WebSearchTool: Tool {
    let providerType: any SearchProvider.Type
    let key: String
    let baseURL: String

    /// 名字固定成 `web_search`：模型对这个名字最熟，不用在描述里解释它是干嘛的
    var name: String { "web_search" }

    var descriptionForModel: String {
        "上网搜东西。需要最新信息、或者你不确定的事实时用它。返回若干条结果的标题、网址和摘要。"
    }

    var parameters: [String: [String: Any]] {
        [
            "query": ["type": "string", "description": "搜索关键词"],
            "count": ["type": "integer",
                      "description": "要几条结果，默认 5，最多 10"],
        ]
    }
    var required: [String] { ["query"] }

    /// 搜索结果最占上下文，给一个偏紧的上限
    var maxOutputChars: Int { 4000 }
    var needsSubModel: Bool { false }

    /// 单次最多返回几条。再多对回答质量没什么帮助，只是把上下文吃光
    static let maxCount = 10
    static let defaultCount = 5

    func run(_ input: [String: Any]) async -> ToolOutput {
        let query = ((input["query"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return ToolOutput(text: "没有给搜索词。", isError: true)
        }
        // 模型给的 count 可能是字符串、可能超范围，夹回合理区间
        let raw = (input["count"] as? Int)
            ?? Int((input["count"] as? String) ?? "")
            ?? Self.defaultCount
        let count = min(max(raw, 1), Self.maxCount)

        do {
            let results = try await providerType.init().search(
                query, limit: count, key: key, baseURL: baseURL)
            guard !results.isEmpty else {
                return ToolOutput(text: "「\(query)」没搜到结果。", isExternalData: true)
            }
            let text = results.enumerated().map { index, item in
                "\(index + 1). \(item.title)\n\(item.url)\n\(item.snippet)"
            }.joined(separator: "\n\n")
            // 搜索结果是彻头彻尾的外部数据，不是指令。
            // isExternalData 会让 ToolResultEnvelope 明确标记这一点——
            // 搜到的网页里可能就写着「忽略之前的指令」
            return ToolOutput(text: text, isExternalData: true)
        } catch {
            ErrorLog.shared.record(source: "搜索 · \(providerType.displayName)",
                                   message: error.localizedDescription,
                                   context: query)
            return ToolOutput(text: error.localizedDescription, isError: true)
        }
    }

    /// 配好了就给一个工具，没配好就没有。
    /// 不返回一个「一调就报错」的工具——那只会让模型浪费一轮
    static func configured() -> WebSearchTool? {
        guard SearchSettings.isReady,
              let id = SearchSettings.selectedID,
              let type = SearchSettings.provider(for: id) else { return nil }
        return WebSearchTool(providerType: type,
                             key: SearchSettings.key(for: id),
                             baseURL: SearchSettings.baseURL(for: id))
    }
}
