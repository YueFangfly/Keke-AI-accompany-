import Foundation

/// 把模型吐出来的那坨东西变成一张卡片，**并且判断它到底算不算成功**。
///
/// 参考项目那边是让模型调一个 `save_timeline_card` 工具，
/// 靠「工具有没有被成功调用」当完成判据。克克这里换成**严格的 JSON 约定**，
/// 原因很实际：`ClaudeService.complete` 是所有供应商通用的一条路，
/// 而工具调用在 DeepSeek / Kimi / 各种中转站上的行为参差不齐。
/// **判据本身一条没少**——只是从「工具调用成功」换成了「JSON 解析并校验通过」。
enum CardParsing {

    /// 卡片没生成出来的原因。每一条都要能直接给用户看，
    /// 「生成失败」这四个字对排查没有任何帮助
    enum Problem: LocalizedError, Equatable {
        case noJSON
        case badJSON
        case unknownKind(String)
        case emptyTitle
        case noSource

        var errorDescription: String? {
            switch self {
            case .noJSON: return "模型没按格式回，整段里找不到 JSON"
            case .badJSON: return "找到了 JSON，但里面是坏的"
            case .unknownKind(let k): return "卡片类型「\(k)」不认识"
            case .emptyTitle: return "标题是空的"
            case .noSource: return "这张卡片没有来源碎片"
            }
        }
    }

    // MARK: - 抠 JSON

    /// 从一段可能夹着废话和 ``` 围栏的回复里，把第一个完整的 JSON 对象抠出来。
    ///
    /// 不用正则：JSON 里可以嵌套花括号，字符串里还可以有花括号和转义引号，
    /// 正则数不清这些。老老实实扫一遍、数括号
    static func extractJSONObject(_ raw: String) -> String? {
        let text = Array(raw)
        var depth = 0
        var start: Int?
        var inString = false
        var escaped = false

        for (index, character) in text.enumerated() {
            if inString {
                if escaped { escaped = false; continue }
                if character == "\\" { escaped = true; continue }
                if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                guard depth > 0 else { break }
                depth -= 1
                if depth == 0, let from = start {
                    return String(text[from...index])
                }
            default:
                break
            }
        }
        return nil
    }

    // MARK: - 组装 + 校验

    /// 完成判据，一条不满足就整张不算数：
    /// JSON 能解析 → 类型认识 → 标题非空 → 有来源碎片。
    ///
    /// 宁可退回规则兜底，也不要一张字段残缺的卡片躺在时间线里——
    /// 半张卡片比没有卡片更难发现问题
    static func card(from raw: String,
                     fragmentIDs: [UUID],
                     occurredAt: Date,
                     imagePaths: [String]) -> Result<TimelineCard, Problem> {
        guard !fragmentIDs.isEmpty else { return .failure(.noSource) }
        guard let slice = extractJSONObject(raw) else { return .failure(.noJSON) }
        guard let data = slice.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return .failure(.badJSON) }

        let rawKind = (object["kind"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = TimelineCard.Kind(rawValue: rawKind.lowercased()) else {
            return .failure(.unknownKind(rawKind.isEmpty ? "（没写）" : rawKind))
        }

        let title = (object["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .failure(.emptyTitle) }

        var card = TimelineCard(fragmentIDs: fragmentIDs, kind: kind,
                                title: String(title.prefix(60)), occurredAt: occurredAt)
        card.detail = (object["detail"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        card.imagePaths = imagePaths
        card.tags = tags(from: object["tags"])
        card.fields = fields(from: object["fields"], kind: kind)
        return .success(card)
    }

    /// 标签：只要字符串、去空白、去重、最多 4 个。
    /// 模型很爱给十几个标签，全收下的话时间线会变成标签墙
    static func tags(from any: Any?) -> [String] {
        guard let list = any as? [Any] else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for item in list {
            guard let text = item as? String else { continue }
            let tag = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "#", with: "")
            guard !tag.isEmpty, tag.count <= 12, seen.insert(tag).inserted else { continue }
            out.append(tag)
            if out.count == 4 { break }
        }
        return out
    }

    /// 字段：**只收这个类型声明过的 key**。
    /// 模型自己发明的字段一律丢掉——留着它们，界面根本不知道该怎么显示
    static func fields(from any: Any?, kind: TimelineCard.Kind) -> [String: String] {
        guard let object = any as? [String: Any] else { return [:] }
        let allowed = Set(kind.fields.map(\.key))
        var out: [String: String] = [:]
        for (key, value) in object where allowed.contains(key) {
            let text: String
            if let s = value as? String { text = s }
            else if let n = value as? NSNumber { text = n.stringValue }
            else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            out[key] = String(trimmed.prefix(40))
        }
        return out
    }

    // MARK: - 提示词

    /// 类型清单直接从 `Kind.allCases` 生成，不手写第二份——
    /// 手写的那份迟早跟枚举对不上，然后模型开始输出不存在的类型
    static var kindMenu: String {
        TimelineCard.Kind.allCases.map { kind in
            let fields = kind.fields.map { "\($0.key)（\($0.label)）" }.joined(separator: "、")
            let tail = fields.isEmpty ? "" : "，可填字段：\(fields)"
            return "- \(kind.rawValue)：\(kind.hint)\(tail)"
        }.joined(separator: "\n")
    }

    static func instruction(fragmentText: String, when: String, seen: String?) -> String {
        """
        下面是一条随手记的碎片。把它整理成一张卡片。

        碎片内容：
        \(fragmentText)
        记录时间：\(when)
        \(seen.map { "这张图里看到的：\($0)" } ?? "")

        可选的卡片类型：
        \(kindMenu)

        只输出一个 JSON 对象，不要任何解释、不要 ``` 围栏：
        {"kind":"类型","title":"一句话标题，不超过20字","detail":"补充说明，可以为空","tags":["标签"],"fields":{}}

        规则：
        - title 是这件事最短的说法，不要复述整条碎片
        - 拿不准类型就用 event
        - **不要编碎片里没有的信息**。没写地点就不要填地点
        - fields 里只能出现上面列出的 key，别的一律不要
        - 最多 4 个标签
        """
    }
}
