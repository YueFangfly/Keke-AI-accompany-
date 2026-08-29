import Foundation

/// 用户自己加的那些 MCP 服务器：增删改、连接状态、拿到能用的工具。
///
/// 跟内置的 `MCPRegistry`（翻译/汇率/天气那 7 个）是两回事，
/// 两边最后都汇成 `Tool` 交给编排层，模型看到的是一份统一的工具清单。
@MainActor
final class MCPServerRegistry: ObservableObject {
    static let shared = MCPServerRegistry()

    @Published private(set) var servers: [MCPServerConfig] = []
    @Published private(set) var status: [UUID: MCPStatus] = [:]
    /// 每台服务器上报的工具清单（连上之后才有）
    @Published private(set) var discovered: [UUID: [MCPProtocol.ToolDescriptor]] = [:]

    private var connections: [UUID: MCPConnection] = [:]
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]
    /// 重连用已有的那套退避策略，不再自己写一份
    private let retry = RetryPolicy(maxAttempts: 4, baseDelay: 2, maxDelay: 30, retryAfterCeiling: 30)

    private init() {
        servers = MCPServerStore.load()
    }

    // MARK: - 增删改

    func add(_ config: MCPServerConfig, headers: [String: String]) {
        servers.append(config)
        MCPServerStore.setHeaders(headers, for: config.id)
        persist()
        Task { await connect(config.id) }
    }

    func update(_ config: MCPServerConfig, headers: [String: String]?) {
        guard let index = servers.firstIndex(where: { $0.id == config.id }) else { return }
        let needsReconnect = servers[index].url != config.url
            || servers[index].transport != config.transport
            || servers[index].enabled != config.enabled
            || headers != nil
        servers[index] = config
        if let headers { MCPServerStore.setHeaders(headers, for: config.id) }
        persist()
        // 改名字、改工具开关不用重连——重连要重新握手，白等好几秒
        if needsReconnect { Task { await connect(config.id) } }
    }

    func remove(_ id: UUID) {
        reconnectTasks[id]?.cancel()
        reconnectTasks[id] = nil
        let connection = connections.removeValue(forKey: id)
        Task { await connection?.disconnect() }
        servers.removeAll { $0.id == id }
        status[id] = nil
        discovered[id] = nil
        MCPServerStore.removeHeaders(for: id)
        persist()
    }

    private func persist() { MCPServerStore.save(servers) }

    // MARK: - 连接

    /// App 起来之后连一遍。逐台连，不并发——失败时错误信息一条条来更好读
    func connectAll() {
        for server in servers where server.enabled {
            Task { await connect(server.id) }
        }
    }

    func connect(_ id: UUID) async {
        guard let config = servers.first(where: { $0.id == id }) else { return }
        reconnectTasks[id]?.cancel()
        reconnectTasks[id] = nil

        guard config.enabled else {
            await teardown(id)
            status[id] = .idle
            return
        }
        guard let connection = MCPConnection(config: config) else {
            status[id] = .failed(MCPError.badURL(config.url).localizedDescription)
            return
        }
        await teardown(id)
        connections[id] = connection
        status[id] = .connecting

        do {
            _ = try await connection.connect()
            let tools = await connection.tools
            discovered[id] = tools
            status[id] = .connected(toolCount: tools.count)
        } catch {
            discovered[id] = []
            status[id] = .failed(error.localizedDescription)
            ErrorLog.shared.record(source: "MCP · \(config.displayName)",
                                   message: error.localizedDescription,
                                   context: "\(config.transport.displayName) \(config.url)")
            scheduleReconnect(id)
        }
    }

    private func teardown(_ id: UUID) async {
        if let existing = connections.removeValue(forKey: id) {
            await existing.disconnect()
        }
    }

    /// 退避重连。次数用完就停在 failed 上，让用户自己点重连——
    /// 无限重试只会一直烧电量，而且配错了地址再试一万次也没用
    private func scheduleReconnect(_ id: UUID) {
        reconnectTasks[id]?.cancel()
        reconnectTasks[id] = Task { [weak self] in
            guard let self else { return }
            for attempt in 0..<(self.retry.maxAttempts - 1) {
                let wait = self.retry.delay(attempt: attempt, retryAfter: nil)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if Task.isCancelled { return }
                guard let config = self.servers.first(where: { $0.id == id }), config.enabled else { return }
                self.status[id] = .reconnecting(attempt: attempt + 1, of: self.retry.maxAttempts - 1)
                guard let connection = MCPConnection(config: config) else { return }
                await self.teardown(id)
                self.connections[id] = connection
                do {
                    _ = try await connection.connect()
                    let tools = await connection.tools
                    self.discovered[id] = tools
                    self.status[id] = .connected(toolCount: tools.count)
                    return
                } catch {
                    self.status[id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 给编排层的工具

    /// 当前能用的远端工具。只包含：服务器开着 + 连上了 + 这个工具没被关掉。
    /// **按名字排序**——工具清单是缓存前缀的第一段，顺序一变整个 prompt cache 就作废
    func enabledTools() -> [Tool] {
        var tools: [Tool] = []
        for config in servers where config.enabled {
            guard let connection = connections[config.id],
                  status[config.id]?.isConnected == true,
                  let descriptors = discovered[config.id] else { continue }
            for descriptor in descriptors {
                let setting = config.setting(for: descriptor.name)
                guard setting.enabled else { continue }
                tools.append(MCPRemoteTool(serverID: config.id, serverName: config.displayName,
                                           descriptor: descriptor,
                                           needsApproval: setting.needsApproval,
                                           connection: connection))
            }
        }
        return tools.sorted { $0.name < $1.name }
    }
}
