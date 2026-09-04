import Foundation

/// 没有模型时的兜底：用关键词规则也要给出一张卡片。
///
/// 这条跟克克已经定下的规矩是同一条线——**绝不静默地丢掉用户的输入**。
/// 没配 API、Key 过期、网断了，碎片照样该变成卡片，只是这张卡片朴素一点，
/// 并且明确标着「规则整理的」，用户有权知道。
///
/// 纯函数，不碰网络也不碰磁盘。
enum RuleCardMatcher {

    /// 关键词 → 类型。顺序有意义：**从最不容易误判的往下排**。
    /// 「花了 30 块」既有数字又是发生过的事，但它更像 metric，所以 metric 排在 event 前面
    private static let rules: [(kind: TimelineCard.Kind, words: [String])] = [
        (.todo,    ["记得", "别忘", "要去", "得去", "待办", "todo", "明天要", "回头", "提醒我"]),
        (.routine, ["打卡", "坚持", "第几天", "又跑了", "每天", "习惯", "连续"]),
        (.quote,   ["书里", "他说", "她说", "看到一句", "摘抄", "引用", "台词", "歌词"]),
        (.metric,  ["公斤", "斤", "kg", "块钱", "元", "分", "度", "步", "小时", "分钟", "毫升", "ml"]),
        (.place,   ["在", "去了", "路过", "店", "馆", "公园", "家里"]),
    ]

    /// 给一条碎片配一张卡片。**一定会返回**，返回 nil 就等于丢了用户的东西
    static func card(for fragment: Fragment) -> TimelineCard {
        let text = fragment.summary
        var card = TimelineCard(fragmentIDs: [fragment.id],
                                kind: kind(for: fragment),
                                title: title(from: text),
                                occurredAt: fragment.occurredAt)
        card.byRule = true
        // 标题已经把话说完了就不要再重复一遍
        let full = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if full.count > card.title.count { card.detail = full }
        if let path = fragment.imagePath { card.imagePaths = [path] }
        return card
    }

    static func kind(for fragment: Fragment) -> TimelineCard.Kind {
        // 一张没配任何文字的照片，除了「这是张照片」也说不出别的
        if fragment.kind == .photo,
           fragment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .gallery
        }
        let text = fragment.summary.lowercased()
        for rule in rules where rule.words.contains(where: { text.contains($0) }) {
            return rule.kind
        }
        return .event
    }

    /// 标题：第一个句子，最多 20 字。
    /// 断句符号中英文都算——中文碎片里出现英文逗号是常事
    static func title(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "一条碎片" }
        let stops = CharacterSet(charactersIn: "。！？!?\n；;")
        let first = trimmed.components(separatedBy: stops)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? trimmed
        if first.count <= 20 { return first }
        return String(first.prefix(19)) + "…"
    }
}
