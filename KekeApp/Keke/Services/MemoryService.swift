import Foundation
import SwiftUI

/// 一条长期记忆（存在 SQLite 里，这个结构体是给 UI/其他代码用的快照）
struct MemoryEntry: Identifiable, Equatable {
    var id: Int64
    var text: String
    var createdAt: Date
    var category: String
    var importance: MemoryDatabase.Importance
    var valence: Double
    var arousal: Double
    var status: MemoryDatabase.Status
    var recallCount: Int
    var archived: Bool
    var contact: String
}

/// 老版本（JSON 文件）存的记忆结构，只用来做一次性迁移
private struct LegacyMemoryEntry: Codable {
    var id: UUID
    var text: String
    var createdAt: Date
}

/// 克克的长期记忆（参考 flagellum 的 recall 思路：记忆是一个可搜索的库，
/// 按相关度取出最相关的条目给模型）。2026-07-13 从 JSON + 手写"二字组重合度"
/// 升级成 SQLite + FTS5，用真正的 BM25 打分，扛得住上万条也不卡。
/// 2026-07-17 参考 Ombre Brain 叠了一层"像人的记忆"的机制（检索底子不变）：
/// - 写入：定期让 AI 从最近聊天里提炼值得记的事，同时标好重要度 + 情绪坐标 + 有没有下文
/// - 读取：置顶（雷点/约定）和未了结的心事无条件带上、不占名额；剩下的用 FTS5 查候选，
///   按 BM25 x 时间衰减 x 情绪强度 x 唤醒次数 x 状态 重排后取最相关的若干条注入上下文；
///   被注入过的条目唤醒计数 +1（越常想起记得越牢）
/// - 每周一次后台维护：AI 合并重复、过期降级、看看哪些心事已经了结；
///   本地规则自动把"了结很久的"和"从没被想起的旧事"收进归档（不删，能捞回来）
@MainActor
final class MemoryService: ObservableObject {
    @Published var memories: [MemoryEntry] = []

    let personaId: String
    private let db: MemoryDatabase?

    private static func dbURL(for personaId: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_memory.sqlite3")
    }
    private var legacyJSONURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_memory.json")
    }
    private var legacyBackupURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_memory_backup.json")
    }

    init(personaId: String = "keke") {
        self.personaId = personaId
        db = MemoryDatabase(path: Self.dbURL(for: personaId))
        migrateFromJSONIfNeeded()
        reload()
    }

    var allTexts: [String] { allTexts(contact: "keke") }

    func allTexts(contact: String) -> [String] {
        memories.filter { !$0.archived && $0.contact == contact }.map(\.text)
    }

    // MARK: - 增删改

    func add(_ text: String, category: String = "", importance: MemoryDatabase.Importance = .normal,
             valence: Double = 0, arousal: Double = 0, status: MemoryDatabase.Status = .none,
             contact: String = "keke") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !memories.contains(where: { $0.text == trimmed && $0.contact == contact }) else { return }
        db?.insert(text: trimmed, category: category, importance: importance,
                   valence: valence, arousal: arousal, status: status, contact: contact)
        reload()
    }

    /// 导入一份 md/txt 文本：按行拆开，去掉常见的列表符号/编号，每行当一条记忆。
    /// 返回新增的条数
    @discardableResult
    func importLines(from text: String, contact: String = "keke") -> Int {
        let before = memories.count
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            for prefix in ["- ", "* ", "+ ", "#### ", "### ", "## ", "# "] {
                if line.hasPrefix(prefix) {
                    line = String(line.dropFirst(prefix.count))
                    break
                }
            }
            if let range = line.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
                line.removeSubrange(range)
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard line.count >= 2 else { continue }
            add(line, contact: contact)
        }
        return memories.count - before
    }

    /// 从文件导入记忆（自动认格式）：
    /// - json：认 claude.ai 导出（chat_messages）、ChatGPT 导出（mapping 树）、
    ///   字符串数组、带 text/content 字段的对象数组
    /// - 其他（md/txt/pdf/html）：提取文字按行拆
    /// 返回实际新增条数
    @discardableResult
    func importFile(at url: URL, contact: String) -> Int {
        if url.pathExtension.lowercased() == "json" {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let lines = Self.linesFromJSON(data) {
                let before = memories.count
                for line in lines {
                    add(line, contact: contact)
                }
                return memories.count - before
            }
            return 0
        }
        guard let text = Attachments.extractBookText(from: url) else { return 0 }
        return importLines(from: text, contact: contact)
    }

    /// 把各种 json 导出解成一行一条的文本
    private static func linesFromJSON(_ data: Data) -> [String]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var lines: [String] = []
        func append(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if trimmed.count >= 2 { lines.append(trimmed) }
        }

        if let strings = object as? [String] {
            strings.forEach(append)
            return lines
        }
        guard let array = object as? [[String: Any]] else { return nil }

        // claude.ai 导出：[{name, chat_messages: [{sender, text}]}]
        if array.contains(where: { $0["chat_messages"] != nil }) {
            for convo in array {
                for message in (convo["chat_messages"] as? [[String: Any]]) ?? [] {
                    guard let text = message["text"] as? String, !text.isEmpty else { continue }
                    let who = (message["sender"] as? String) == "human" ? "我" : "TA"
                    append("\(who)：\(text)")
                }
            }
            return lines
        }

        // ChatGPT 导出：[{title, mapping: {id: {message: {author:{role}, content:{parts}, create_time}}}}]
        if array.contains(where: { $0["mapping"] != nil }) {
            for convo in array {
                guard let mapping = convo["mapping"] as? [String: [String: Any]] else { continue }
                var messages: [(Double, String, String)] = []
                for node in mapping.values {
                    guard let message = node["message"] as? [String: Any],
                          let role = (message["author"] as? [String: Any])?["role"] as? String,
                          role == "user" || role == "assistant",
                          let content = message["content"] as? [String: Any],
                          let parts = content["parts"] as? [Any] else { continue }
                    let text = parts.compactMap { $0 as? String }.joined(separator: " ")
                    guard !text.isEmpty else { continue }
                    let time = message["create_time"] as? Double ?? 0
                    messages.append((time, role, text))
                }
                for (_, role, text) in messages.sorted(by: { $0.0 < $1.0 }) {
                    append("\(role == "user" ? "我" : "TA")：\(text)")
                }
            }
            return lines
        }

        // 通用：对象数组里取 text / content 字段
        for item in array {
            if let text = item["text"] as? String { append(text) }
            else if let text = item["content"] as? String { append(text) }
        }
        return lines.isEmpty ? nil : lines
    }

    func delete(_ entry: MemoryEntry) {
        db?.delete(id: entry.id)
        reload()
    }

    func setImportance(_ importance: MemoryDatabase.Importance, for entry: MemoryEntry) {
        db?.setImportance(importance, for: entry.id)
        reload()
    }

    func setStatus(_ status: MemoryDatabase.Status, for entry: MemoryEntry) {
        db?.setStatus(status, for: entry.id)
        reload()
    }

    func setArchived(_ archived: Bool, for entry: MemoryEntry) {
        db?.setArchived(archived, for: entry.id)
        reload()
    }

    func clearAll() {
        db?.deleteAll()
        reload()
    }

    // MARK: - 读取（给聊天用的上下文块）

    /// 挑出和 query 最相关的记忆，拼成给克克的"长期记忆"上下文块。query 为空时取最新的若干条。
    /// 置顶级（雷点/约定）和未了结的心事无条件带上、不占 limit 名额；已归档的不参与
    func contextBlock(for query: String?, userName: String, limit: Int = 32,
                      contact: String = "keke") -> String? {
        guard let db, memories.contains(where: { !$0.archived && $0.contact == contact }) else { return nil }

        let pinned = db.pinnedRows(contact: contact)
        let open = db.openRows(contact: contact, limit: 6).filter { row in !pinned.contains(where: { $0.id == row.id }) }
        let unconditionalIDs = Set((pinned + open).map(\.id))

        let recentSlots = min(limit / 4, 8)
        let allActive = db.activeRows(contact: contact).filter { !unconditionalIDs.contains($0.id) }
        let recentRows = Array(allActive.prefix(recentSlots))
        let recentIDs = Set(recentRows.map(\.id))
        let searchLimit = limit - recentRows.count

        let others: [MemoryDatabase.Row]
        if allActive.count <= limit {
            others = allActive
        } else if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let candidates = db.searchCandidates(query: query, contact: contact, candidateLimit: max(limit * 3, 80))
                .filter { !recentIDs.contains($0.row.id) }
            let now = Date()
            let ranked = candidates.map { pair -> (MemoryDatabase.Row, Double) in
                let ageDays = now.timeIntervalSince(pair.row.createdAt) / 86400
                let decay = pow(0.985, max(0, ageDays))
                let rehearsal = 1 + 0.02 * Double(min(pair.row.recallCount, 20))
                let emotion = 1 + 0.3 * pair.row.arousal
                let settled = pair.row.status == .resolved ? 0.3 : 1.0
                return (pair.row, pair.relevance * decay * rehearsal * emotion * settled)
            }.sorted { $0.1 > $1.1 }
            let picked = ranked.prefix(searchLimit).map { $0.0 }
            db.bumpRecall(ids: (recentRows + picked).map(\.id))
            others = recentRows + picked
        } else {
            others = Array(allActive.prefix(limit))
        }

        let combined = pinned + open + others
        guard !combined.isEmpty else { return nil }

        let profileRows = combined.filter { $0.text.hasPrefix("【性格画像】") }
        let eventRows = combined.filter { !$0.text.hasPrefix("【性格画像】") }

        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"

        var block = ""

        if !profileRows.isEmpty {
            let profileTexts = profileRows.map { String($0.text.dropFirst("【性格画像】".count)) }
            block += "你对 \(userName) 这个人的了解（性格画像，这是TA的底色，回复时自然融入）：\n"
                + profileTexts.joined(separator: "\n")
        }

        if !eventRows.isEmpty {
            let lines = eventRows.map { row -> String in
                var tag = row.importance == .pinned ? "【置顶】" : (row.importance == .important ? "【重要】" : "")
                if row.status == .open { tag += "【惦记】" }
                return "- \(tag)[\(formatter.string(from: row.createdAt))] \(row.text)"
            }
            if !block.isEmpty { block += "\n\n" }
            block += "最近发生的事和日常记忆（结合性格画像自然地聊，不要逐条复述）：\n"
                + lines.joined(separator: "\n")
        }

        if !open.isEmpty {
            block += "\n（标了【惦记】的是还没有着落的事——合适的时候可以自然地问问进展或关心一下，别刻意；"
                + "已经有结果的就不用再当心事惦记了）"
        }
        return block
    }

    // MARK: - 性格画像提炼

    /// 从大量聊天记录文件中提炼性格画像：分块让 AI 分析，汇总后写入记忆（置顶）。
    /// `onProgress` 回调用来更新 UI 进度文字。返回最终的画像文本，nil 表示失败或无内容。
    func synthesizeProfile(from url: URL, userName: String,
                           provider: AIProvider, apiKey: String, model: String,
                           onProgress: @MainActor @Sendable (String) -> Void) async -> String? {
        let lines: [String]
        if url.pathExtension.lowercased() == "json" {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let parsed = Self.linesFromJSON(data), !parsed.isEmpty else { return nil }
            lines = parsed
        } else {
            guard let text = Attachments.extractBookText(from: url) else { return nil }
            lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= 2 }
            guard !lines.isEmpty else { return nil }
        }

        let chunkSize = 100
        let chunks = stride(from: 0, to: lines.count, by: chunkSize).map { start in
            Array(lines[start..<min(start + chunkSize, lines.count)])
        }

        var summaries: [String] = []
        for (i, chunk) in chunks.enumerated() {
            onProgress("\(i + 1)/\(chunks.count)")
            let block = chunk.joined(separator: "\n")
            guard let result = try? await ClaudeService.synthesizeProfileChunk(
                chatLines: block, userName: userName,
                provider: provider, apiKey: apiKey, model: model
            ) else { continue }
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { summaries.append(trimmed) }
        }
        guard !summaries.isEmpty else { return nil }

        onProgress("")
        let profile: String
        if summaries.count == 1 {
            profile = summaries[0]
        } else {
            guard let merged = try? await ClaudeService.mergeProfileSummaries(
                chunks: summaries, userName: userName,
                provider: provider, apiKey: apiKey, model: model
            ) else { return nil }
            profile = merged.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !profile.isEmpty else { return nil }

        saveProfileWithHistory(profile)
        return profile
    }

    /// 从 App 内已有的记忆（包括导入的）提炼性格画像
    func synthesizeProfileFromMemories(userName: String,
                                       provider: AIProvider, apiKey: String, model: String,
                                       onProgress: @MainActor @Sendable (String) -> Void) async -> String? {
        let relevant = memories.filter {
            !$0.archived && $0.contact == personaId && !$0.text.hasPrefix("【性格画像】")
                && !$0.text.hasPrefix("【画像更新记录】")
        }
        guard !relevant.isEmpty else { return nil }

        let lines = relevant.map(\.text)
        let chunkSize = 100
        let chunks = stride(from: 0, to: lines.count, by: chunkSize).map { start in
            Array(lines[start..<min(start + chunkSize, lines.count)])
        }

        var summaries: [String] = []
        for (i, chunk) in chunks.enumerated() {
            onProgress("\(i + 1)/\(chunks.count)")
            let block = chunk.joined(separator: "\n")
            guard let result = try? await ClaudeService.synthesizeProfileChunk(
                chatLines: block, userName: userName,
                provider: provider, apiKey: apiKey, model: model
            ) else { continue }
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { summaries.append(trimmed) }
        }
        guard !summaries.isEmpty else { return nil }

        onProgress("")
        let profile: String
        if summaries.count == 1 {
            profile = summaries[0]
        } else {
            guard let merged = try? await ClaudeService.mergeProfileSummaries(
                chunks: summaries, userName: userName,
                provider: provider, apiKey: apiKey, model: model
            ) else { return nil }
            profile = merged.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !profile.isEmpty else { return nil }

        saveProfileWithHistory(profile)
        return profile
    }

    private func saveProfileWithHistory(_ newProfile: String) {
        let existing = memories.first { $0.text.hasPrefix("【性格画像】") && $0.contact == personaId }
        if let existing {
            let oldProfile = String(existing.text.dropFirst("【性格画像】".count))
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd HH:mm"
            let ts = fmt.string(from: Date())
            let abbrev = oldProfile.count > 200 ? String(oldProfile.prefix(200)) + "…" : oldProfile
            add("【画像更新记录】\(ts) 旧画像：\(abbrev)", category: "profile_history", contact: personaId)
            delete(existing)
        }
        add("【性格画像】\(newProfile)", category: "profile", importance: .pinned, contact: personaId)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "\(personaId)_profile_refreshed_at")
    }

    // MARK: - 每周维护：合并重复、过期降级、心事了结、自动归档

    /// App 回到前台时调用：一周检查一次。
    /// 先跑本地规则的自动归档（不花钱），再让 AI 看看记忆列表里有没有能合并的相似/重复条目、
    /// 有没有已经过期的事实该从重要/置顶降回普通、有没有标着【惦记】但看起来已经了结的心事。
    /// 合并的做法是保留最早那条、删掉其余重复的，不是让 AI 现改写合并后的新句子
    func maybeRunWeeklyMaintenance(store: ChatStore) async {
        guard let db, !store.apiKey.isEmpty else { return }
        let maintenanceKey = "\(personaId)_memory_maintenance_at"
        let lastRun = UserDefaults.standard.double(forKey: maintenanceKey)
        guard Date().timeIntervalSince1970 - lastRun > 7 * 24 * 3600 else { return }
        guard memories.count >= 8 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: maintenanceKey)

        db.autoArchive()

        let rows = db.activeRows(contact: personaId)
        let numbered = rows.enumerated().map { index, row in
            let marker = row.status == .open ? "〔还惦记着〕" : ""
            return "\(index): \(marker)\(row.text)"
        }.joined(separator: "\n")
        guard let result = try? await ClaudeService.reviewMemories(
            numberedList: numbered, userName: store.myName, provider: store.provider, apiKey: store.apiKey,
            model: store.model, systemPrompt: store.effectiveSystemPrompt
        ) else {
            reload()
            return
        }

        for group in result.mergeGroups {
            let ids = group.compactMap { rows.indices.contains($0) ? rows[$0].id : nil }
            guard ids.count > 1 else { continue }
            db.delete(ids: Array(ids.dropFirst()))
        }
        for index in result.downgradeIndexes where rows.indices.contains(index) {
            db.setImportance(.normal, for: rows[index].id)
        }
        for index in result.resolveIndexes where rows.indices.contains(index) {
            if rows[index].status == .open {
                db.setStatus(.resolved, for: rows[index].id)
            }
        }
        reload()

        await maybeRefreshProfile(store: store)
    }

    private func maybeRefreshProfile(store: ChatStore) async {
        guard let db else { return }
        let profileEntry = memories.first { $0.text.hasPrefix("【性格画像】") && $0.contact == personaId }
        guard let profileEntry else { return }

        let refreshKey = "\(personaId)_profile_refreshed_at"
        let lastRefresh = UserDefaults.standard.double(forKey: refreshKey)
        let newMemories = memories.filter {
            !$0.archived && $0.contact == personaId
                && !$0.text.hasPrefix("【性格画像】")
                && $0.createdAt.timeIntervalSince1970 > lastRefresh
        }
        guard newMemories.count >= 30 else { return }

        let existingProfile = String(profileEntry.text.dropFirst("【性格画像】".count))
        let recentObservations = newMemories.suffix(60).map(\.text).joined(separator: "\n")

        guard let updated = try? await ClaudeService.refreshProfile(
            existingProfile: existingProfile,
            recentObservations: recentObservations,
            userName: store.myName,
            provider: store.provider, apiKey: store.apiKey, model: store.model
        ) else { return }

        let trimmed = updated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        let abbrev = existingProfile.count > 200 ? String(existingProfile.prefix(200)) + "…" : existingProfile
        add("【画像更新记录】\(fmt.string(from: Date())) 自动更新，旧画像：\(abbrev)", category: "profile_history", contact: personaId)

        db.delete(id: profileEntry.id)
        db.insert(text: "【性格画像】\(trimmed)", createdAt: profileEntry.createdAt,
                  category: "profile", importance: .pinned, contact: personaId)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: refreshKey)
        reload()
    }

    // MARK: - 迁移 / 加载

    private func reload() {
        let rows = db?.allRows() ?? []
        let entries = rows.map {
            MemoryEntry(id: $0.id, text: $0.text, createdAt: $0.createdAt, category: $0.category,
                        importance: $0.importance, valence: $0.valence, arousal: $0.arousal,
                        status: $0.status, recallCount: $0.recallCount, archived: $0.archived,
                        contact: $0.contact)
        }
        // 记忆页里活跃的排前面、归档的沉底
        memories = entries.filter { !$0.archived } + entries.filter(\.archived)
    }

    /// 老版本存的是 keke_memory.json；第一次升级时把里面的内容原样搬进新的 SQLite 库，
    /// 完事把 JSON 文件改名留着当备份，不删
    private func migrateFromJSONIfNeeded() {
        guard let db, db.count == 0 else { return }
        guard let data = try? Data(contentsOf: legacyJSONURL),
              let saved = try? JSONDecoder().decode([LegacyMemoryEntry].self, from: data),
              !saved.isEmpty else { return }
        for entry in saved {
            db.insert(text: entry.text, createdAt: entry.createdAt)
        }
        try? FileManager.default.removeItem(at: legacyBackupURL)
        try? FileManager.default.moveItem(at: legacyJSONURL, to: legacyBackupURL)
    }
}
