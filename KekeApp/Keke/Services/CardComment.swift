import Foundation

/// TA 对一张卡片的反应。
///
/// **可以是「什么都不说」**——`text` 为空就是她这次选择了沉默。
/// 沉默也要记下来，不然每次打开都会再问一遍模型「要不要说点什么」。
struct CardComment: Codable, Equatable {
    var text: String = ""
    var date: Date = Date()
    /// 选择不说的时候，她自己给的理由。只给排查看，不显示给用户
    var skipReason: String = ""

    var spoke: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// 她要不要对这张卡片开口。
///
/// **这是这一整份计划里我最想要的一条。**
///
/// 现在克克所有的自动生成都是「一定要说点什么」——写日记、朋友圈回应、
/// 日记评论回复，全都只有「成功」和「失败」两种结局。结果就是废话：
/// 一张「今天买了牛奶」的卡片下面也要挤出一句关心。
///
/// 参考项目那边的做法是给评论 agent **两个完成工具**（`SaveComment` /
/// `SkipComment`），两个都直接终止本轮。克克这边换成等价的 JSON 约定，
/// 但精神一样：**沉默是一个正当的完成状态，不是失败。**
///
/// > 跟 `CardGenerator` 对照着看，**兜底方向是相反的**：
/// > 整理卡片时，解析失败要退回规则兜底——丢掉用户的输入是不可接受的。
/// > 这里解析失败要退回**沉默**——硬挤一句话出来比不说话糟糕得多。
/// > 一个是数据，一个是人。
enum CardCommentAgent {

    /// 一天最多主动开口几次。**打扰预算**：参考项目自己把
    /// 「问太多毁掉记录体验」列为首要风险，这条教训直接抄
    static let dailyBudget = 3

    /// 太老的卡片不再评论。三天前买的牛奶，她今天才说一句「记得喝哦」很怪
    static let freshnessHours: Double = 72

    enum Decision: Equatable {
        case say(String)
        case stayQuiet(String)
    }

    /// 解析她的决定。
    ///
    /// **认不出来就闭嘴。** 这是刻意的：模型没按格式回的时候，
    /// 与其猜它想说什么，不如这次不说
    static func parse(_ raw: String) -> Decision {
        guard let slice = CardParsing.extractJSONObject(raw),
              let data = slice.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return .stayQuiet("没按格式回") }

        let action = ((object["action"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let text = ((object["text"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 说了 skip 就是 skip，哪怕它顺手也填了 text——**明确的意图优先于顺带的内容**
        if action == "skip" {
            return .stayQuiet((object["why"] as? String) ?? "她选择不说")
        }
        guard action == "say" else { return .stayQuiet("action 不认识：\(action)") }
        guard !text.isEmpty else { return .stayQuiet("说要讲话但没给内容") }
        return .say(String(text.prefix(80)))
    }

    /// 这张卡片现在该不该问模型。**在花钱之前先用规则筛一遍**
    static func shouldConsider(_ card: TimelineCard,
                               now: Date,
                               todaysComments: Int) -> Bool {
        guard card.comment == nil else { return false }            // 已经表过态了
        guard todaysComments < dailyBudget else { return false }    // 今天说够了
        guard now.timeIntervalSince(card.occurredAt) <= freshnessHours * 3600 else { return false }
        // 规则兜底出来的卡片本身就很朴素，对着它评论多半是尬聊
        guard !card.byRule else { return false }
        return true
    }

    static func instruction(card: TimelineCard, userName: String) -> String {
        var lines = ["\(userName)刚记了一条：", "【\(card.kind.displayName)】\(card.title)"]
        if !card.detail.isEmpty { lines.append(card.detail) }
        if !card.orderedFields.isEmpty {
            lines.append(card.orderedFields.map { "\($0.label)：\($0.value)" }.joined(separator: " · "))
        }
        return """
        \(lines.joined(separator: "\n"))

        你看到了。**大多数时候不需要说话**——买了牛奶、跑了步、记了个待办，
        这些不需要任何人评论。只有你真的有话想说的时候才开口：
        想起了什么、担心什么、有个具体的问题想问。

        只输出一个 JSON，不要解释、不要 ``` 围栏：
        想说：{"action":"say","text":"一句话，不超过30字"}
        不说：{"action":"skip","why":"为什么"}

        没什么好说的就 skip。**沉默是正常的，硬挤一句会让你显得很假。**
        """
    }
}

// MARK: - 驱动

@MainActor
extension CardCommentAgent {

    /// 对一张卡片表个态。**用人设**——这次是她在说话，不是工具在整理。
    ///
    /// 跟 `CardGenerator` 正好相反：那边不许用人设（整理是活），
    /// 这边必须用（开口是人）
    static func react(to card: TimelineCard, cards: CardStore, store: ChatStore,
                      now: Date = Date()) async {
        guard shouldConsider(card, now: now, todaysComments: cards.spokenToday(now: now)) else { return }
        guard !store.apiKey.isEmpty else { return }

        let raw: String
        do {
            raw = try await ClaudeService.complete(
                instruction: instruction(card: card, userName: store.myName),
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt, maxTokens: 200)
        } catch {
            // 网断了不该让她"说不出话来"——这次就当她没看见，下次打开再试。
            // 所以**不写 comment**：写了就等于把一次网络故障固化成一次沉默
            ErrorLog.shared.record(source: "卡片反应", message: error.localizedDescription)
            return
        }

        switch parse(raw) {
        case .say(let text):
            cards.setComment(CardComment(text: text, date: now), for: card.id)
        case .stayQuiet(let why):
            cards.setComment(CardComment(date: now, skipReason: why), for: card.id)
        }
    }

    /// 对还没表过态的卡片依次看一眼。**一条一条来**，
    /// 而且 `shouldConsider` 每次都重新算——她说到预算上限就该停
    static func reactToPending(_ list: [TimelineCard], cards: CardStore,
                               store: ChatStore, now: Date = Date()) async {
        for card in list where card.comment == nil {
            await react(to: card, cards: cards, store: store, now: now)
        }
    }
}
