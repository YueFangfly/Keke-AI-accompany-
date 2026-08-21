import Foundation

/// 日历：每天的心情打点（我+克克）、聊天摘要缓存
@MainActor
final class CalendarService: ObservableObject {
    @Published var moods: [String: DayMood] = [:]
    @Published var summaries: [String: String] = [:]

    private var moodsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keke_calendar_moods.json")
    }
    private var summariesURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keke_calendar_summaries.json")
    }

    init() {
        load()
    }

    // MARK: - 心情

    func myMood(on date: Date) -> String? { moods[key(date)]?.myMood }
    func kekeMood(on date: Date) -> String? { moods[key(date)]?.kekeMood }

    func setMyMood(_ emoji: String, on date: Date) {
        var entry = moods[key(date)] ?? DayMood()
        entry.myMood = emoji
        moods[key(date)] = entry
        save()
    }

    func setKekeMood(_ emoji: String, on date: Date) {
        var entry = moods[key(date)] ?? DayMood()
        entry.kekeMood = emoji
        moods[key(date)] = entry
        save()
    }

    // MARK: - 心情手帐（emoji + 小记）

    func note(on date: Date) -> String? { moods[key(date)]?.note }

    /// 保存这一天我的心情 + 小记
    func setMyDay(mood: String, note: String, on date: Date) {
        var entry = moods[key(date)] ?? DayMood()
        entry.myMood = mood
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = trimmed.isEmpty ? nil : trimmed
        moods[key(date)] = entry
        save()
    }

    /// 清掉这一天我的心情和小记（克克那栏不动）
    func clearMyDay(on date: Date) {
        var entry = moods[key(date)] ?? DayMood()
        entry.myMood = nil
        entry.note = nil
        moods[key(date)] = entry
        save()
    }

    /// 勾了「顺便告诉克克」：这天的心情记进她的记忆；接了 Key 的话，她还会在聊天里回一句
    func tellKeke(mood: String, note: String, date: Date, store: ChatStore) async {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let dateText = formatter.string(from: date)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteText = trimmedNote.isEmpty ? "" : "，记了一句：\(trimmedNote)"

        // 按 emoji 粗分好坏，让这条记忆带上情绪坐标
        let positive = ["😊", "🥰", "😆", "🥳", "😌", "🙂"]
        let negative = ["😢", "😭", "😡", "😰", "🤒", "😪"]
        let valence: Double = positive.contains(mood) ? 0.5 : (negative.contains(mood) ? -0.5 : 0)
        store.memory?.add("\(dateText) \(store.myName) 在日历记下心情 \(mood)\(noteText)",
                          valence: valence, arousal: 0.3)

        guard !store.apiKey.isEmpty else { return }
        let pName = PersonaStore.persona(for: store.personaId).name
        guard let line = try? await ClaudeService.generateMoodReaction(
            dateText: dateText, mood: mood, note: trimmedNote.isEmpty ? nil : trimmedNote,
            userName: store.myName,
            personaName: pName,
            provider: store.provider, apiKey: store.apiKey,
            model: store.model, systemPrompt: store.effectiveSystemPrompt
        ) else { return }
        store.receiveNudge(line)
    }

    /// 让 AI 根据这天的聊天记录，自动判断我和克克那天的心情（选好之后还是能手动改）
    func autoDetectMoods(for date: Date, store: ChatStore, options: [String]) async {
        let dayMessages = store.messages.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        guard !dayMessages.isEmpty else { return }
        let pName = PersonaStore.persona(for: store.personaId).name
        let lines = dayMessages
            .map { ($0.role == .user ? "\(store.myName)：" : "\(pName)：") + $0.text }
            .joined(separator: "\n")

        guard let result = try? await ClaudeService.generateDayMoods(
            chatLines: lines, moodOptions: options, userName: store.myName,
            personaName: pName,
            provider: store.provider, apiKey: store.apiKey,
            model: store.model, systemPrompt: store.effectiveSystemPrompt
        ) else { return }

        setMyMood(result.myMood, on: date)
        setKekeMood(result.kekeMood, on: date)
    }

    // MARK: - 聊天摘要（只给过去的日子缓存，今天可能还在继续聊）

    func summary(for date: Date, store: ChatStore) async -> String {
        let dayKey = key(date)
        if let cached = summaries[dayKey] { return cached }

        let dayMessages = store.messages.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        guard !dayMessages.isEmpty else {
            return L.t("这天没有聊天记录", store.appLanguage)
        }
        let lines = dayMessages
            .map { ($0.role == .user ? "\(store.myName)：" : "\(PersonaStore.persona(for: store.personaId).name)：") + $0.text }
            .joined(separator: "\n")

        guard let text = try? await ClaudeService.generateDaySummary(
            chatLines: lines, userName: store.myName, provider: store.provider, apiKey: store.apiKey,
            model: store.model, systemPrompt: store.effectiveSystemPrompt
        ) else {
            return L.t("摘要生成失败，重试一下", store.appLanguage)
        }

        if !Calendar.current.isDateInToday(date) {
            summaries[dayKey] = text
            save()
        }
        return text
    }

    private func key(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - 持久化

    private func save() {
        if let data = try? JSONEncoder().encode(moods) {
            try? data.write(to: moodsURL, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(summaries) {
            try? data.write(to: summariesURL, options: .atomic)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: moodsURL),
           let saved = try? JSONDecoder().decode([String: DayMood].self, from: data) {
            moods = saved
        }
        if let data = try? Data(contentsOf: summariesURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            summaries = saved
        }
    }
}

struct DayMood: Codable, Equatable {
    var myMood: String?
    var kekeMood: String?
    /// 这天的一句小记（心情手帐），可空
    var note: String?
}
