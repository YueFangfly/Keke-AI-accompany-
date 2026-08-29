import Foundation

/// Token 用量统计。
///
/// 数据本身早就在 `ChatMessage.usage` 里了，这里只负责**读**：
/// 扫一遍所有聊天记录文件，把有用量的 AI 回复聚起来。不写、不改、不删。
struct UsageStats {

    /// 一个维度下的合计
    struct Bucket: Equatable {
        var usage = TokenUsage.zero
        /// 带用量数据的 AI 回复条数
        var replies = 0
        /// 带耗时数据的那些的耗时总和，以及它们的条数（分开记才能算出正确的平均值）
        var durationMs = 0
        var timedReplies = 0

        var averageDurationMs: Int? {
            timedReplies > 0 ? durationMs / timedReplies : nil
        }
        /// 平均每条回复的输出 token
        var averageOutput: Int? {
            replies > 0 ? usage.output / replies : nil
        }

        mutating func add(usage: TokenUsage, durationMs: Int?) {
            self.usage += usage
            replies += 1
            if let durationMs, durationMs > 0 {
                self.durationMs += durationMs
                timedReplies += 1
            }
        }
    }

    /// 一个具名维度（模型 / 会话）的一行
    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        let bucket: Bucket
    }

    var overall = Bucket()
    var byModel: [Row] = []
    var byConversation: [Row] = []
    /// 没有用量数据的 AI 回复条数。老消息、报错、以及中转站不回 usage 的都算这里。
    /// **要显示出来**——不然用户会以为统计是全量的
    var repliesWithoutUsage = 0

    var hasData: Bool { overall.replies > 0 }

    // MARK: - 派生指标

    /// 输入侧 token 里有多少是从缓存读的。
    ///
    /// 分母用 input + cacheRead + cacheWrite（= 这次请求的全部输入侧 token），
    /// 不是 input + cacheRead——写缓存那部分也是这次真金白银发过去的输入。
    /// 这个数是**验证 prompt caching 到底有没有生效**的唯一直接证据
    static func cacheReadShare(_ usage: TokenUsage) -> Double? {
        let inputSide = usage.input + usage.cacheRead + usage.cacheWrite
        guard inputSide > 0 else { return nil }
        return Double(usage.cacheRead) / Double(inputSide)
    }

    // MARK: - 采集

    /// 扫描并聚合。会读文件，**别在主线程调**。
    ///
    /// 名字也在这里自己查（PersonaStore 读 UserDefaults、联系人直接读那个 json），
    /// 不从外面接 ContactsStore：那是个 @MainActor 的类，为了一份名字表把整个
    /// 统计流程绑回主线程不值得，而且会给调用方凭空加一个环境依赖
    static func collect() -> UsageStats {
        var stats = UsageStats()
        let names = displayNames()
        var models: [String: Bucket] = [:]
        var conversations: [String: Bucket] = [:]

        for source in historyFiles() {
            guard let data = try? Data(contentsOf: source.url) else { continue }
            let messages = source.isJSONL
                ? ChatStore.decodeJSONL(data)
                : ((try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? [])

            for message in messages {
                guard message.role == .keke else { continue }
                guard let usage = message.usage, !usage.isEmpty else {
                    stats.repliesWithoutUsage += 1
                    continue
                }
                stats.overall.add(usage: usage, durationMs: message.durationMs)
                // 模型名没记的那些归到一个明确的桶里，别硬塞进某个真实模型
                let modelKey = message.model?.trimmingCharacters(in: .whitespaces)
                let model = (modelKey?.isEmpty == false) ? modelKey! : "(未记录模型)"
                models[model, default: Bucket()].add(usage: usage, durationMs: message.durationMs)
                conversations[source.key, default: Bucket()].add(usage: usage, durationMs: message.durationMs)
            }
        }

        // 排序按总 token 降序，看的人最关心花得最多的那几个
        stats.byModel = models
            .map { Row(id: $0.key, name: $0.key, bucket: $0.value) }
            .sorted { $0.bucket.usage.total > $1.bucket.usage.total }
        stats.byConversation = conversations
            .map { Row(id: $0.key, name: conversationName($0.key, names: names), bucket: $0.value) }
            .sorted { $0.bucket.usage.total > $1.bucket.usage.total }
        return stats
    }

    /// 把聚合键还原成显示名。查不到的就用 id 本身
    private static func conversationName(_ key: String, names: [String: String]) -> String {
        let raw = key.hasPrefix("contact:") ? String(key.dropFirst("contact:".count)) : key
        return names[raw] ?? raw
    }

    /// 会话 id → 显示名。查不到的就用 id 本身——
    /// 人设已经删了但记录文件还在的时候，显示 id 比瞎给一个名字诚实
    static func displayNames() -> [String: String] {
        var names: [String: String] = [:]
        for persona in PersonaStore.allPersonas() { names[persona.id] = persona.name }

        let contactsURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keke_contacts.json")
        if let data = try? Data(contentsOf: contactsURL),
           let contacts = try? JSONDecoder().decode([Contact].self, from: data) {
            for contact in contacts { names[contact.id] = contact.name }
        }
        return names
    }

    // MARK: - 文件发现

    struct Source {
        let id: String
        let url: URL
        let isJSONL: Bool
        /// 联系人的记录，不是人设的
        let isContact: Bool

        /// 聚合用的键。人设和联系人各有各的 id 空间，可能撞车
        /// （联系人里就有 claude / gpt / deepseek 这几个短 id），
        /// 撞了会把两份不相干的记录加到一起，所以分开命名空间
        var key: String { isContact ? "contact:" + id : id }
    }

    /// 找出所有聊天记录文件。
    ///
    /// 直接扫目录而不是照着人设/联系人列表去找，是为了把**已删除人设留下的记录**
    /// 也算进来——那些 token 也是真花掉了的。
    static func historyFiles() -> [Source] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let all = try? FileManager.default.contentsOfDirectory(
            at: docs, includingPropertiesForKeys: nil) else { return [] }

        var sources: [Source] = []
        var jsonlIDs = Set<String>()

        // 先收 jsonl：ChatStore.load() 优先读它，有 jsonl 就不该再读同名的 json，
        // 不然同一批消息会被数两遍
        for url in all where url.lastPathComponent.hasSuffix("_chat.jsonl") {
            let id = String(url.lastPathComponent.dropLast("_chat.jsonl".count))
            guard !id.isEmpty else { continue }
            jsonlIDs.insert(id)
            sources.append(Source(id: id, url: url, isJSONL: true, isContact: false))
        }
        for url in all {
            let name = url.lastPathComponent
            if name.hasSuffix("_chat.json") {
                let id = String(name.dropLast("_chat.json".count))
                guard !id.isEmpty, !jsonlIDs.contains(id) else { continue }
                sources.append(Source(id: id, url: url, isJSONL: false, isContact: false))
            } else if name.hasPrefix("chat_contact_"), name.hasSuffix(".json") {
                let id = String(name.dropFirst("chat_contact_".count).dropLast(".json".count))
                guard !id.isEmpty else { continue }
                sources.append(Source(id: id, url: url, isJSONL: false, isContact: true))
            }
        }
        return sources
    }
}

// MARK: - 显示用的格式化

enum UsageFormat {

    /// 12345 → "12.3k"。统计页上精确到个位没意义，长度还失控
    static func tokens(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        if n < 1_000_000 {
            let k = Double(n) / 1000
            // 先按显示精度四舍五入再判断分支，不然 9950 会走进"一位小数"那支
            // 然后被 %.1f 印成 "10.0k"——和 10k 起步只留整数的规则自相矛盾
            let shown = (k * 10).rounded() / 10
            return shown < 10 ? String(format: "%.1fk", shown) : "\(Int(k.rounded()))k"
        }
        return String(format: "%.1fM", Double(n) / 1_000_000)
    }

    /// 3400 → "3.4s"；900 → "0.9s"；72000 → "1m12s"
    static func duration(_ ms: Int) -> String {
        if ms < 1000 { return String(format: "%.1fs", Double(ms) / 1000) }
        if ms < 60_000 { return String(format: "%.1fs", Double(ms) / 1000) }
        return "\(ms / 60_000)m\((ms % 60_000) / 1000)s"
    }

    static func percent(_ ratio: Double) -> String {
        String(format: "%.0f%%", ratio * 100)
    }
}
