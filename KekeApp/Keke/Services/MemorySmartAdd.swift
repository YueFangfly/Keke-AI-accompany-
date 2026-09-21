import Foundation

/// 记忆写入前的把关：新记忆撞上旧记忆时该怎么办。
///
/// 之前只有 `insert`——聊久了必然堆一堆重复条目和自相矛盾的说法
/// （「喜欢猫」和「后来养了狗之后不太喜欢猫了」会并排躺着）。
/// 现在四选一：新增 / 合并 / 冲突 / 跳过。
enum MemoryDecision: String, Codable, Equatable {
    /// 全新的事，直接加
    case add
    /// 跟某条已有的说的是同一件事但更完整，合并成一条
    case merge
    /// 跟已有的矛盾。**不自动覆盖**——标记出来让人来定
    case conflict
    /// 已有等价信息，不用记
    case skip
}

/// 对一条待写入记忆的判定
struct MemoryVerdict: Equatable {
    let decision: MemoryDecision
    /// merge / conflict 时指向的那条已有记忆（在候选列表里的下标）
    let targetIndex: Int?
    /// merge 时给出的合并后文本
    let mergedText: String?
}

enum MemorySmartAdd {

    /// 判定结果的解析。模型只需要回一个小 JSON，比让它重写整个记忆库便宜得多。
    ///
    /// **解析不出来一律当 `.add`**：宁可多记一条重复的，也不能因为一次解析失败
    /// 把真实发生过的事丢掉——记忆丢了用户是不知道的。
    static func parseVerdict(_ raw: String, candidateCount: Int) -> MemoryVerdict {
        guard let json = firstObject(in: raw),
              let decisionText = json["decision"] as? String,
              let decision = MemoryDecision(rawValue: decisionText.lowercased()) else {
            return MemoryVerdict(decision: .add, targetIndex: nil, mergedText: nil)
        }
        // 下标越界当没给——模型偶尔会指向一条不存在的候选
        let index = (json["index"] as? Int).flatMap { (0..<candidateCount).contains($0) ? $0 : nil }
        let merged = (json["merged"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch decision {
        case .merge:
            // 说要合并却没给合并后的文本，或者没指出合并到哪条 —— 退回新增
            guard let index, let merged, !merged.isEmpty else {
                return MemoryVerdict(decision: .add, targetIndex: nil, mergedText: nil)
            }
            return MemoryVerdict(decision: .merge, targetIndex: index, mergedText: merged)
        case .conflict:
            guard let index else {
                return MemoryVerdict(decision: .add, targetIndex: nil, mergedText: nil)
            }
            return MemoryVerdict(decision: .conflict, targetIndex: index, mergedText: nil)
        case .skip, .add:
            return MemoryVerdict(decision: decision, targetIndex: index, mergedText: nil)
        }
    }

    /// 从可能带前后废话的回复里抠出第一个 JSON 对象
    private static func firstObject(in raw: String) -> [String: Any]? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"),
              start < end else { return nil }
        let slice = String(raw[start...end])
        return (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any]
    }

    /// 判定用的提示词。候选只给最像的那几条——全给的话又贵又容易挑花眼
    static func verdictPrompt(newMemory: String, candidates: [String]) -> String {
        let list = candidates.enumerated()
            .map { "\($0.offset). \($0.element)" }.joined(separator: "\n")
        return """
        已经记住的相关条目：
        \(list.isEmpty ? "（还没有相关的）" : list)

        待记录的新信息：
        \(newMemory)

        判断该怎么处理，只输出一个 JSON 对象：
        {"decision": "add|merge|conflict|skip", "index": 已有条目的编号, "merged": "合并后的完整文本"}

        - add：全新的事，已有条目里没有
        - merge：跟第 index 条说的是同一件事，但合起来更完整。必须给出 merged
        - conflict：跟第 index 条矛盾（新的说法推翻了旧的）
        - skip：已有条目已经包含了这个信息，不用重复记

        只输出 JSON，不要任何解释。
        """
    }

    // MARK: - 把关：这段对话值不值得记

    /// Gatekeeper 的提示词。让模型只回一个词，比直接跑提炼便宜一个数量级
    static func gatekeeperPrompt(chatLines: String) -> String {
        """
        下面是一段对话：

        \(chatLines)

        这段对话里有没有**值得长期记住**的新信息？
        （比如对方的偏好、经历、在意的人和事、明确的约定；
        寒暄、闲聊、已经记过的重复内容都不算）

        只回一个词：yes 或 no
        """
    }

    /// 解析把关结果。**认不出来一律当 yes**——
    /// 判断失误顶多多花一次提炼的钱，判错成 no 就是真的把事情漏掉了
    static func parseGatekeeper(_ raw: String) -> Bool {
        let text = raw.lowercased()
        if text.contains("no") && !text.contains("yes") { return false }
        return true
    }
}
