import Foundation

/// 把碎片整理成卡片。**只干这一件事**。
///
/// 三条硬规矩：
///
/// 1. **不用人设。** 整理是一份活，不是一次对话。带上人设的话，模型会用角色的
///    口吻写标题，还会顺手说两句安慰的话——那是第 6 项要做的事，不是这里。
/// 2. **完成判据一条不能少。** JSON 解析通过、类型认识、标题非空、有来源碎片，
///    四条缺一即失败。宁可退回规则兜底，也不要半张卡片躺在时间线里。
/// 3. **永远返回一张卡片。** 没配 Key、模型抽风、网断了，都退回
///    `RuleCardMatcher`，同时把原因记进 `ErrorLog`。绝不静默地丢掉用户的输入。
@MainActor
enum CardGenerator {

    /// 整理用的 system prompt。跟用户写的人设**完全无关**，
    /// 所以这段是写死的——它不是角色说的话，是一份工单
    static let systemPrompt = """
    你是一个把随手记的碎片整理成结构化卡片的工具。
    你不是任何角色，不要有情绪、不要安慰、不要评论，也不要跟用户说话。
    只输出要求的 JSON，多一个字都不要。
    """

    static func make(from fragment: Fragment, store: ChatStore) async -> TimelineCard {
        let text = fragment.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return RuleCardMatcher.card(for: fragment) }

        // 整理是脏活，正好交给便宜模型。没配就退回主模型，行为跟以前一样
        let picked = SubModelConfig.resolve(fallbackProvider: store.provider,
                                            fallbackKey: store.apiKey,
                                            fallbackModel: store.model)
        guard !picked.key.isEmpty else {
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
            ErrorLog.shared.record(source: "整理卡片", message: error.localizedDescription)
            return RuleCardMatcher.card(for: fragment)
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
            ErrorLog.shared.record(source: "整理卡片",
                                   message: (problem.errorDescription ?? "没通过校验")
                                            + "。已经用规则整理了一张顶上")
            return RuleCardMatcher.card(for: fragment)
        }
    }
    // MARK: - 驱动

    /// 整理一条。已经整理过的直接跳过——一条碎片只该有一张卡片
    static func organize(_ fragment: Fragment, into cards: CardStore, store: ChatStore) async {
        guard !cards.organizedFragmentIDs.contains(fragment.id) else { return }
        guard !cards.working.contains(fragment.id) else { return }
        cards.setWorking(fragment.id, true)
        defer { cards.setWorking(fragment.id, false) }
        let card = await make(from: fragment, store: store)
        cards.add(card)
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
