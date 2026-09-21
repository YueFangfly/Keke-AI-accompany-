import Foundation

/// 一次模型请求的完整记录
struct RequestLogEntry: Identifiable {
    let id = UUID()
    let at = Date()
    let provider: String
    let model: String
    /// 实际发出去的 system prompt（人设 + 协议说明 + 记忆块）
    let systemPrompt: String
    /// 实际发出去的消息，一行一条
    let messages: [String]
    /// 这次挂了哪些工具
    let tools: [String]
    var durationMs: Int?
    var usage: TokenUsage?
    /// 回复正文（截断）。失败时是错误原因
    var reply: String?
    var failed = false
}

/// 请求日志：看每次**实际发出去了什么**。
///
/// `ErrorLog` 只记失败，可调人设时最需要的恰恰是成功那些——
/// 「我改的人设到底生效了没」「压缩之后历史剩下什么」「工具定义占了多少」，
/// 光看聊天界面全看不出来。
///
/// 这一份还是「trace 绝不进 messages」那条硬约束的**验证手段**：
/// 那条是防，这里是验——能亲眼确认发出去的 payload 里确实没有 trace / 状态文案。
///
/// **默认关**：它把完整的人设和聊天内容留在内存里，不该无声无息地一直开着。
/// **只在内存**：不落盘，关掉 App 就没了——这里面是最私密的那部分内容。
/// **绝不记 API Key**：请求头压根不进这个结构。
@MainActor
final class RequestLog: ObservableObject {
    static let shared = RequestLog()

    @Published private(set) var entries: [RequestLogEntry] = []
    @Published var isRecording: Bool = UserDefaults.standard.bool(forKey: "request_log_on") {
        didSet {
            UserDefaults.standard.set(isRecording, forKey: "request_log_on")
            if !isRecording { entries.removeAll() }   // 关掉就顺手清干净
        }
    }

    /// 每条正文最多留这么多字。留全文的话几十轮就上百 MB
    private let bodyLimit = 4000
    private let limit = 30

    private init() {}

    /// 开始记一次请求，返回它的 id；没开录就返回 nil
    func begin(provider: String, model: String, systemPrompt: String,
               messages: [String], tools: [String]) -> UUID? {
        guard isRecording else { return nil }
        let entry = RequestLogEntry(
            provider: provider, model: model,
            systemPrompt: String(systemPrompt.prefix(bodyLimit)),
            messages: messages.map { String($0.prefix(600)) },
            tools: tools)
        entries.insert(entry, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        return entry.id
    }

    func finish(_ id: UUID?, reply: String, usage: TokenUsage?, durationMs: Int) {
        guard let id, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].reply = String(reply.prefix(bodyLimit))
        entries[index].usage = usage
        entries[index].durationMs = durationMs
    }

    func fail(_ id: UUID?, reason: String) {
        guard let id, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].reply = reason
        entries[index].failed = true
    }

    func clear() { entries.removeAll() }

    /// 整条导成纯文本，方便贴出来看
    func exportText(_ entry: RequestLogEntry) -> String {
        var lines = ["\(entry.provider) / \(entry.model)"]
        if let ms = entry.durationMs { lines.append("耗时 \(UsageFormat.duration(ms))") }
        if let usage = entry.usage, !usage.isEmpty {
            lines.append("token ↑\(UsageFormat.tokens(usage.input + usage.cacheRead + usage.cacheWrite))"
                         + " ↓\(UsageFormat.tokens(usage.output))")
        }
        lines.append("")
        lines.append("=== system ===")
        lines.append(entry.systemPrompt.isEmpty ? "（空）" : entry.systemPrompt)
        lines.append("")
        lines.append("=== 工具（\(entry.tools.count)）===")
        lines.append(entry.tools.isEmpty ? "（没挂工具）" : entry.tools.joined(separator: ", "))
        lines.append("")
        lines.append("=== messages（\(entry.messages.count)）===")
        lines.append(contentsOf: entry.messages)
        lines.append("")
        lines.append("=== 回复 ===")
        lines.append(entry.reply ?? "（还没回来）")
        return lines.joined(separator: "\n")
    }
}
