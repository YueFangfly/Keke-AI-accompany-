import Foundation

/// 一台服务器的会话：握手 → 列工具 → 调工具。
///
/// 只做协议这一层，不管重连和界面——那些在 `MCPServerRegistry` 里。
actor MCPConnection {
    private let config: MCPServerConfig
    private let transport: MCPTransport
    private var nextID = 1
    private(set) var tools: [MCPProtocol.ToolDescriptor] = []
    private var handshakeDone = false

    init?(config: MCPServerConfig) {
        guard let url = URL(string: config.url.trimmingCharacters(in: .whitespaces)),
              url.scheme == "http" || url.scheme == "https" else { return nil }
        self.config = config
        let headers = MCPServerStore.headers(for: config.id)
        switch config.transport {
        case .streamableHTTP:
            self.transport = MCPStreamableHTTPTransport(url: url, headers: headers)
        case .sse:
            self.transport = MCPSSETransport(url: url, headers: headers)
        }
    }

    private func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// 握手 + 拉工具清单。返回工具数，失败抛错
    @discardableResult
    func connect() async throws -> Int {
        try await transport.start()

        let result = try await transport.send(MCPProtocol.Request(
            id: takeID(), method: "initialize",
            params: [
                "protocolVersion": MCPProtocol.preferredVersion,
                // 不声明 sampling：克克不给服务器反向调模型的能力
                "capabilities": ["tools": [String: Any]()],
                "clientInfo": ["name": "Keke", "version": "1.0"],
            ]))

        // 服务器可能降级到它支持的版本，照单接受（协议要求客户端能降级）
        if let version = result["protocolVersion"] as? String,
           let http = transport as? MCPStreamableHTTPTransport {
            http.adoptProtocolVersion(version)
        }
        // 协议规定握手完要发这条，不发的话有的服务器不会开始服务
        try await transport.notify(MCPProtocol.notification("notifications/initialized"))
        handshakeDone = true

        tools = try await listTools()
        return tools.count
    }

    private func listTools() async throws -> [MCPProtocol.ToolDescriptor] {
        var collected: [MCPProtocol.ToolDescriptor] = []
        var cursor: String?
        // 工具多的服务器会分页。给个硬上限，免得服务器 cursor 有 bug 时转不出来
        for _ in 0..<20 {
            var params: [String: Any] = [:]
            if let cursor { params["cursor"] = cursor }
            let result = try await transport.send(MCPProtocol.Request(
                id: takeID(), method: "tools/list", params: params.isEmpty ? nil : params))
            let page = (result["tools"] as? [[String: Any]]) ?? []
            collected.append(contentsOf: page.compactMap(MCPProtocol.ToolDescriptor.init))
            guard let next = result["nextCursor"] as? String, !next.isEmpty else { break }
            cursor = next
        }
        return collected
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> (text: String, isError: Bool) {
        guard handshakeDone else { throw MCPError.notConnected }
        let result = try await transport.send(MCPProtocol.Request(
            id: takeID(), method: "tools/call",
            params: ["name": name, "arguments": arguments]))
        return MCPProtocol.toolResultText(result)
    }

    func disconnect() {
        handshakeDone = false
        tools = []
        transport.close()
    }
}
