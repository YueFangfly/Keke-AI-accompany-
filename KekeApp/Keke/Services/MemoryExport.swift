import Foundation

/// 记忆的导出与回读。
///
/// 之前只有两个极端：资料页那个「导出记忆」只吐正文（时间、分类、重要度全丢），
/// 完整备份倒是什么都有，但那是个 SQLite 库——能恢复，**不能读**。
///
/// 这里补中间那一档：
/// - **Markdown**：给人看的。按人分组、按重要度分段，元数据跟在每条下面
/// - **JSON**：给机器读的。带版本号，**能被这个 App 自己导回去**
///
/// 两种都是**一次导所有人**。分开导的话，想把整份记忆交给别的工具时
/// 还得自己拼，那不如不做。
enum MemoryExport {

    /// 格式标记 + 版本号。将来改结构时，老版本能认出「这份我读不了」，
    /// 而不是解出一半元数据、剩下的悄悄用默认值填上
    static let formatTag = "keke-memory"
    static let formatVersion = 1

    // MARK: - 一条记忆在文件里长什么样

    /// 从 JSON 读回来的一条。**故意跟 `MemoryEntry` 分开**：
    /// 那个带数据库主键，而导入的东西不该假装自己有主键
    struct Incoming: Equatable {
        var text: String
        var contact: String
        var category: String = ""
        var importance: MemoryDatabase.Importance = .normal
        var valence: Double = 0
        var arousal: Double = 0
        var status: MemoryDatabase.Status = .none
    }

    // MARK: - JSON

    static func jsonObject(_ entries: [MemoryEntry], exportedAt: Date = Date()) -> [String: Any] {
        [
            "format": formatTag,
            "version": formatVersion,
            "exportedAt": exportedAt.timeIntervalSince1970,
            "count": entries.count,
            "memories": entries.map(row),
        ]
    }

    private static func row(_ entry: MemoryEntry) -> [String: Any] {
        var out: [String: Any] = [
            "text": entry.text,
            "contact": entry.contact,
            "importance": entry.importance.rawValue,
            "status": entry.status.rawValue,
            "createdAt": entry.createdAt.timeIntervalSince1970,
        ]
        // 空的就不写进去。一堆 "category": "" 只会让文件更难读
        if !entry.category.isEmpty { out["category"] = entry.category }
        if entry.valence != 0 { out["valence"] = entry.valence }
        if entry.arousal != 0 { out["arousal"] = entry.arousal }
        // 这两个是**只读的**：导回去时不还原（`add` 不接受它们），
        // 但留在文件里，人看的时候有用
        if entry.recallCount > 0 { out["recallCount"] = entry.recallCount }
        if entry.archived { out["archived"] = true }
        return out
    }

    static func jsonData(_ entries: [MemoryEntry], exportedAt: Date = Date()) -> Data? {
        try? JSONSerialization.data(withJSONObject: jsonObject(entries, exportedAt: exportedAt),
                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// 认不认这份文件。**只认自己导出的**——别人的 JSON 走原来那条
    /// 「按 text 字段抠正文」的老路，元数据本来就没有
    static func parse(_ data: Data) -> [Incoming]? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (object["format"] as? String) == formatTag,
              let version = object["version"] as? Int,
              version <= formatVersion,
              // 故意先收成 [Any] 再逐条转：直接转 [[String: Any]] 的话，
              // **一条坏行会让整份文件读不了**，而坏一条不该让另外两百条陪葬
              let rows = object["memories"] as? [Any]
        else { return nil }

        return rows.compactMap { element in
            guard let row = element as? [String: Any] else { return nil }
            let text = (row["text"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else { return nil }
            var incoming = Incoming(text: text, contact: (row["contact"] as? String) ?? "")
            incoming.category = (row["category"] as? String) ?? ""
            if let raw = row["importance"] as? String,
               let value = MemoryDatabase.Importance(rawValue: raw) { incoming.importance = value }
            if let raw = row["status"] as? String,
               let value = MemoryDatabase.Status(rawValue: raw) { incoming.status = value }
            incoming.valence = clamp(row["valence"])
            incoming.arousal = clamp(row["arousal"])
            return incoming
        }
    }

    /// 情绪值只在 -1…1 之间有意义。文件被手改过、或者别的版本写了别的范围，
    /// 夹回来而不是照单全收——一个 999 的 valence 会让排序全乱
    private static func clamp(_ any: Any?) -> Double {
        guard let value = (any as? NSNumber)?.doubleValue, value.isFinite else { return 0 }
        return min(1, max(-1, value))
    }

    // MARK: - Markdown

    /// 给人读的那份。按人分组，组内按重要度分段，归档的沉到最后
    static func markdown(_ entries: [MemoryEntry],
                         names: [String: String],
                         exportedAt: Date = Date()) -> String {
        var lines = ["# 记忆导出", ""]
        lines.append("导出时间：\(stamp.string(from: exportedAt))")
        lines.append("共 \(entries.count) 条")
        lines.append("")

        for group in grouped(entries) {
            let name = names[group.contact] ?? group.contact
            lines.append("## \(name) · \(group.items.count) 条")
            lines.append("")
            for bucket in buckets(group.items) {
                lines.append("### \(bucket.title)（\(bucket.items.count)）")
                lines.append("")
                for entry in bucket.items {
                    lines.append("- " + entry.text.replacingOccurrences(of: "\n", with: " "))
                    let meta = metaLine(entry)
                    if !meta.isEmpty { lines.append("  · " + meta) }
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 每条底下那行小字。**没有的就不写**，不要「分类：无」这种占位
    static func metaLine(_ entry: MemoryEntry) -> String {
        var parts = [day.string(from: entry.createdAt)]
        if !entry.category.isEmpty { parts.append(entry.category) }
        switch entry.status {
        case .open: parts.append("还悬着")
        case .resolved: parts.append("已了结")
        case .none: break
        }
        if entry.recallCount > 0 { parts.append("被想起 \(entry.recallCount) 次") }
        return parts.joined(separator: " · ")
    }

    /// 按人分组。人的顺序按条数多到少——记得最多的那个显然是主角
    static func grouped(_ entries: [MemoryEntry]) -> [(contact: String, items: [MemoryEntry])] {
        var buckets: [String: [MemoryEntry]] = [:]
        for entry in entries { buckets[entry.contact, default: []].append(entry) }
        return buckets
            .map { (contact: $0.key, items: $0.value) }
            .sorted { left, right in
                if left.items.count != right.items.count { return left.items.count > right.items.count }
                return left.contact < right.contact   // 条数一样时定个死顺序，免得每次导出都不一样
            }
    }

    /// 组内分段：置顶 → 重要 → 普通 → 归档。**归档的不消失**，
    /// 只是沉到最后——导出是留档，不是筛选
    static func buckets(_ items: [MemoryEntry]) -> [(title: String, items: [MemoryEntry])] {
        let live = items.filter { !$0.archived }
        let archived = items.filter(\.archived)
        var out: [(String, [MemoryEntry])] = []
        for (importance, title) in [(MemoryDatabase.Importance.pinned, "置顶"),
                                    (.important, "重要"),
                                    (.normal, "普通")] {
            let picked = live.filter { $0.importance == importance }
                .sorted { $0.createdAt > $1.createdAt }
            if !picked.isEmpty { out.append((title, picked)) }
        }
        if !archived.isEmpty {
            out.append(("已归档", archived.sorted { $0.createdAt > $1.createdAt }))
        }
        return out
    }

    // MARK: - 文件名

    static func fileName(_ ext: String, at date: Date = Date()) -> String {
        "keke-memory-\(fileStamp.string(from: date)).\(ext)"
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 文件名里的时间戳固定用 POSIX 格式：文件名跟着系统语言变，排序会乱
    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return f
    }()
}
