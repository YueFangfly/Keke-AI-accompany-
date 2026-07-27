import SwiftUI
import UIKit
import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var kekeMood: KekeMood = .idle
    /// 从侧边栏搜索跳转到某条消息
    @Published var scrollTarget: UUID?

    /// 当前选中的 AI 提供方；切换时自动换成那家存好的 Key 和模型
    @Published var provider: AIProvider = .deepseek {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: "ai_provider")
            apiKey = apiKeys[provider.id] ?? ""
            model = modelsByProvider[provider.id] ?? provider.defaultModel
        }
    }
    /// 当前提供方的 API Key（切换 provider 时自动换成对应的那份）
    @Published var apiKey: String = "" {
        didSet {
            apiKeys[provider.id] = apiKey
            UserDefaults.standard.set(apiKeys, forKey: "ai_api_keys")
        }
    }
    /// 当前提供方的模型
    @Published var model: String = "" {
        didSet {
            modelsByProvider[provider.id] = model
            UserDefaults.standard.set(modelsByProvider, forKey: "ai_models")
        }
    }

    private var apiKeys: [String: String] =
        (UserDefaults.standard.dictionary(forKey: "ai_api_keys") as? [String: String]) ?? [:]
    private var modelsByProvider: [String: String] =
        (UserDefaults.standard.dictionary(forKey: "ai_models") as? [String: String]) ?? [:]

    /// 克克的人设；空字符串代表用内置默认人设
    @Published var customPrompt: String = UserDefaults.standard.string(forKey: "keke_custom_prompt") ?? "" {
        didSet { UserDefaults.standard.set(customPrompt, forKey: "keke_custom_prompt") }
    }
    /// 实际发给模型的 system prompt
    var effectiveSystemPrompt: String {
        let trimmed = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ClaudeService.defaultSystemPrompt(userName: myName) : customPrompt
    }

    /// 外观：system（跟随系统）/ light / dark
    @Published var appearanceMode: String = UserDefaults.standard.string(forKey: "keke_appearance") ?? "system" {
        didSet { UserDefaults.standard.set(appearanceMode, forKey: "keke_appearance") }
    }

    /// 主题配色：mist（月雾，默认）/ deepSea（深海）/ starryCats（星夜猫猫）。
    /// Theme 的颜色都是按 Theme.selected 现取的，改这里会同步过去并触发整个界面重绘
    @Published var appTheme: String = UserDefaults.standard.string(forKey: "keke_theme") ?? "mist" {
        didSet {
            UserDefaults.standard.set(appTheme, forKey: "keke_theme")
            Theme.selected = AppTheme(rawValue: appTheme) ?? .mist
        }
    }

    /// 顺便学一门语言：空字符串代表不学；否则是语言的中文名，比如"法语"
    @Published var learningLanguage: String = UserDefaults.standard.string(forKey: "keke_learning_language") ?? "" {
        didSet { UserDefaults.standard.set(learningLanguage, forKey: "keke_learning_language") }
    }

    /// App 界面语言：中文 / English，App 内手动切换，不跟着系统语言走
    @Published var appLanguage: AppLanguage =
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "keke_app_language") ?? "") ?? .zh {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: "keke_app_language") }
    }

    /// App 全局字体：default / rounded / serif / monospaced
    @Published var fontDesign: String = UserDefaults.standard.string(forKey: "keke_font_design") ?? "default" {
        didSet { UserDefaults.standard.set(fontDesign, forKey: "keke_font_design") }
    }
    var fontDesignValue: Font.Design {
        switch fontDesign {
        case "rounded": return .rounded
        case "serif": return .serif
        case "monospaced": return .monospaced
        default: return .default
        }
    }

    /// 我的名字，显示在朋友圈/收藏这些地方；不影响克克在聊天里怎么称呼我（那个由人设决定）
    @Published var myName: String = UserDefaults.standard.string(forKey: "keke_my_name") ?? "wifey" {
        didSet { UserDefaults.standard.set(myName, forKey: "keke_my_name") }
    }
    /// 我的头像（attachments 目录里的文件名）
    @Published var myAvatarPath: String? = UserDefaults.standard.string(forKey: "keke_my_avatar") {
        didSet {
            if let myAvatarPath {
                UserDefaults.standard.set(myAvatarPath, forKey: "keke_my_avatar")
            } else {
                UserDefaults.standard.removeObject(forKey: "keke_my_avatar")
            }
        }
    }
    /// 聊天页背景图（attachments 目录里的文件名）；不设置就用默认的玻璃拟态渐变
    @Published var chatBackgroundPath: String? = UserDefaults.standard.string(forKey: "keke_chat_bg") {
        didSet {
            if let chatBackgroundPath {
                UserDefaults.standard.set(chatBackgroundPath, forKey: "keke_chat_bg")
            } else {
                UserDefaults.standard.removeObject(forKey: "keke_chat_bg")
            }
        }
    }

    /// 长期记忆（recall 思路），由 RootView 注入
    var memory: MemoryService?
    /// 本机状态（电池/步数/定位/日程/提醒），由 RootView 注入
    var device: DeviceContextService?
    /// 朋友圈，由 RootView 注入；用于克克回完消息后小概率自己想发一条
    var moments: MomentsStore?
    /// 养克克的状态，由 RootView 注入；每次她回完消息心情/亲密度会涨一点
    var petStats: PetStatsService?
    /// 主动冒泡通知，由 RootView 注入；用于聊天里让克克直接改冒泡频率/开关
    var nudge: NudgeService?
    /// 私密日记，由 RootView 注入；用于聊天里让克克直接改日记的三个概率
    var diary: DiaryService?
    /// 状态面板，由 RootView 注入；记忆提炼时顺便让克克更新数值 + 留一句漂流思绪
    var kekeState: KekeStateService?

    /// 允许克克上网查东西 / 打开链接
    @Published var webEnabled: Bool = (UserDefaults.standard.object(forKey: "keke_web_enabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(webEnabled, forKey: "keke_web_enabled") }
    }

    /// 回到 App 时，隔了挺久没聊的话，克克可能先开口
    @Published var speakFirstEnabled: Bool = (UserDefaults.standard.object(forKey: "keke_speak_first") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(speakFirstEnabled, forKey: "keke_speak_first") }
    }

    /// 允许克克在聊天里直接帮你改设置（日记概率、主动冒泡、外观、字体、学语言等）
    @Published var settingsToolsEnabled: Bool = (UserDefaults.standard.object(forKey: "keke_settings_tools") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(settingsToolsEnabled, forKey: "keke_settings_tools") }
    }

    var favorites: [ChatMessage] {
        messages.filter(\.isFavorite)
    }

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keke_chat.json")
    }

    /// 正在进行的请求，方便"停止"按钮取消
    private var currentTask: Task<Void, Never>?

    init(memory: MemoryService? = nil, device: DeviceContextService? = nil,
         moments: MomentsStore? = nil, petStats: PetStatsService? = nil) {
        self.memory = memory
        self.device = device
        self.moments = moments
        self.petStats = petStats
        provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: "ai_provider") ?? "") ?? .deepseek
        load()
        if messages.isEmpty {
            append(ChatMessage(role: .keke, text: "在。*挥爪*"))
        }
    }

    func send(_ text: String, image: UIImage? = nil, doc: (name: String, text: String)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil || doc != nil, !isThinking else { return }
        var message = ChatMessage(role: .user, text: trimmed)
        if let image, let name = Attachments.saveImage(image) {
            message.imagePath = name
        }
        if let doc {
            message.docName = doc.name
            message.docText = doc.text
        }
        append(message)
        currentTask = Task { await requestReply() }
    }

    /// 停止正在等待的回复
    func cancelSend() {
        currentTask?.cancel()
        currentTask = nil
        isThinking = false
        kekeMood = .idle
    }

    private func requestReply() async {
        isThinking = true
        kekeMood = .thinking
        do {
            // recall：按最后一句话的相关度取出长期记忆；再拼上她允许克克看的本机状态和语言学习设置
            let lastUserText = messages.last(where: { $0.role == .user })?.text ?? ""
            var contextParts: [String] = []
            if let memoryBlock = memory?.contextBlock(for: lastUserText, userName: myName) {
                contextParts.append(memoryBlock)
            }
            if let deviceBlock = await device?.contextBlock(userName: myName) {
                contextParts.append(deviceBlock)
            }
            if let imageBlock = await localImageContextBlock() {
                contextParts.append(imageBlock)
            }
            if let languageBlock = learningLanguageBlock {
                contextParts.append(languageBlock)
            }
            let context = contextParts.isEmpty ? nil : contextParts.joined(separator: "\n\n")
            let raw = try await ClaudeService.send(messages: messages, userName: myName, provider: provider, apiKey: apiKey,
                                                   model: model, systemPrompt: effectiveSystemPrompt,
                                                   extraContext: context, webTools: webEnabled,
                                                   toolExecutor: settingsToolsEnabled && provider == .claude
                                                       ? { [weak self] name, input in
                                                           await self?.executeSettingsTool(name: name, input: input)
                                                               ?? "改不了，页面已经关掉了"
                                                       }
                                                       : nil)
            try Task.checkCancellation()
            let (thinking, text) = ClaudeService.splitThinking(raw)
            append(ChatMessage(role: .keke, text: text, thinking: thinking))
            kekeMood = .happy
            maybeExtractMemories()
            petStats?.onChatReply()
            Task { await moments?.maybeSpontaneousPost(store: self) }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !isThinking, kekeMood == .happy { kekeMood = .idle }
            }
        } catch is CancellationError {
            // 用户主动停止，不显示错误
        } catch {
            append(ChatMessage(role: .keke, text: "*爪子挠头* 好像出了点问题：\(error.localizedDescription)"))
            kekeMood = .idle
        }
        isThinking = false
    }

    private var learningLanguageBlock: String? {
        guard !learningLanguage.isEmpty else { return nil }
        return "\(myName) 想顺便学\(learningLanguage)。在保持克克性格的前提下，适当地在对话里自然地" +
            "教她一些\(learningLanguage)词汇或短句，可以中\(learningLanguage)对照，不用每句话都教，看情况穿插，" +
            "不要变成生硬的教学模式。"
    }

    /// 当前模型不支持看图（比如 DeepSeek）时，用手机本地的 Vision 框架（完全免费）猜一下
    /// 最近这张图片大概是什么，算出来的结果缓存在消息上，不用每轮都重新识别一遍
    private func localImageContextBlock() async -> String? {
        guard !provider.supportsVision else { return nil }
        guard let target = messages.suffix(6).last(where: { $0.imagePath != nil }) else { return nil }

        let description: String
        if let cached = target.localImageCaption {
            description = cached
        } else {
            guard let path = target.imagePath, let image = Attachments.loadImage(named: path) else { return nil }
            description = await Attachments.describeImageLocally(image) ?? ""
            if let index = messages.firstIndex(where: { $0.id == target.id }) {
                messages[index].localImageCaption = description
                // 改的是已存在的那条消息（缓存本地识图结果），整份重写一次；
                // 只有刚发过图、且模型看不了图时才会走到这，很少发生
                rewriteAll()
            }
        }
        guard !description.isEmpty else { return nil }
        return "（\(myName) 发了一张图片，这个模型本身看不了图，下面是手机本地识别出来的大致内容，" +
            "不如真的看图准，可以大概判断，别原样复述给她看——\(description)）"
    }

    // MARK: - 聊天里直接改设置（工具调用）

    /// 执行克克在聊天里调用的「改设置」工具，返回一句给她看的结果说明。
    /// 只处理白名单里的几个设置，其余一律拒绝，不做任意读写
    private func executeSettingsTool(name: String, input: [String: Any]) async -> String {
        switch name {
        case "set_diary_probability":
            guard let which = input["which"] as? String, let raw = input["value"] as? Double else {
                return "参数不对，没改成"
            }
            let value = min(max(raw, 0), 1)
            switch which {
            case "write": diary?.writeProbability = value
            case "peek_notice": diary?.peekNoticeProbability = value
            case "read": diary?.readProbability = value
            default: return "不认识这个选项，没改成"
            }
            return "已经改成 \(Int(value * 100))%"

        case "set_nudge":
            if let enabled = input["enabled"] as? Bool {
                if enabled { await nudge?.enable(store: self) } else { nudge?.disable() }
            }
            if let perDay = input["perDay"] as? Int, (1...3).contains(perDay) {
                nudge?.perDay = perDay
            }
            return "改好了"

        case "set_speak_first_enabled":
            guard let enabled = input["enabled"] as? Bool else { return "参数不对，没改成" }
            speakFirstEnabled = enabled
            return "改好了"

        case "set_web_enabled":
            guard let enabled = input["enabled"] as? Bool else { return "参数不对，没改成" }
            webEnabled = enabled
            return "改好了"

        case "set_appearance_mode":
            guard let mode = input["mode"] as? String, ["system", "light", "dark"].contains(mode) else {
                return "参数不对，没改成"
            }
            appearanceMode = mode
            return "改好了"

        case "set_font_design":
            guard let design = input["design"] as? String,
                  ["default", "rounded", "serif", "monospaced"].contains(design) else {
                return "参数不对，没改成"
            }
            fontDesign = design
            return "改好了"

        case "set_learning_language":
            guard let language = input["language"] as? String else { return "参数不对，没改成" }
            learningLanguage = language
            return language.isEmpty ? "已经关掉了" : "改好了"

        case "create_reminder":
            guard let title = (input["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return "参数不对，没建成" }
            let due = (input["due"] as? String).flatMap(Self.parseToolDate)
            let ok = await device?.createReminder(title: title, due: due, notes: input["notes"] as? String) ?? false
            guard ok else {
                return "没建成——大概是「提醒事项」的权限没开，让她去 iPhone 设置 → Moonlight 里打开提醒事项权限"
            }
            return "提醒「\(title)」建好了" + (due.map { "，时间 \(Self.toolDateText($0))" } ?? "")

        case "create_calendar_event":
            guard let title = (input["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  let startText = input["start"] as? String,
                  let start = Self.parseToolDate(startText) else { return "参数不对，没建成" }
            let end = (input["end"] as? String).flatMap(Self.parseToolDate)
            let ok = await device?.createCalendarEvent(title: title, start: start, end: end,
                                                       notes: input["notes"] as? String) ?? false
            guard ok else {
                return "没建成——大概是「日历」的权限没开，让她去 iPhone 设置 → Moonlight 里打开日历权限"
            }
            return "日程「\(title)」建好了，\(Self.toolDateText(start)) 开始"

        default:
            return "不认识这个工具，没改成"
        }
    }

    /// 工具参数里的时间：优先 "yyyy-MM-dd HH:mm"，只给日期也认
    private static func parseToolDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        if let date = formatter.date(from: text) { return date }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    private static func toolDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 长期记忆的写入

    /// 每积累 10 条新消息，后台让克克提炼一次记忆
    private func maybeExtractMemories() {
        guard memory != nil else { return }
        let lastCount = UserDefaults.standard.integer(forKey: "memory_extracted_at_count")
        guard messages.count - lastCount >= 10 else { return }
        UserDefaults.standard.set(messages.count, forKey: "memory_extracted_at_count")
        Task { _ = await extractMemoriesNow(markCounter: false) }
    }

    /// 立即整理最近聊天成记忆，返回新记住的条数（记忆页的按钮也用它）
    func extractMemoriesNow(markCounter: Bool = true) async -> Int {
        guard let memory else { return 0 }
        if markCounter {
            UserDefaults.standard.set(messages.count, forKey: "memory_extracted_at_count")
        }
        let recent = Array(messages.suffix(40))

        // 有状态面板的话走合并版：记忆 + 状态数值 + 漂流思绪蹭同一次调用
        if let kekeState {
            guard let result = try? await ClaudeService.extractMemoriesAndState(
                recent: recent, existing: memory.allTexts, userName: myName,
                currentState: kekeState.promptLine,
                provider: provider, apiKey: apiKey, model: model, systemPrompt: effectiveSystemPrompt
            ) else { return 0 }
            for entry in result.memories {
                memory.add(entry.text, importance: entry.importance, valence: entry.valence,
                           arousal: entry.arousal, status: entry.open ? .open : .none)
            }
            kekeState.applyAIState(result.state)
            if let thought = result.thought {
                kekeState.addThought(thought)
            }
            return result.memories.count
        }

        guard let new = try? await ClaudeService.extractMemories(
            recent: recent, existing: memory.allTexts, userName: myName, provider: provider, apiKey: apiKey,
            model: model, systemPrompt: effectiveSystemPrompt
        ), !new.isEmpty else { return 0 }
        for entry in new {
            memory.add(entry.text, importance: entry.importance, valence: entry.valence,
                       arousal: entry.arousal, status: entry.open ? .open : .none)
        }
        return new.count
    }

    /// 挂断电话后留一条通话记录：正文是"打了多久"，完整字幕折叠在心里话那个位置里
    func appendCallRecord(text: String, transcript: String?) {
        append(ChatMessage(role: .keke, text: text, thinking: transcript))
    }

    /// 克克主动冒泡的话（来自通知），直接写进聊天记录
    func receiveNudge(_ text: String, date: Date = Date()) {
        append(ChatMessage(role: .keke, text: text, date: date))
    }

    /// 打开 App 时克克先开口：距离上次聊天超过 3 小时、
    /// 且距离上次它主动开口超过 6 小时，才说一句（带记忆和本机状态）
    func kekeSpeaksFirstIfNeeded() async {
        guard speakFirstEnabled, !isThinking, !apiKey.isEmpty else { return }
        guard let last = messages.last else { return }
        guard last.date < Date().addingTimeInterval(-3 * 3600) else { return }
        let lastSpokeAt = UserDefaults.standard.double(forKey: "keke_speak_first_at")
        guard Date().timeIntervalSince1970 - lastSpokeAt > 6 * 3600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "keke_speak_first_at")

        var contextParts: [String] = []
        if let memoryBlock = memory?.contextBlock(for: nil, userName: myName) {
            contextParts.append(memoryBlock)
        }
        if let deviceBlock = await device?.contextBlock(userName: myName) {
            contextParts.append(deviceBlock)
        }
        let context = contextParts.isEmpty ? nil : contextParts.joined(separator: "\n\n")

        guard let lines = try? await ClaudeService.generateNudges(
            messages: messages, userName: myName, provider: provider, apiKey: apiKey, model: model,
            systemPrompt: effectiveSystemPrompt, count: 1, extraContext: context
        ), let line = lines.first else { return }

        append(ChatMessage(role: .keke, text: line))
        kekeMood = .happy
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !isThinking, kekeMood == .happy { kekeMood = .idle }
        }
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isFavorite.toggle()
        rewriteAll()
    }

    /// 删除/撤回一条消息（发错了的话可以撤掉，不会影响下一次发送的上下文）
    func deleteMessage(_ id: UUID) {
        messages.removeAll { $0.id == id }
        rewriteAll()
    }

    func clearAll() {
        messages = [ChatMessage(role: .keke, text: "在。*挥爪*")]
        rewriteAll()
    }

    /// 聊天记录改用「一行一条」的 jsonl 存：新消息只往文件末尾追加一行（O(1)），
    /// 不用每发一句就把整份记录重写一遍——聊到几万条也不会卡。
    /// 只有删除/收藏/清空这种结构性改动才整份重写（很少发生）
    private var jsonlURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keke_chat.jsonl")
    }

    /// 追加一条消息：进内存 + 往文件末尾写一行
    private func append(_ message: ChatMessage) {
        messages.append(message)
        appendLine(message)
    }

    private func appendLine(_ message: ChatMessage) {
        guard var line = try? JSONEncoder().encode(message) else { return }
        line.append(0x0A) // 换行
        if FileManager.default.fileExists(atPath: jsonlURL.path),
           let handle = try? FileHandle(forWritingTo: jsonlURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: jsonlURL, options: .atomic)
        }
    }

    /// 结构性改动才用：把整份记录重写一遍
    private func rewriteAll() {
        var blob = Data()
        for message in messages {
            guard let data = try? JSONEncoder().encode(message) else { continue }
            blob.append(data)
            blob.append(0x0A)
        }
        try? blob.write(to: jsonlURL, options: .atomic)
    }

    private func load() {
        if let data = try? Data(contentsOf: jsonlURL) {
            messages = Self.decodeJSONL(data)
            return
        }
        // 从旧版「整份 JSON 数组」迁移：读进来后写成 jsonl，以后都走增量追加
        if let data = try? Data(contentsOf: saveURL),
           let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = saved
            rewriteAll()
        }
    }

    private static func decodeJSONL(_ data: Data) -> [ChatMessage] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        var result: [ChatMessage] = []
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8),
                  let message = try? decoder.decode(ChatMessage.self, from: lineData) else { return }
            result.append(message)
        }
        return result
    }
}
