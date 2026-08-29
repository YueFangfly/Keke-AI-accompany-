import Foundation

/// MCP（Model Context Protocol）的线上格式。
///
/// 协议本体是 JSON-RPC 2.0，只用到三个方法：`initialize`、`tools/list`、`tools/call`。
/// 服务器主动发来的东西（sampling、通知）一律忽略——克克只是个客户端，不提供采样。
enum MCPProtocol {
    /// 握手时声明的协议版本。服务器不认的话会在 initialize 的回包里给它支持的版本，
    /// 我们照单接受（协议规定客户端要能降级）
    static let preferredVersion = "2025-06-18"
    static let sessionHeader = "Mcp-Session-Id"
    static let versionHeader = "MCP-Protocol-Version"

    /// 一个 JSON-RPC 请求。id 用自增整数，够用且好对号
    struct Request {
        let id: Int
        let method: String
        let params: [String: Any]?

        var body: [String: Any] {
            var json: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
            if let params { json["params"] = params }
            return json
        }
    }

    /// 一条通知（没有 id，服务器不回）
    static func notification(_ method: String, params: [String: Any]? = nil) -> [String: Any] {
        var json: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let params { json["params"] = params }
        return json
    }

    /// 服务器发回来的一条消息。只区分「是不是我等的那条回包」
    struct Response {
        let id: Int?
        let result: [String: Any]?
        let error: String?

        init?(_ json: [String: Any]) {
            guard (json["jsonrpc"] as? String) == "2.0" else { return nil }
            id = json["id"] as? Int
            result = json["result"] as? [String: Any]
            if let err = json["error"] as? [String: Any] {
                let code = err["code"] as? Int
                let message = err["message"] as? String ?? "未知错误"
                error = code.map { "\(message)（\($0)）" } ?? message
            } else {
                error = nil
            }
        }
    }

    /// `tools/list` 里的一个工具
    struct ToolDescriptor: Equatable {
        let name: String
        let description: String
        /// 原样保留服务器给的 JSON Schema。里面的 properties / required
        /// 直接透给模型，不做转换——转换只会引入不一致
        let inputSchema: [String: Any]

        static func == (a: ToolDescriptor, b: ToolDescriptor) -> Bool {
            a.name == b.name && a.description == b.description
        }

        init?(_ json: [String: Any]) {
            guard let name = json["name"] as? String, !name.isEmpty else { return nil }
            self.name = name
            self.description = (json["description"] as? String) ?? ""
            self.inputSchema = (json["inputSchema"] as? [String: Any]) ?? [:]
        }

        var properties: [String: [String: Any]] {
            (inputSchema["properties"] as? [String: [String: Any]]) ?? [:]
        }
        var required: [String] {
            (inputSchema["required"] as? [String]) ?? []
        }
    }

    /// `tools/call` 的回包：把 content 数组里的文本块拼起来。
    /// 图片块暂时只留一句占位——模型看不到图，硬塞 base64 只会烧 token
    static func toolResultText(_ result: [String: Any]) -> (text: String, isError: Bool) {
        let isError = (result["isError"] as? Bool) ?? false
        guard let content = result["content"] as? [[String: Any]] else {
            return ((result["content"] as? String) ?? "", isError)
        }
        let parts: [String] = content.compactMap { block in
            switch block["type"] as? String {
            case "text": return block["text"] as? String
            case "image": return "[图片：模型看不到，已省略]"
            case "resource":
                let resource = block["resource"] as? [String: Any]
                return (resource?["text"] as? String) ?? (resource?["uri"] as? String)
            default: return nil
            }
        }
        return (parts.joined(separator: "\n"), isError)
    }
}

enum MCPError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    case rpc(String)
    case notConnected
    case timeout
    case malformed

    var errorDescription: String? {
        switch self {
        case .badURL(let s): return "服务器地址不对：\(s)"
        case .http(let code, let body):
            return body.isEmpty ? "服务器返回 HTTP \(code)" : "HTTP \(code)：\(body.prefix(200))"
        case .rpc(let message): return message
        case .notConnected: return "还没连上这个服务器"
        case .timeout: return "服务器没有响应"
        case .malformed: return "服务器回的内容看不懂，可能不是 MCP 服务器"
        }
    }
}
