import Foundation

/// 一条到 MCP 服务器的连接。
///
/// 对上层只暴露「发一个请求，等一个回包」——克克用不到服务器主动推的消息
/// （sampling、进度通知），收到就丢掉。
protocol MCPTransport: AnyObject {
    /// 建立连接。Streamable HTTP 这一步什么都不做，SSE 这一步要等服务器给 POST 地址
    func start() async throws
    func send(_ request: MCPProtocol.Request) async throws -> [String: Any]
    /// 单向通知，不等回包
    func notify(_ body: [String: Any]) async throws
    func close()
}

// MARK: - Streamable HTTP（现行协议）

/// 每个请求 POST 一次，回包可能是 `application/json`（一条），
/// 也可能是 `text/event-stream`（流式发回，得读到我们等的那个 id 为止）。
///
/// 这是 2025 版协议的默认传输，新服务器基本都支持。
final class MCPStreamableHTTPTransport: MCPTransport {
    private let url: URL
    private let headers: [String: String]
    private var sessionID: String?
    private var negotiatedVersion: String?

    init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }

    func start() async throws {}   // 无状态，第一次 POST 就是建立
    func close() { sessionID = nil }

    func notify(_ body: [String: Any]) async throws {
        _ = try await post(body: body, expecting: nil)
    }

    func send(_ request: MCPProtocol.Request) async throws -> [String: Any] {
        guard let result = try await post(body: request.body, expecting: request.id) else {
            throw MCPError.malformed
        }
        return result
    }

    func adoptProtocolVersion(_ version: String) { negotiatedVersion = version }

    /// `expecting` 为 nil 表示这是条通知，不等回包
    private func post(body: [String: Any], expecting id: Int?) async throws -> [String: Any]? {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 两种都收：服务器自己挑用哪种回
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID { req.setValue(sessionID, forHTTPHeaderField: MCPProtocol.sessionHeader) }
        if let negotiatedVersion {
            req.setValue(negotiatedVersion, forHTTPHeaderField: MCPProtocol.versionHeader)
        }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw MCPError.malformed }
        // 会话 id 只在 initialize 的回包里给一次，之后每个请求都要带上
        if let session = http.value(forHTTPHeaderField: MCPProtocol.sessionHeader) {
            sessionID = session
        }
        guard (200...299).contains(http.statusCode) else {
            var raw = Data()
            for try await byte in bytes { raw.append(byte) }
            throw MCPError.http(http.statusCode, String(decoding: raw, as: UTF8.self))
        }
        // 202 Accepted：通知的正常回应，没有 body
        guard let id else {
            for try await _ in bytes {}
            return nil
        }

        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("text/event-stream") {
            return try await readSSE(bytes, waitingFor: id)
        }
        var raw = Data()
        for try await byte in bytes { raw.append(byte) }
        guard let json = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              let parsed = MCPProtocol.Response(json) else { throw MCPError.malformed }
        if let error = parsed.error { throw MCPError.rpc(error) }
        return parsed.result ?? [:]
    }

    /// 从 SSE 流里挑出我们等的那条回包。中间夹的通知/进度全部忽略
    private func readSSE(_ bytes: URLSession.AsyncBytes, waitingFor id: Int) async throws -> [String: Any] {
        var framer = SSEFramer()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let payload = framer.accept(line: line) else { continue }
            guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any],
                  let parsed = MCPProtocol.Response(json), parsed.id == id else { continue }
            if let error = parsed.error { throw MCPError.rpc(error) }
            return parsed.result ?? [:]
        }
        throw MCPError.timeout
    }
}

// MARK: - HTTP + SSE（旧协议，仍有不少服务器只支持这个）

/// 先 GET 打开一条常驻 SSE 流，服务器在第一条 `event: endpoint` 里告诉我们
/// 该往哪个地址 POST；之后请求走 POST，**回包从那条 SSE 流上回来**。
///
/// 所以要有个后台任务一直读流，按 id 把回包派发给在等的那个请求。
final class MCPSSETransport: MCPTransport {
    private let url: URL
    private let headers: [String: String]

    private var readerTask: Task<Void, Never>?
    private let pending = PendingResponses()
    private var postURL: URL?

    /// 等 endpoint 事件的最长时间。连不上的服务器不能让用户一直转圈
    private let handshakeTimeout: TimeInterval = 20

    init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }

    func start() async throws {
        close()
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 0            // 常驻流，不能按普通请求超时
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw MCPError.malformed }
        guard (200...299).contains(http.statusCode) else {
            throw MCPError.http(http.statusCode, "")
        }

        let base = url
        let pending = self.pending
        readerTask = Task { [weak self] in
            var framer = SSEFramer()
            var eventName = "message"
            do {
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    // 需要看 event: 行，所以不能只依赖 SSEFramer（它只管 data:）
                    if line.hasPrefix("event:") {
                        eventName = line.dropFirst("event:".count)
                            .trimmingCharacters(in: .whitespaces)
                        continue
                    }
                    guard let payload = framer.accept(line: line) else { continue }
                    if eventName == "endpoint" {
                        self?.postURL = Self.resolve(endpoint: payload, against: base)
                        eventName = "message"
                        continue
                    }
                    eventName = "message"
                    guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8)))
                            as? [String: Any],
                          let parsed = MCPProtocol.Response(json), let id = parsed.id else { continue }
                    if let error = parsed.error {
                        await pending.fail(id, MCPError.rpc(error))
                    } else {
                        await pending.succeed(id, parsed.result ?? [:])
                    }
                }
            } catch {
                // 流断了：下面统一把在等的请求全部失败掉，不然它们会一直挂着
            }
            await pending.failAll(MCPError.notConnected)
        }

        // 等服务器把 POST 地址给过来
        let deadline = Date().addingTimeInterval(handshakeTimeout)
        while postURL == nil {
            guard Date() < deadline else { close(); throw MCPError.timeout }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// endpoint 事件给的可能是相对路径（`/messages?sessionId=…`），要拼回绝对地址
    private static func resolve(endpoint: String, against base: URL) -> URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    func close() {
        readerTask?.cancel()
        readerTask = nil
        postURL = nil
    }

    func notify(_ body: [String: Any]) async throws {
        try await rawPost(body)
    }

    func send(_ request: MCPProtocol.Request) async throws -> [String: Any] {
        // 先挂号再发，免得回包比登记还快
        async let answer = pending.wait(request.id)
        try await rawPost(request.body)
        return try await answer
    }

    private func rawPost(_ body: [String: Any]) async throws {
        guard let postURL else { throw MCPError.notConnected }
        var req = URLRequest(url: postURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MCPError.http(code, String(decoding: data, as: UTF8.self))
        }
    }
}

/// 按 id 等回包。用 actor 而不是加锁：这张表被读流的后台任务和
/// 若干个在等的请求同时碰，actor 天然把它们排好队
private actor PendingResponses {
    private var waiters: [Int: CheckedContinuation<[String: Any], Error>] = [:]

    func wait(_ id: Int) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            waiters[id] = continuation
        }
    }
    func succeed(_ id: Int, _ result: [String: Any]) {
        waiters.removeValue(forKey: id)?.resume(returning: result)
    }
    func fail(_ id: Int, _ error: Error) {
        waiters.removeValue(forKey: id)?.resume(throwing: error)
    }
    func failAll(_ error: Error) {
        let all = waiters
        waiters.removeAll()
        for (_, continuation) in all { continuation.resume(throwing: error) }
    }
}
