import Foundation

/// 一台用户自己加的 MCP 服务器。
///
/// 存在 UserDefaults 里，**但 headers 不存**——那里面往往是 Bearer token。
/// header 走 Keychain，跟别的密钥一个待遇（见 `MCPServerStore`）。
struct MCPServerConfig: Identifiable, Codable, Equatable {
    enum Transport: String, Codable, CaseIterable, Identifiable {
        /// 2025 版协议的默认传输，新服务器基本都支持
        case streamableHTTP
        /// 旧的 HTTP+SSE，仍有不少服务器只支持这个
        case sse

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .streamableHTTP: return "Streamable HTTP"
            case .sse: return "SSE"
            }
        }
    }

    var id = UUID()
    var name = ""
    var url = ""
    var transport: Transport = .streamableHTTP
    var enabled = true
    /// 工具名 → 用户的设置。没记的工具按默认（开、不需确认）处理
    var toolSettings: [String: ToolSetting] = [:]

    struct ToolSetting: Codable, Equatable {
        var enabled = true
        /// 执行前要不要问一句。第三方服务器给什么工具你事先不知道，
        /// 会删东西、会花钱的那些应该拦一下
        var needsApproval = false
    }

    func setting(for tool: String) -> ToolSetting {
        toolSettings[tool] ?? ToolSetting()
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return URL(string: url)?.host ?? url
    }
}

/// 服务器列表的存取。
///
/// 配置进 UserDefaults，**header 进 Keychain**——header 里常常是
/// `Authorization: Bearer …`，跟 API Key 是一回事，不能躺在 plist 里
/// （也不能跟着备份文件流出去）。
enum MCPServerStore {
    private static let listKey = "mcp_servers"

    static func load() -> [MCPServerConfig] {
        guard let data = UserDefaults.standard.data(forKey: listKey),
              let list = try? JSONDecoder().decode([MCPServerConfig].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [MCPServerConfig]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: listKey)
    }

    // MARK: - headers（Keychain）

    private static func headerKey(_ id: UUID) -> String { "mcp-headers:\(id.uuidString)" }

    static func headers(for id: UUID) -> [String: String] {
        let raw = APIKeyStore.key(for: headerKey(id))
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    static func setHeaders(_ headers: [String: String], for id: UUID) {
        let cleaned = headers.filter {
            !$0.key.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !cleaned.isEmpty else { APIKeyStore.setKey("", for: headerKey(id)); return }
        guard let data = try? JSONEncoder().encode(cleaned),
              let text = String(data: data, encoding: .utf8) else { return }
        APIKeyStore.setKey(text, for: headerKey(id))
    }

    static func removeHeaders(for id: UUID) {
        APIKeyStore.setKey("", for: headerKey(id))
    }
}

/// 一台服务器现在是什么状态。**必须能在界面上看见**——
/// 否则工具静默失效跟没配过一模一样，用户只会觉得"这个模型怎么不会查天气"
enum MCPStatus: Equatable {
    case idle
    case connecting
    case connected(toolCount: Int)
    /// 第几次重试 / 一共几次
    case reconnecting(attempt: Int, of: Int)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .connecting, .reconnecting: return true
        default: return false
        }
    }
}
