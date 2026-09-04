import Foundation

/// 把碎片整理成卡片。**只干这一件事**。
///
/// 三条硬规矩：
///
/// 1. **不用人设。** 整理是一份活，不是一次对话。带上人设的话，模型会用角色的
///    口吻写标题，还会顺手说两句安慰的话——那是第 6 项要做的事，不是这里。
/// 2. **完成判据一条不能少。** JSON 解析通过、类型认识、标题非空、有来源碎片，
///    四条缺一即失败。宁可退回规则兜底，也不要半张卡片躺在时间线里。
/// 3. **最终一定有一张卡片。** 没配 Key、模型抽风、网断了，都退回
///    `RuleCardMatcher`，同时把原因记进 `ErrorLog`。绝不静默地丢掉用户的输入。
///    但「最终」两个字是有讲究的：流水线前几次重试**不许兜底**，
///    这样一次断网才不会被永久地固化成一张朴素的规则卡片；
///    只有最后一次才兜底，保证用户手里一定有东西。
@MainActor
enum CardGenerator {

    /// 整理用的 system prompt。跟用户写的人设**完全无关**，
    /// 所以这段是写死的——它不是角色说的话，是一份工单
    static let systemPrompt = """
    你是一个把随手记的碎片整理成结构化卡片的工具。
    你不是任何角色，不要有情绪、不要安慰、不要评论，也不要跟用户说话。
    只输出要求的 JSON，多一个字都不要。
    """

    /// `allowFallback` 为 false 时，模型这条路走不通就返回 nil，
    /// 让调用方决定是重试还是就此兜底
    static func make(from fragment: Fragment, store: ChatStore,
                     allowFallback: Bool = true) async -> TimelineCard? {
        func fallback(_ why: String) -> TimelineCard? {
            guard allowFallback else { return nil }
            ErrorLog.shared.record(source: "整理卡片", message: why)
            return RuleCardMatcher.card(for: fragment)
        }

        let text = fragment.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        // 一个字都没有的碎片，模型也无从整理起。这种直接走规则，不算失败
        guard !text.isEmpty else { return RuleCardMatcher.card(for: fragment) }

        // 整理是脏活，正好交给便宜模型。没配就退回主模型，行为跟以前一样
        let picked = SubModelConfig.resolve(fallbackProvider: store.provider,
                                            fallbackKey: store.apiKey,
                                            fallbackModel: store.model)
        guard !picked.key.isEmpty else {
            // 没 Key 不是「暂时的问题」，重试多少次都一样。直接兜底
            ErrorLog.shared.record(source: "整理卡片",
                                   message: "还没填 API Key，先用规则凑合整理了一张")
            return RuleCardMatcher.card(for: fragment)
        }

        let stamp = DateFormatter.cardStamp.string(from: fragment.occurredAt)
        let instruction = CardParsing.instruction(fragmentText: text, when: stamp,
                                                  seen: fragment.analysis?.shortDescription)

        let raw: String
        do {
            raw = try await ClaudeService.complete(
                instruction: instruction,
                provider: picked.provider, apiKey: picked.key, model: picked.model,
                systemPrompt: systemPrompt, maxTokens: 400)
        } catch {
            return fallback(error.localizedDescription + "。已经用规则整理了一张顶上")
        }

        let outcome = CardParsing.card(from: raw,
                                       fragmentIDs: [fragment.id],
                                       occurredAt: fragment.occurredAt,
                                       imagePaths: fragment.imagePath.map { [$0] } ?? [])
        switch outcome {
        case .success(let card):
            return card
        case .failure(let problem):
            // 说清是**哪一条判据**没过，不然下次还是不知道该改什么
            return fallback((problem.errorDescription ?? "没通过校验")
                            + "。已经用规则整理了一张顶上")
        }
    }
    // MARK: - 驱动

    /// 整理一条。已经整理过的直接跳过——一条碎片只该有一张卡片。
    /// 返回「这条碎片现在有卡片了吗」，流水线靠它决定重试还是收工
    @discardableResult
    static func organize(_ fragment: Fragment, into cards: CardStore, store: ChatStore,
                         allowFallback: Bool = true) async -> Bool {
        guard !cards.organizedFragmentIDs.contains(fragment.id) else { return true }
        guard !cards.working.contains(fragment.id) else { return false }
        cards.setWorking(fragment.id, true)
        defer { cards.setWorking(fragment.id, false) }
        guard let card = await make(from: fragment, store: store, allowFallback: allowFallback) else {
            return false
        }
        cards.add(card)
        return true
    }

    /// 批量整理。**一条一条来，不并发**：几十条同时发出去，
    /// 要么把限速撞满，要么把便宜模型的并发额度打爆，最后一条都没成
    static func organizeAll(_ fragments: [Fragment], into cards: CardStore, store: ChatStore) async {
        for fragment in fragments {
            await organize(fragment, into: cards, store: store)
        }
    }
}

extension DateFormatter {
    /// 给模型看的时间。固定中文格式，别让它去猜 ISO 串是哪个时区
    static let cardStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()
}
