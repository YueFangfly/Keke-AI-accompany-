import Foundation

/// 把一个远端 MCP 工具包成克克自己的 `Tool`。
///
/// 这一层就是当初把 `Tool` 抽出来的理由：编排层的工具循环、
/// `ToolResultEnvelope` 的包装截断、缓存前缀排序，一行都不用改。
struct MCPRemoteTool: Tool {
    let serverID: UUID
    let serverName: String
    let descriptor: MCPProtocol.ToolDescriptor
    let needsApproval: Bool
    private let connection: MCPConnection

    init(serverID: UUID, serverName: String, descriptor: MCPProtocol.ToolDescriptor,
         needsApproval: Bool, connection: MCPConnection) {
        self.serverID = serverID
        self.serverName = serverName
        self.descriptor = descriptor
        self.needsApproval = needsApproval
        self.connection = connection
    }

    /// 加服务器前缀，避免两台服务器都叫 `search` 时撞名。
    ///
    /// **只留 ASCII 字母数字和下划线**。注意不能用 `isLetter` 判断——
    /// 它对中文也返回 true，而各家 API 的函数名都要求 `[a-zA-Z0-9_-]`，
    /// 一个中文名的工具会让整个请求 400。
    var name: String {
        let tail = Self.asciiSafe(descriptor.name)
        // 名字全是中文时消毒完就空了，用原名的稳定哈希兜底：
        // 保证不同工具不会撞成同一个名字，而且每次启动算出来都一样
        let body = tail.isEmpty ? "t\(Self.stableHash(descriptor.name))" : tail
        return String("\(shortServerTag)_\(body)".prefix(64))
    }

    private var shortServerTag: String {
        let letters = serverName.unicodeScalars
            .filter { CharacterSet.alphanumerics.isSuperset(of: CharacterSet(charactersIn: String($0)))
                      && $0.isASCII }
            .map { String($0) }.joined()
        return letters.isEmpty ? "mcp" : String(letters.prefix(12)).lowercased()
    }

    /// 非 ASCII 字母数字一律换成下划线，并把连续的下划线压成一个
    private static func asciiSafe(_ raw: String) -> String {
        let mapped = raw.unicodeScalars.map { scalar -> Character in
            let ok = scalar.isASCII
                && (("a"..."z").contains(String(scalar)) || ("A"..."Z").contains(String(scalar))
                    || ("0"..."9").contains(String(scalar)) || scalar == "_")
            return ok ? Character(scalar) : "_"
        }
        let collapsed = String(mapped).split(separator: "_", omittingEmptySubsequences: true)
        return collapsed.joined(separator: "_")
    }

    /// FNV-1a。不能用 Swift 的 `hashValue`——它每次启动加的盐不同，
    /// 工具名跟着变会让 prompt cache 每次都失效
    private static func stableHash(_ text: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in Array(text.utf8) {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(hash, radix: 36)
    }

    var descriptionForModel: String {
        let body = descriptor.description.isEmpty ? descriptor.name : descriptor.description
        return "[\(serverName)] \(body)"
    }

    /// schema 原样透传。服务器怎么写的就怎么给模型，中间不做转换——
    /// 转换只会让「模型按 schema 填的参数」和「服务器实际要的参数」对不上
    var parameters: [String: [String: Any]] { descriptor.properties }
    var required: [String] { descriptor.required }

    /// 第三方服务器返回多少内容不受我们控制，给一个偏紧的上限
    var maxOutputChars: Int { 4000 }
    var needsSubModel: Bool { false }

    func run(_ input: [String: Any]) async -> ToolOutput {
        if needsApproval {
            let granted = await MCPApprovalGate.shared.request(
                server: serverName, tool: descriptor.name, arguments: input)
            guard granted else {
                return ToolOutput(text: "用户没有批准这次调用。", isError: true)
            }
        }
        do {
            let (text, isError) = try await connection.callTool(
                name: descriptor.name, arguments: input)
            // 第三方服务器返回的东西是**外部数据**，不是指令。
            // isExternalData 会让 ToolResultEnvelope 明确标记这一点
            return ToolOutput(text: text, isError: isError, isExternalData: true)
        } catch {
            ErrorLog.shared.record(source: "MCP · \(serverName)",
                                   message: error.localizedDescription,
                                   context: descriptor.name)
            return ToolOutput(text: error.localizedDescription, isError: true)
        }
    }
}
