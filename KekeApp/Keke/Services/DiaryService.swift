import Foundation

/// 私密日记：我和克克各写各的。作者自己决定每一篇给不给对方看；
/// 克克没公开的可以"偷看"，有概率被她发现；我分享给她的，她会（不是秒回地）看完留个反应
@MainActor
final class DiaryService: ObservableObject {
    let personaId: String
    @Published var entries: [DiaryEntry] = []

    @Published var writeProbability: Double {
        didSet { UserDefaults.standard.set(writeProbability, forKey: "\(personaId)_diary_write_prob") }
    }
    @Published var peekNoticeProbability: Double {
        didSet { UserDefaults.standard.set(peekNoticeProbability, forKey: "\(personaId)_diary_notice_prob") }
    }
    @Published var readProbability: Double {
        didSet { UserDefaults.standard.set(readProbability, forKey: "\(personaId)_diary_read_prob") }
    }

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_diary.json")
    }

    init(personaId: String = "keke") {
        self.personaId = personaId
        let d = UserDefaults.standard
        writeProbability = d.object(forKey: "\(personaId)_diary_write_prob") as? Double ?? 0.5
        peekNoticeProbability = d.object(forKey: "\(personaId)_diary_notice_prob") as? Double ?? 0.4
        readProbability = d.object(forKey: "\(personaId)_diary_read_prob") as? Double ?? 0.4
        load()
    }

    var myEntries: [DiaryEntry] { entries.filter { $0.author == .me }.sorted { $0.date > $1.date } }
    var kekeEntries: [DiaryEntry] { entries.filter { $0.author == .keke }.sorted { $0.date > $1.date } }

    // MARK: - 我写日记

    func postMine(text: String, shared: Bool, imagePath: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(DiaryEntry(author: .me, text: trimmed, sharedWithOther: shared, imagePath: imagePath), at: 0)
        save()
    }

    func setShared(_ shared: Bool, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].sharedWithOther = shared
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    // MARK: - 评论

    func addComment(to entryID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].comments.append(DiaryComment(author: .me, text: trimmed))
        save()
    }

    /// App 回到前台时调用：克克能看到的条目里，如果我留了条她还没回过的评论，有概率回一句
    func maybeReplyToComments(store: ChatStore) async {
        guard !store.apiKey.isEmpty else { return }
        let visible = entries.filter { $0.author == .keke || $0.sharedWithOther || $0.peeked }
        for entry in visible {
            guard let lastComment = entry.comments.last, lastComment.author == .me else { continue }
            let lastKekeReply = entry.comments.last(where: { $0.author == .keke })
            guard lastKekeReply == nil || lastKekeReply!.date < lastComment.date else { continue }
            guard Double.random(in: 0..<1) < 0.4 else { continue }

            guard let reply = try? await ClaudeService.generateDiaryCommentReply(
                entryPreview: String(entry.text.prefix(60)), comment: lastComment.text, userName: store.myName,
                personaName: PersonaStore.persona(for: store.personaId).name,
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt
            ) else { continue }

            guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { continue }
            entries[index].comments.append(DiaryComment(author: .keke, text: reply))
            save()
        }
    }

    // MARK: - 克克写日记

    /// App 回到前台时调用：克克今天还没写的话，有概率写一篇（不是每天一定写）。
    /// moments 传进来是为了她有概率把今天发过的朋友圈照片顺手配到日记里，
    /// 就当是"今天玩过的内容的截屏"，不是她自己画/生成的图
    func maybeWriteKekeDiary(store: ChatStore, petStats: PetStatsService, moments: MomentsStore) async {
        guard !store.apiKey.isEmpty else { return }
        // 🫧 漂流思绪那篇不算"今天写过日记"，不然她当天就不写正经日记了
        guard !entries.contains(where: {
            $0.author == .keke && Calendar.current.isDateInToday($0.date) && !$0.text.hasPrefix("🫧")
        }) else { return }
        guard Double.random(in: 0..<1) < writeProbability else { return }

        let recent = store.messages.suffix(16)
            .map { ($0.role == .user ? "\(store.myName)：" : "\(PersonaStore.persona(for: store.personaId).name)：") + $0.text }
            .joined(separator: "\n")
        let moodHint = "（仅供你自己把握语气参考，不要直接告诉 \(store.myName) 这些数字：最近心情值 \(Int(petStats.mood))/100，亲密度 \(Int(petStats.bond))/100）"

        guard let result = try? await ClaudeService.generateKekeDiary(
            recentChat: recent.isEmpty ? nil : recent, moodHint: moodHint, userName: store.myName,
            personaName: PersonaStore.persona(for: store.personaId).name,
            provider: store.provider, apiKey: store.apiKey, model: store.model,
            systemPrompt: store.effectiveSystemPrompt
        ) else { return }

        var imagePath: String?
        let todaysPhotos = moments.moments.filter { Calendar.current.isDateInToday($0.date) && $0.imagePath != nil }
        if let picked = todaysPhotos.randomElement(), Double.random(in: 0..<1) < 0.4 {
            imagePath = picked.imagePath
        }

        entries.insert(DiaryEntry(author: .keke, text: result.text, sharedWithOther: result.share, imagePath: imagePath), at: 0)
        save()
    }

    /// 漂流思绪顺手记进克克的日记：同一天的思绪合并成一篇（🫧 开头），
    /// 一条一行带时间，不会把日记刷屏。这篇默认是公开的——思绪本来就是给她看的
    func appendDriftThought(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let line = "· \(formatter.string(from: Date())) \(trimmed)"
        if let index = entries.firstIndex(where: {
            $0.author == .keke && $0.text.hasPrefix("🫧") && Calendar.current.isDateInToday($0.date)
        }) {
            entries[index].text += "\n" + line
        } else {
            entries.insert(DiaryEntry(author: .keke, text: "🫧 漂流思绪\n" + line, sharedWithOther: true), at: 0)
        }
        save()
    }

    // MARK: - 偷看 / 被读

    /// 偷看克克没公开的一篇；第一次偷看才会真的判定"有没有被发现"，返回被发现时她说的那句话
    @discardableResult
    func peek(_ entry: DiaryEntry, store: ChatStore) async -> String? {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return nil }
        guard !entries[index].peeked else { return entries[index].reaction }
        entries[index].peeked = true
        let noticed = Double.random(in: 0..<1) < peekNoticeProbability
        entries[index].peekNoticed = noticed
        save()

        guard noticed, !store.apiKey.isEmpty else { return nil }
        guard let line = try? await ClaudeService.generateDiaryPeekCaught(
            entryPreview: String(entry.text.prefix(60)), userName: store.myName,
            provider: store.provider, apiKey: store.apiKey, model: store.model,
            systemPrompt: store.effectiveSystemPrompt
        ) else { return nil }

        guard let index2 = entries.firstIndex(where: { $0.id == entry.id }) else { return line }
        entries[index2].reaction = line
        save()
        return line
    }

    /// App 回到前台时调用：克克有概率翻到我分享给她的日记，看完留句反应（不是秒回）
    func maybeReadMyDiary(store: ChatStore) async {
        guard !store.apiKey.isEmpty else { return }
        let unread = entries.filter { $0.author == .me && $0.sharedWithOther && !$0.readByOther }
        for entry in unread {
            guard Double.random(in: 0..<1) < readProbability else { continue }
            guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { continue }
            entries[index].readByOther = true
            if let line = try? await ClaudeService.generateDiaryReadReaction(
                entryPreview: String(entry.text.prefix(60)), userName: store.myName,
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt
            ) {
                entries[index].reaction = line
            }
            save()
        }
    }

    // MARK: - 持久化

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([DiaryEntry].self, from: data) else { return }
        entries = saved
    }
}
