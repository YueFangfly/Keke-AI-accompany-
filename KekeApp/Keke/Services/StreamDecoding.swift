import Foundation

// 流式回复的解析层。这个文件只认协议，不碰网络——发请求、拿字节流是 ClaudeService 的事，
// 这里只负责"给我一行 SSE 数据，我告诉你发生了什么"。
//
// 这么分是为了让各家 API 的协议差异只存在于下面两个解码器里：
// 上层拿到的永远是同一套 StreamEvent，加一家新供应商只要再写一个解码器。

// MARK: - 事件

/// 流式回复里会发生的事，跟是哪家 API 无关。
///
/// 这里**没有**单独的"思考"通道：克克的心里话是模型在正文里写
/// `<thinking>…</thinking>`，收完之后由 `splitThinking` 拆出来，
/// 不是 API 层面的 reasoning 字段，所以不需要为它多开一条流。
enum StreamEvent {
    /// 正文又来了一段
    case textDelta(String)
    /// 模型要调工具了。id 在这里就定下来，后面的参数分片按它对号入座
    case toolCallStart(id: String, name: String)
    /// 工具参数是一小片一小片的 JSON 文本，要按 id 拼起来才能解析
    case toolArgumentsDelta(id: String, fragment: String)
    /// 这一轮的账单。可能分几次来（Claude 就是开头给输入、结尾给输出）
    case usage(TokenUsage)
    /// 这一轮收完了
    case finished(stopReason: String)
}

/// 流中途报错时，错误信息借 `finished` 的 stopReason 带出来，用这个前缀标记。
///
/// 前面那个 \0 是故意的：正常的 stop_reason（end_turn / tool_use / stop / length…）
/// 不可能长这样，错误正文里也不可能出现，所以判断和还原都不会误伤——
/// 之前用 "error" 当前缀，遇到 "error: internal error" 这种就会被改坏
extension StreamEvent {
    static let errorPrefix = "\u{0}stream_error:"
}

// MARK: - 折叠成一次完整回复

/// 把一串事件折成一次完整的回复。
///
/// 流式和非流式最后都汇到这个形状，后面的工具循环不用管这次是怎么拿到的。
struct StreamedReply {
    struct ToolCall {
        let id: String
        let name: String
        var argumentsJSON: String
    }

    var text = ""
    var toolCalls: [ToolCall] = []
    var usage = TokenUsage.zero
    var stopReason = ""

    mutating func apply(_ event: StreamEvent) {
        switch event {
        case .textDelta(let piece):
            text += piece

        case .toolCallStart(let id, let name):
            // 同一个 id 重复出现就不再新建，避免个别供应商重发起始帧时出现两条一样的工具调用
            guard !toolCalls.contains(where: { $0.id == id }) else { return }
            toolCalls.append(ToolCall(id: id, name: name, argumentsJSON: ""))

        case .toolArgumentsDelta(let id, let fragment):
            // 按 id 找回对应那条，而不是往最后一条上贴——模型可能同时要调好几个工具，
            // 它们的参数分片是交错到达的
            guard let index = toolCalls.firstIndex(where: { $0.id == id }) else { return }
            toolCalls[index].argumentsJSON += fragment

        case .usage(let piece):
            usage += piece

        case .finished(let reason):
            if !reason.isEmpty { stopReason = reason }
        }
    }

    /// 参数 JSON 解成字典。没收到参数的工具当成空参数（有些工具本来就不需要参数）
    func argumentsObject(for call: ToolCall) -> [String: Any] {
        let trimmed = call.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let object = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any]
        else { return [:] }
        return object
    }
}

// MARK: - SSE 分帧

/// 把 SSE 的行拼成一个个完整事件。
///
/// SSE 的规矩是：`data:` 开头的行是内容，允许连续好几行，空行表示一个事件结束。
/// Claude 和 OpenAI 实际都只发一行，但按规矩拼总不会错。
/// `event:` / `id:` / `retry:` 这些行用不上——两家的类型信息在 data 的 JSON 里都有一份。
struct SSEFramer {
    private var buffer: [String] = []

    /// 喂一行进来，凑满一个事件就把它的 data 吐出来
    mutating func accept(line: String) -> String? {
        // SSE 的行尾可能带 \r（有的服务器用 CRLF）
        let line = line.hasSuffix("\r") ? String(line.dropLast()) : line

        if line.isEmpty {
            return flush()
        }
        guard line.hasPrefix("data:") else { return nil }
        // "data: xxx" 和 "data:xxx" 都合法，冒号后面那个空格要去掉
        var payload = String(line.dropFirst("data:".count))
        if payload.hasPrefix(" ") { payload.removeFirst() }
        buffer.append(payload)
        return nil
    }

    /// 流断了，把没凑完的最后一个事件交出来
    mutating func finish() -> String? {
        flush()
    }

    private mutating func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        let joined = buffer.joined(separator: "\n")
        buffer.removeAll()
        return joined.isEmpty ? nil : joined
    }
}

// MARK: - 解码器

/// 一条响应配一个解码器实例，有状态，不能跨响应复用。
///
/// 每跑一轮工具调用就换一个新实例——这样各轮之间的 id 天然隔离，
/// 不会出现后一轮的内容被并进前一轮的情况。
protocol StreamDecoder: AnyObject {
    /// 吃一个 SSE 事件的 data，吐出它对应的零个或多个事件
    func accept(_ payload: String) -> [StreamEvent]
    /// 流正常结束时收尾，补上还没发出去的事件
    func finish() -> [StreamEvent]
}

/// Claude 的 Messages API 流式协议。
///
/// 一次回复的骨架：
/// ```
/// message_start        → 输入侧的 token 数在这里
/// content_block_start  → 一个块开始（text 或 tool_use）
/// content_block_delta  → 块的内容，一小片一小片来
/// content_block_stop   → 块结束
/// message_delta        → stop_reason 和输出侧的 token 数
/// message_stop         → 完
/// ```
/// 块之间用 index 区分，工具块的 index 要映射到它的 id，
/// 因为后面的参数分片只报 index 不报 id。
final class ClaudeStreamDecoder: StreamDecoder {
    /// content block 的 index → 工具调用 id
    private var toolIDByIndex: [Int: String] = [:]
    private var stopReason = ""
    private var finished = false

    func accept(_ payload: String) -> [StreamEvent] {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any],
              let type = json["type"] as? String else { return [] }

        switch type {
        case "message_start":
            // 输入、读缓存、写缓存都在这里给全了，输出那部分要等 message_delta
            guard let message = json["message"] as? [String: Any] else { return [] }
            let usage = ClaudeStreamDecoder.inputUsage(from: message["usage"] as? [String: Any])
            return usage.isEmpty ? [] : [.usage(usage)]

        case "content_block_start":
            guard let index = json["index"] as? Int,
                  let block = json["content_block"] as? [String: Any],
                  (block["type"] as? String) == "tool_use",
                  let id = block["id"] as? String,
                  let name = block["name"] as? String else { return [] }
            toolIDByIndex[index] = id
            return [.toolCallStart(id: id, name: name)]

        case "content_block_delta":
            guard let index = json["index"] as? Int,
                  let delta = json["delta"] as? [String: Any] else { return [] }
            switch delta["type"] as? String {
            case "text_delta":
                guard let text = delta["text"] as? String, !text.isEmpty else { return [] }
                return [.textDelta(text)]
            case "input_json_delta":
                guard let fragment = delta["partial_json"] as? String,
                      let id = toolIDByIndex[index] else { return [] }
                return [.toolArgumentsDelta(id: id, fragment: fragment)]
            default:
                // thinking_delta 之类的块这里用不上，直接忽略
                return []
            }

        case "message_delta":
            var events: [StreamEvent] = []
            if let delta = json["delta"] as? [String: Any],
               let reason = delta["stop_reason"] as? String {
                stopReason = reason
            }
            if let usage = json["usage"] as? [String: Any],
               let output = usage["output_tokens"] as? Int, output > 0 {
                events.append(.usage(TokenUsage(output: output)))
            }
            return events

        case "message_stop":
            finished = true
            return [.finished(stopReason: stopReason)]

        case "error":
            // 流中途报错：当成一次结束，错误信息带前缀交给上层去抛
            finished = true
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? ""
            return [.finished(stopReason: StreamEvent.errorPrefix + message)]

        default:
            return []
        }
    }

    func finish() -> [StreamEvent] {
        // message_stop 已经发过就别再发一次
        guard !finished else { return [] }
        finished = true
        return [.finished(stopReason: stopReason)]
    }

    /// message_start 里的输入侧用量。字段名和非流式那份是一样的
    private static func inputUsage(from usage: [String: Any]?) -> TokenUsage {
        guard let usage else { return .zero }
        return TokenUsage(input: usage["input_tokens"] as? Int ?? 0,
                          cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                          cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0)
    }
}

/// OpenAI 兼容家族（GPT / DeepSeek / Grok / Gemini / Kimi / 自定义中转）的流式协议。
///
/// 每帧都是一个 chunk：`choices[0].delta` 里带这一小片内容，
/// 工具调用按 `index` 分组——第一帧给 id 和函数名，后面几帧只给参数片段。
/// 最后一帧是 `data: [DONE]`。
final class OpenAIStreamDecoder: StreamDecoder {
    /// tool_calls 的 index → 工具调用 id
    private var toolIDByIndex: [Int: String] = [:]
    private var stopReason = ""
    private var finished = false

    func accept(_ payload: String) -> [StreamEvent] {
        if payload == "[DONE]" {
            finished = true
            return [.finished(stopReason: stopReason)]
        }
        guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else {
            return []
        }

        var events: [StreamEvent] = []

        // 开了 include_usage 之后，最后会多来一帧：choices 是空的，只带 usage
        if let usage = json["usage"] as? [String: Any] {
            let piece = OpenAIStreamDecoder.usage(from: usage)
            if !piece.isEmpty { events.append(.usage(piece)) }
        }

        guard let choice = (json["choices"] as? [[String: Any]])?.first else { return events }

        if let reason = choice["finish_reason"] as? String, !reason.isEmpty {
            stopReason = reason
        }

        guard let delta = choice["delta"] as? [String: Any] else { return events }

        if let text = delta["content"] as? String, !text.isEmpty {
            events.append(.textDelta(text))
        }

        for call in (delta["tool_calls"] as? [[String: Any]]) ?? [] {
            // index 是必须的：同时调好几个工具时，全靠它把分片对上号
            guard let index = call["index"] as? Int else { continue }
            let function = call["function"] as? [String: Any]

            if let id = call["id"] as? String, !id.isEmpty, toolIDByIndex[index] == nil {
                toolIDByIndex[index] = id
                events.append(.toolCallStart(id: id, name: function?["name"] as? String ?? ""))
            }
            if let fragment = function?["arguments"] as? String, !fragment.isEmpty,
               let id = toolIDByIndex[index] {
                events.append(.toolArgumentsDelta(id: id, fragment: fragment))
            }
        }

        return events
    }

    func finish() -> [StreamEvent] {
        // 有的服务器不发 [DONE]，直接把连接关了，这里补一个结束
        guard !finished else { return [] }
        finished = true
        return [.finished(stopReason: stopReason)]
    }

    /// prompt_tokens 是**含**缓存的总数，要把缓存那部分减出去，
    /// 才能和 Claude 一样"四份互不重叠"——跟非流式那边同一套口径
    private static func usage(from usage: [String: Any]) -> TokenUsage {
        let prompt = usage["prompt_tokens"] as? Int ?? 0
        let details = usage["prompt_tokens_details"] as? [String: Any]
        let cached = (details?["cached_tokens"] as? Int)
            ?? (usage["prompt_cache_hit_tokens"] as? Int)
            ?? 0
        return TokenUsage(input: prompt - min(cached, prompt),
                          output: usage["completion_tokens"] as? Int ?? 0,
                          cacheRead: cached)
    }
}
