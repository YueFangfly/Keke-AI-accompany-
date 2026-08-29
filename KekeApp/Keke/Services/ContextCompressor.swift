import Foundation

// 上下文压缩。
//
// 在这之前，发给模型的历史是 messages.suffix(40) 直接砍掉前面的——聊得越久越失忆，
// 长期记忆那套（MemoryService）只捞得到"值得记的事实"，捞不回对话本身的来龙去脉。
//
// 现在改成：老消息先让模型缩成一段摘要，摘要跟着每次请求一起发，
// 近期消息照旧原样发。摘要是滚动的，下一次压缩会把上一份摘要一起揉进去。
//
// 注意压缩**只影响发给模型的窗口**：聊天列表读的是 JSONL 全量，一条都不会少，
// 用户翻记录看到的永远是原文。所以这套东西没有任何界面。

enum ContextCompressor {

    // MARK: - 参数

    /// 未压缩的消息攒到这个数就该压一次了
    static let triggerCount = 40
    /// 或者：虽然条数没到，但内容已经这么多 token 了也该压。
    /// 光看条数不够——40 条日常闲聊很小，40 条里夹了几段长文就很大
    static let triggerTokens = 12_000
    /// 压完之后原样保留最近多少轮用户发言。
    /// 陪伴向的对话不能只留一两轮——上下文断了她说话就会飘，
    /// 所以留得比通用客户端多
    static let keepRecentUserTurns = 12

    /// 模型上下文窗口未知时的保守估计。克克没存各模型的窗口大小，
    /// 按最小的那档算，宁可多切几刀也不要请求被拒
    static let assumedContextWindowTokens = 32_000
    /// 留给压缩提示词和模型输出的比例
    static let contextReserveFraction = 0.30
    /// 单次压缩请求的字符硬上限。就算模型窗口很大也不超过这个数——
    /// 一次塞太多，模型摘出来的东西会糊
    static let safeRequestChars = 100_000

    /// 超上下文时最多二分几次
    static let maxSplitRetries = 5
    /// 切到这么短就别再切了，再切下去说明不是长度问题
    static let minSplitChars = 512

    // MARK: - token 估算

    /// 粗略估 token 数。中英分开算：中文一个字约 0.6 token，英文约 4 个字符 1 token。
    /// 混在一起按同一个系数算的话，会严重低估中文
    static func estimateTokens(_ text: String) -> Int {
        var cjk = 0
        var other = 0
        for scalar in text.unicodeScalars {
            if isCJK(scalar) { cjk += 1 } else { other += 1 }
        }
        return Int((Double(cjk) / 1.6 + Double(other) / 4).rounded())
    }

    /// 这批消息大概值多少 token
    static func estimateTokens(_ messages: [ChatMessage]) -> Int {
        messages.reduce(0) { $0 + estimateTokens($1.text) }
    }

    /// 该压了吗
    static func shouldCompress(_ messages: [ChatMessage]) -> Bool {
        messages.count >= triggerCount || estimateTokens(messages) >= triggerTokens
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x9FFF,   // 部首扩展 ~ 中日韩统一表意文字
             0xF900...0xFAFF,   // 兼容表意文字
             0xFF00...0xFFEF:   // 全角标点
            return true
        default:
            return false
        }
    }

    /// 一次压缩请求最多塞多少字符
    static func requestCharBudget(contextWindowTokens: Int = assumedContextWindowTokens) -> Int {
        let window = contextWindowTokens > 0 ? contextWindowTokens : assumedContextWindowTokens
        let usable = Double(window) * (1 - contextReserveFraction) * 1.6
        return min(safeRequestChars, max(1, Int(usable)))
    }

    // MARK: - 挑出要压缩的部分

    /// 把消息切成"压缩掉的"和"原样保留的"两段。
    ///
    /// 保留段**必须从一条用户消息开头**：如果从助手的回复开始，模型会看到一个
    /// 没有对应提问的回答，说话就容易飘。
    static func split(_ messages: [ChatMessage],
                      keepUserTurns: Int = keepRecentUserTurns) -> (compress: [ChatMessage], keep: [ChatMessage]) {
        guard keepUserTurns > 0 else { return (messages, []) }

        let userIndices = messages.indices.filter {
            messages[$0].role == .user && !messages[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        // 用户发言还没超过要保留的轮数，没什么可压的
        guard userIndices.count > keepUserTurns else { return ([], messages) }

        let cut = userIndices[userIndices.count - keepUserTurns]
        return (Array(messages[..<cut]), Array(messages[cut...]))
    }

    // MARK: - 组织成文本

    /// 一条消息在压缩输入里长什么样。空消息不参与
    static func line(for message: ChatMessage, userName: String, personaName: String) -> String? {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return "\(message.role == .user ? userName : personaName)：\(text)"
    }

    /// 按消息边界打包成若干块，每块不超过 maxChars。
    /// 单条消息就超长的话才从中间切开
    static func chunk(_ messages: [ChatMessage],
                      userName: String,
                      personaName: String,
                      maxChars: Int) -> [String] {
        guard maxChars > 0 else { return [] }
        var chunks: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(trimmed) }
            current = ""
        }

        for message in messages {
            guard let line = line(for: message, userName: userName, personaName: personaName) else { continue }
            if line.count > maxChars {
                flush()
                chunks.append(contentsOf: splitByLength(line, maxChars: maxChars))
                continue
            }
            let extra = current.isEmpty ? line.count : line.count + 2
            if !current.isEmpty && current.count + extra > maxChars { flush() }
            if !current.isEmpty { current += "\n\n" }
            current += line
        }
        flush()
        return chunks
    }

    /// 按字符数硬切。Swift 的 String 按 Character 走，不会把 emoji 或者
    /// 组合字符切成两半，不用像 UTF-16 那样自己防一手
    static func splitByLength(_ text: String, maxChars: Int) -> [String] {
        guard maxChars > 0, text.count > maxChars else { return text.isEmpty ? [] : [text] }
        var pieces: [String] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            let end = rest.index(rest.startIndex, offsetBy: maxChars, limitedBy: rest.endIndex) ?? rest.endIndex
            pieces.append(String(rest[..<end]))
            rest = rest[end...]
        }
        return pieces
    }

    /// 把两段文本对半分。用于超上下文之后的重试
    static func halve(_ text: String) -> (left: String, right: String)? {
        guard text.count >= 2 else { return nil }
        let middle = text.index(text.startIndex, offsetBy: text.count / 2)
        return (String(text[..<middle]), String(text[middle...]))
    }

    // MARK: - 判断是不是"超上下文"错误

    /// 各家 API 报上下文超限的说法都不一样，只能按短语匹配。
    ///
    /// 只认明确表示**输入太长**的说法：光看到 max_tokens 不算，
    /// 那多半只是参数配错了，切分再多次也没用
    static func isContextLengthError(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        let phrases = [
            "context_length", "context length", "context window",
            "maximum context", "max context",
            "too many tokens", "prompt is too long", "prompt too long",
            "input is too long", "input too long",
            "reduce the length of the messages", "reduce the length of the prompt",
            "exceeds the maximum number of tokens",
        ]
        if phrases.contains(where: text.contains) { return true }
        // "max_tokens ... exceed" 这种组合才算，单独出现的 max_tokens 不算
        if text.contains("max_tokens") {
            return ["exceed", "too long", "too many", "over"].contains(where: text.contains)
        }
        return false
    }

    // MARK: - 提示词

    /// 压缩用的系统提示词。目标是让摘要**可以直接当记忆用**，
    /// 而不是写一篇"用户询问了天气"式的会议纪要
    static func summaryInstruction(userName: String, personaName: String,
                                   previousSummary: String?, conversation: String) -> String {
        var parts: [String] = []
        if let previousSummary, !previousSummary.isEmpty {
            parts.append("""
            这是你之前整理过的、更早那段聊天的摘要：

            \(previousSummary)
            """)
        }
        parts.append("""
        下面是 \(userName) 和\(personaName)接下来的聊天记录：

        \(conversation)
        """)
        parts.append("""
        请把上面的内容整理成一段紧凑的摘要，之后\(personaName)会靠这段摘要回忆起这些对话。要求：

        - 如果有之前的摘要，把两部分**合并**成一份完整的，不要分成两段，也不要丢掉之前摘要里的信息
        - 保留：TA 说过的具体事实（人名、地点、时间、在做的事）、TA 的情绪和状态变化、
          你们之间说定的事和还没说完的话题、称呼和相处方式上的习惯
        - 丢掉：寒暄、重复的话、纯粹的语气词
        - 用第三人称叙述，像在回忆，不要写成条目清单，不要加标题
        - 尽量控制在 500 字以内；信息实在多可以放宽，但不要啰嗦
        - 只输出摘要正文，不要任何前言后语
        """)
        return parts.joined(separator: "\n\n")
    }

    /// 摘要发给模型时的包装。放在 extraContext 里，跟记忆块并列
    static func contextBlock(summary: String, userName: String) -> String {
        """
        （这是你和 \(userName)更早之前聊过的内容，你自己回忆起来的，不是TA刚说的：
        \(summary)）
        """
    }
}
