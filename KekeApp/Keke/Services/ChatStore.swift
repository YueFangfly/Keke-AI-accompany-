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
            APIKeyStore.setAllKeys(apiKeys)
        }
    }
    /// 当前提供方的模型
    @Published var model: String = "" {
        didSet {
            modelsByProvider[provider.id] = model
            UserDefaults.standard.set(modelsByProvider, forKey: "ai_models")
        }
    }

    private var apiKeys: [String: String] = APIKeyStore.allKeys()
    private var modelsByProvider: [String: String] =
        (UserDefaults.standard.dictionary(forKey: "ai_models") as? [String: String]) ?? [:]

    /// 这个人设的自定义 system prompt；空字符串代表用人设自带的那份
    @Published var customPrompt: String = "" {
        didSet { UserDefaults.standard.set(customPrompt, forKey: "\(personaId)_custom_prompt") }
    }
    /// 实际发给模型的 system prompt。
    ///
    /// 人设**全部由用户自己写**：设置页里写的自定义人设优先，其次是这个人设自带的 systemPrompt。
    /// App 不再内置任何角色描述——两个都为空就只发功能说明，
    /// 模型是什么样子、怎么说话完全由用户决定。
    var effectiveSystemPrompt: String {
        let custom = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let persona = custom.isEmpty
            ? PersonaStore.persona(for: personaId).systemPrompt
            : custom
        return ChatProtocolPrompt.combined(persona: persona,
                                           settingsToolsEnabled: settingsToolsEnabled)
    }

    @Published var appearanceMode: String = "system" {
        didSet { UserDefaults.standard.set(appearanceMode, forKey: "\(personaId)_appearance") }
    }

    @Published var appTheme: String = "mist" {
        didSet {
            UserDefaults.standard.set(appTheme, forKey: "\(personaId)_theme")
            Theme.selected = AppTheme(rawValue: appTheme) ?? .mist
        }
    }

    @Published var learningLanguage: String = "" {
        didSet { UserDefaults.standard.set(learningLanguage, forKey: "\(personaId)_learning_language") }
    }

    @Published var appLanguage: AppLanguage = .zh {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: "\(personaId)_app_language") }
    }

    @Published var fontDesign: String = "default" {
        didSet { UserDefaults.standard.set(fontDesign, forKey: "\(personaId)_font_design") }
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
    /// MCP 模块注册表，由 RootView 注入；开启的模块会变成聊天里能用的工具
    var mcp: MCPRegistry?
    /// 音频播放器，由 PersonaSessionView 注入；用于聊天里调用播放工具后附带 trackId
    var audioPlayer: AudioPlayerService?
    /// 自定义 API 提供方管理
    var customProviderStore: CustomProviderStore?
    var activityLog: ActivityLog?
    var anniversaryStore: AnniversaryStore?
    var typingRhythm: TypingRhythm?
    /// 当前选中的自定义提供方 ID（nil = 用内置提供方）
    @Published var customProviderId: String? = UserDefaults.standard.string(forKey: "custom_provider_id") {
        didSet { UserDefaults.standard.set(customProviderId, forKey: "custom_provider_id") }
    }

    @Published var webEnabled: Bool = true {
        didSet { UserDefaults.standard.set(webEnabled, forKey: "\(personaId)_web_enabled") }
    }

    @Published var speakFirstEnabled: Bool = true {
        didSet { UserDefaults.standard.set(speakFirstEnabled, forKey: "\(personaId)_speak_first") }
    }

    @Published var settingsToolsEnabled: Bool = true {
        didSet { UserDefaults.standard.set(settingsToolsEnabled, forKey: "\(personaId)_settings_tools") }
    }

    /// 生成温度（0.0–2.0），-1 表示不传（用 API 默认值）
    @Published var temperature: Double = -1 {
        didSet { UserDefaults.standard.set(temperature, forKey: "\(personaId)_temperature") }
    }

    /// top_p 值（0.0–1.0），-1 表示不传（用 API 默认值）
    @Published var topP: Double = -1 {
        didSet { UserDefaults.standard.set(topP, forKey: "\(personaId)_top_p") }
    }

    /// 边生成边显示。个别中转站不支持 SSE 或者不认 stream_options，关掉就退回一次性拿完整回复
    @Published var streamEnabled: Bool = true {
        didSet { UserDefaults.standard.set(streamEnabled, forKey: "\(personaId)_stream") }
    }

    /// 让模型先想再答，思考过程可以在气泡上点开看。只有支持的 Claude 模型有这个
    @Published var thinkingEnabled: Bool = false {
        didSet { UserDefaults.standard.set(thinkingEnabled, forKey: "\(personaId)_thinking") }
    }

    /// 生成投入档位。新的 Claude 模型用它替代了 temperature / top_p
    @Published var effort: ReasoningEffort = .high {
        didSet { UserDefaults.standard.set(effort.rawValue, forKey: "\(personaId)_effort") }
    }

    /// 当前模型认不认 temperature / top_p
    var supportsSampling: Bool {
        ModelCapability.supportsSampling(provider: provider, model: model)
    }
    /// 当前模型能不能调生成投入档位
    var supportsEffort: Bool {
        ModelCapability.supportsEffort(provider: provider, model: model)
    }
    /// 当前模型能不能开思考
    var supportsThinking: Bool {
        ModelCapability.supportsThinking(provider: provider, model: model)
    }

    /// 界面上正在显示的流式文字。空字符串代表现在没有在流。
    /// 这份是限流过的，会比真实进度慢几十毫秒
    @Published var streamingText: String = ""
    /// 没限流的那份，每个增量都更新。中断时保存用它，不然会丢掉最后几十毫秒的字
    private var latestStreamText = ""
    /// 上次刷新界面的时间——每个 token 都刷一次 SwiftUI 太浪费，
    /// 隔几十毫秒刷一次眼睛看不出区别
    private var lastStreamPush = Date.distantPast

    // MARK: - 上下文压缩

    /// 更早那些聊天压出来的摘要。跟着每次请求一起发，让她记得住更久以前的事。
    /// 空字符串 = 还没压过
    private(set) var contextSummary = ""
    /// 已经被摘要覆盖掉的消息 id。这些不再原样发给模型，但**聊天记录里一条不少**，
    /// 用户翻上去看到的还是原文
    private var compressedIDs: Set<UUID> = []
    /// 正在后台压缩，避免同时压两次
    private var isCompressing = false

    private var compressionURL: URL {
        docsDir.appendingPathComponent("\(personaId)_context.json")
    }

    /// 界面上要显示的消息：重新生成产生的旧版本不显示（但留在文件里，切回去还能看）
    var visibleMessages: [ChatMessage] {
        messages.filter(\.isVisibleVersion)
    }

    /// 真正发给模型的那一份。
    ///
    /// compactMap(\.modelPayload) 会把 systemNote（通话记录、报错这类界面文案）
    /// 直接滤掉——它们的 modelPayload 是 nil。trace / reasoning / usage
    /// 也进不来，Payload 里根本没有这些字段
    private var payloadForRequest: [ChatMessage.Payload] {
        messagesForRequest.compactMap(\.modelPayload)
    }

    /// 这次请求要发的历史：摘要没覆盖到的、并且是当前选中那一版的
    private var messagesForRequest: [ChatMessage] {
        let active = messages.filter(\.isVisibleVersion)
        guard !compressedIDs.isEmpty else { return active }
        let pending = active.filter { !compressedIDs.contains($0.id) }
        // 理论上到不了这里（保留段至少还剩十几条）。真到了说明摘要状态和聊天记录对不上，
        // 这时候宁可多发点历史，也不能让聊天直接不能用
        return pending.isEmpty ? active.suffix(ContextCompressor.triggerCount).map { $0 } : pending
    }

    /// 发给模型的历史条数上限。压缩正常工作时窗口远小于这个数，够不着；
    /// 压缩要是一直失败（比如摘要模型没配好），它负责兜住，不让上下文无限涨
    private var historyBackstop: Int { ContextCompressor.triggerCount * 2 }

    /// 这次请求实际发给了谁。只有真的找到自定义供应商配置才算 custom，
    /// 光有 customProviderId 但配置已经被删了的话，走的还是内置那家
    private var currentProviderId: String {
        customProviderStore?.provider(for: customProviderId ?? "") == nil
            ? provider.rawValue : "custom"
    }

    let personaId: String

    var favorites: [ChatMessage] {
        messages.filter(\.isFavorite)
    }

    private var docsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var saveURL: URL {
        docsDir.appendingPathComponent("\(personaId)_chat.json")
    }

    /// 正在进行的请求，方便"停止"按钮取消
    private var currentTask: Task<Void, Never>?
    /// 这次请求是某条回复的"再来一版"，回来的消息要归进这一组
    private var pendingRegenerationGroup: UUID?

    /// 当前可用的工具。顺序固定，因为 tools 是缓存前缀的第一段，
    /// 变一下整个 prompt cache 就作废
    private var toolRegistry: ToolRegistry {
        ToolRegistry(tools: mcp?.enabledTools() ?? [])
    }
    private var lastRhythmSnapshot: RhythmSnapshot?

    init(personaId: String = "keke",
         memory: MemoryService? = nil, device: DeviceContextService? = nil,
         moments: MomentsStore? = nil, petStats: PetStatsService? = nil) {
        self.personaId = personaId
        self.memory = memory
        self.device = device
        self.moments = moments
        self.petStats = petStats
        provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: "ai_provider") ?? "") ?? .deepseek
        customPrompt = UserDefaults.standard.string(forKey: "\(personaId)_custom_prompt") ?? ""

        let ud = UserDefaults.standard
        appearanceMode = ud.string(forKey: "\(personaId)_appearance")
            ?? ud.string(forKey: "keke_appearance") ?? "system"
        let theme = ud.string(forKey: "\(personaId)_theme")
            ?? ud.string(forKey: "keke_theme") ?? "mist"
        appTheme = theme
        Theme.selected = AppTheme(rawValue: theme) ?? .mist
        learningLanguage = ud.string(forKey: "\(personaId)_learning_language")
            ?? ud.string(forKey: "keke_learning_language") ?? ""
        appLanguage = AppLanguage(rawValue: ud.string(forKey: "\(personaId)_app_language") ?? "")
            ?? AppLanguage(rawValue: ud.string(forKey: "keke_app_language") ?? "") ?? .zh
        fontDesign = ud.string(forKey: "\(personaId)_font_design")
            ?? ud.string(forKey: "keke_font_design") ?? "default"
        webEnabled = (ud.object(forKey: "\(personaId)_web_enabled") as? Bool)
            ?? (ud.object(forKey: "keke_web_enabled") as? Bool) ?? true
        speakFirstEnabled = (ud.object(forKey: "\(personaId)_speak_first") as? Bool)
            ?? (ud.object(forKey: "keke_speak_first") as? Bool) ?? true
        settingsToolsEnabled = (ud.object(forKey: "\(personaId)_settings_tools") as? Bool)
            ?? (ud.object(forKey: "keke_settings_tools") as? Bool) ?? true
        temperature = (ud.object(forKey: "\(personaId)_temperature") as? Double)
            ?? (ud.object(forKey: "keke_temperature") as? Double) ?? -1
        topP = (ud.object(forKey: "\(personaId)_top_p") as? Double)
            ?? (ud.object(forKey: "keke_top_p") as? Double) ?? -1
        streamEnabled = (ud.object(forKey: "\(personaId)_stream") as? Bool)
            ?? (ud.object(forKey: "keke_stream") as? Bool) ?? true
        thinkingEnabled = (ud.object(forKey: "\(personaId)_thinking") as? Bool) ?? false
        effort = ReasoningEffort(rawValue: ud.string(forKey: "\(personaId)_effort") ?? "")
            ?? ReasoningEffort.apiDefault

        load()
        loadCompressionState()
        if messages.isEmpty {
            _ = PersonaStore.persona(for: personaId)
            let greeting = personaId == "keke" ? "在。*挥爪*" : "你好！"
            append(ChatMessage(role: .keke, text: greeting))
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
        let preview = String(trimmed.prefix(30))
        activityLog?.log(.homepage, "发了消息给\(PersonaStore.persona(for: personaId).name)：\(preview)")
        lastRhythmSnapshot = typingRhythm?.messageSent()
        currentTask = Task { await requestReply() }
    }

    @Published var thinkingStatus: String = ""

    /// 停止正在等待的回复
    func cancelSend() {
        currentTask?.cancel()
        currentTask = nil
        isThinking = false
        thinkingStatus = ""
        kekeMood = .idle
    }

    private func requestReply() async {
        isThinking = true
        kekeMood = .thinking
        do {
            let lastUserText = messages.last(where: { $0.role == .user })?.text ?? ""

            // ── 路由层：端上模型判断这轮要不要工具、要不要记忆。
            // 不可用 / 超时 / 出错都会返回 passthrough，这里不用分辨是哪种。
            // 部署目标还是 iOS 16.1，所以现在绝大多数设备走的就是 passthrough
            let route = await OnDeviceRouter.decide(userText: lastUserText)

            thinkingStatus = L.t("回忆中...", appLanguage)
            var contextParts: [String] = []
            if !contextSummary.isEmpty {
                contextParts.append(ContextCompressor.contextBlock(summary: contextSummary, userName: myName))
            }
            // 路由说这轮用不上记忆就不注入，省 token。
            // 端上模型没参与时 needsMemory 是 true，行为跟以前一样
            if route.needsMemory,
               let memoryBlock = memory?.contextBlock(for: lastUserText, userName: myName) {
                contextParts.append(memoryBlock)
            }
            thinkingStatus = L.t("感知环境...", appLanguage)
            let timeFmt = DateFormatter()
            timeFmt.dateFormat = "yyyy-MM-dd HH:mm (EEEE)"
            timeFmt.locale = Locale(identifier: "zh_CN")
            contextParts.append("现在是 \(timeFmt.string(from: Date()))")
            if let deviceBlock = await device?.contextBlock(userName: myName) {
                contextParts.append(deviceBlock)
            }
            if let imageBlock = await localImageContextBlock() {
                contextParts.append(imageBlock)
            }
            if let languageBlock = learningLanguageBlock {
                contextParts.append(languageBlock)
            }
            if let activityBlock = activityLog?.contextBlock(userName: myName) {
                contextParts.append(activityBlock)
            }
            if let anniversaryBlock = anniversaryStore?.contextBlock(userName: myName) {
                contextParts.append(anniversaryBlock)
            }
            if let snapshot = lastRhythmSnapshot, let hint = typingRhythm?.contextHint(for: snapshot) {
                contextParts.append(hint)
            }
            if let swallowHint = typingRhythm?.swallowedWordsHint() {
                contextParts.append(swallowHint)
            }
            lastRhythmSnapshot = nil
            let context = contextParts.isEmpty ? nil : contextParts.joined(separator: "\n\n")
            // tools 一律全量挂着、顺序固定：它是缓存前缀的第一段，
            // 按路由结果动态增删会让整个 prompt cache 每轮作废。
            // 路由控制的是"要不要跑工具循环"和"要不要注入记忆"，不是 tools 本身
            let registry = toolRegistry
            let mcpTools = registry.schemas
            let hasTools = settingsToolsEnabled || !mcpTools.isEmpty
            let canCallTools = hasTools && provider.supportsFunctionCalling
            let customBaseURL: String? = customProviderStore?.provider(for: customProviderId ?? "").map(\.baseURL)
            let customVision: Bool? = customProviderStore?.provider(for: customProviderId ?? "").map(\.supportsVision)
            thinkingStatus = L.t("思考中...", appLanguage)
            let lang = appLanguage
            let statusCallback: @Sendable (String) -> Void = { text in
                let localized = L.t(text, lang)
                Task { @MainActor [weak self] in self?.thinkingStatus = localized }
            }
            let deltaCallback: @MainActor (String) -> Void = { [weak self] text in
                self?.pushStreamingText(text)
            }
            let reply = try await ClaudeService.send(messages: payloadForRequest, userName: myName, provider: provider, apiKey: apiKey,
                                                     model: model, systemPrompt: effectiveSystemPrompt,
                                                     extraContext: context,
                                                     temperature: temperature >= 0 ? temperature : nil,
                                                     topP: topP >= 0 ? topP : nil,
                                                     webTools: webEnabled,
                                                     extraTools: mcpTools,
                                                     baseURLOverride: customBaseURL,
                                                     supportsVisionOverride: customVision,
                                                     toolExecutor: canCallTools
                                                         ? { [weak self] name, input in
                                                             // 注册表跑出来的结果已经过 ToolResultEnvelope 封装
                                                             if registry.tool(named: name) != nil {
                                                                 return await registry.run(name: name, input: input)
                                                             }
                                                             // 改设置是本地动作不是外部数据，包成普通工具结果
                                                             let text = await self?.executeSettingsTool(name: name, input: input)
                                                                 ?? "改不了，页面已经关掉了"
                                                             return ToolResultEnvelope.wrap(ToolOutput(text: text),
                                                                                            toolName: name, maxChars: 500)
                                                         }
                                                         : nil,
                                                     onStatus: statusCallback,
                                                     stream: streamEnabled,
                                                     onDelta: deltaCallback,
                                                     historyLimit: historyBackstop,
                                                     effort: supportsEffort ? effort : nil,
                                                     thinking: thinkingEnabled)
            try Task.checkCancellation()
            thinkingStatus = ""
            resetStreamingText()
            let parsed = ClaudeService.splitChoices(reply.text)
            let pendingAudio = audioPlayer?.pendingTrackId
            audioPlayer?.pendingTrackId = nil
            let regenerated = takePendingRegenerationGroup()
            append(ChatMessage(role: .keke, text: parsed.text,
                               choices: parsed.choices,
                               multiSelect: parsed.choices != nil ? parsed.multiSelect : nil,
                               audioTrackId: pendingAudio,
                               usage: reply.usage.isEmpty ? nil : reply.usage,
                               durationMs: reply.durationMs,
                               model: model,
                               providerId: currentProviderId,
                               groupId: regenerated?.groupId,
                               version: regenerated?.version,
                               reasoning: reply.reasoning.isEmpty ? nil : reply.reasoning,
                               trace: route.trace))
            kekeMood = .happy
            maybeExtractMemories()
            maybeCompressContext()
            petStats?.onChatReply()
            Task { await moments?.maybeSpontaneousPost(store: self) }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !isThinking, kekeMood == .happy { kekeMood = .idle }
            }
        } catch is CancellationError {
            // 用户主动停止，不显示错误。
            // 但流式下她可能已经说了半句，这半句用户是看着它出来的——
            // 直接抹掉太怪，落成一条消息留着
            keepPartialStreamIfAny()
        } catch {
            // 出错前流出来的半句同样保留：网断在半路时，能看到她说到哪儿了
            keepPartialStreamIfAny()
            // 标成 systemNote：这是界面上的报错提示，不是她说的话。
            // 以前它会随每轮请求发给模型，模型看多了会学着自己编报错
            append(ChatMessage(role: .keke,
                               text: "*爪子挠头* 好像出了点问题：\(error.localizedDescription)",
                               kind: .systemNote))
            kekeMood = .idle
        }
        thinkingStatus = ""
        resetStreamingText()
        restorePendingRegenerationIfNeeded()
        isThinking = false
    }

    // MARK: - 上下文压缩：存取和触发

    private struct CompressionState: Codable {
        var summary: String
        var compressedIDs: [UUID]
    }

    private func loadCompressionState() {
        guard let data = try? Data(contentsOf: compressionURL),
              let state = try? JSONDecoder().decode(CompressionState.self, from: data) else { return }
        contextSummary = state.summary
        compressedIDs = Set(state.compressedIDs)
    }

    private func saveCompressionState() {
        let state = CompressionState(summary: contextSummary, compressedIDs: Array(compressedIDs))
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: compressionURL, options: .atomic)
    }

    /// 清空聊天记录时把摘要一起清掉，否则会残留一段没有对应原文的记忆
    private func clearCompressionState() {
        contextSummary = ""
        compressedIDs = []
        try? FileManager.default.removeItem(at: compressionURL)
    }

    /// 每次回复完检查一下：没压缩的消息攒够了就在后台压一次。
    /// 压缩失败不影响聊天——大不了这轮不压，下次回复完再试
    private func maybeCompressContext() {
        guard !isCompressing else { return }
        let pending = messagesForRequest
        guard ContextCompressor.shouldCompress(pending) else { return }

        let (toCompress, _) = ContextCompressor.split(pending)
        guard !toCompress.isEmpty else { return }

        isCompressing = true
        // 请求要用的东西先取成局部量：后台任务跑的时候这些属性可能已经被改了
        let previous = contextSummary.isEmpty ? nil : contextSummary
        let personaName = PersonaStore.persona(for: personaId).name
        let baseURL = customProviderStore?.provider(for: customProviderId ?? "")?.baseURL
        let currentProvider = provider
        let currentKey = apiKey
        let currentModel = model
        let name = myName

        Task { [weak self] in
            let summary = try? await ClaudeService.compressHistory(
                messages: toCompress, previousSummary: previous,
                userName: name, personaName: personaName,
                provider: currentProvider, apiKey: currentKey, model: currentModel,
                baseURLOverride: baseURL)

            await MainActor.run {
                guard let self else { return }
                self.isCompressing = false
                guard let summary, !summary.isEmpty else { return }
                // 压缩这会儿用户可能又聊了几句、甚至清空了记录。
                // 只有这批消息还都在，这份摘要才对得上号
                let ids = Set(toCompress.map(\.id))
                guard ids.isSubset(of: Set(self.messages.map(\.id))) else { return }
                self.contextSummary = summary
                self.compressedIDs.formUnion(ids)
                self.saveCompressionState()
            }
        }
    }

    /// 这次「再来一版」什么都没生成出来（报错、或者刚点就取消）：
    /// 把刚才收起来的那版放回去。不放的话这一组全是隐藏状态，
    /// 界面上整条消息会凭空消失
    private func restorePendingRegenerationIfNeeded() {
        guard let groupId = pendingRegenerationGroup else { return }
        pendingRegenerationGroup = nil
        guard let latest = messages.filter({ $0.groupId == groupId })
            .map(\.versionIndex).max() else { return }
        selectVersion(groupId: groupId, version: latest)
    }

    /// 取出这次要归的组，同时算好新版本号（当前组里最大的 +1）。
    /// 取一次就清掉，避免下一条普通回复被误归进去
    private func takePendingRegenerationGroup() -> (groupId: UUID, version: Int)? {
        guard let groupId = pendingRegenerationGroup else { return nil }
        pendingRegenerationGroup = nil
        let next = (messages.filter { $0.groupId == groupId }.map(\.versionIndex).max() ?? -1) + 1
        return (groupId, next)
    }

    /// 收到一段流式增量。完整的那份立刻记下，界面那份隔几十毫秒才刷一次
    private func pushStreamingText(_ text: String) {
        latestStreamText = text
        let now = Date()
        guard now.timeIntervalSince(lastStreamPush) >= 0.05 else { return }
        lastStreamPush = now
        streamingText = text
    }

    private func resetStreamingText() {
        streamingText = ""
        latestStreamText = ""
        lastStreamPush = .distantPast
    }

    /// 中断（取消或出错）时，把已经流出来的半句话落成一条消息。
    /// 这半句用户是看着它一个字一个字出来的，直接抹掉比留着更奇怪
    private func keepPartialStreamIfAny() {
        let partial = latestStreamText
        resetStreamingText()
        // 用跟界面同一套规则挑正文：半截的选项标签不能存进消息里
        let body = ClaudeService.visibleStreamingText(partial)
        guard !body.isEmpty else { return }
        let regenerated = takePendingRegenerationGroup()
        append(ChatMessage(role: .keke, text: body,
                           model: model, providerId: currentProviderId,
                           groupId: regenerated?.groupId, version: regenerated?.version))
    }

    private var learningLanguageBlock: String? {
        guard !learningLanguage.isEmpty else { return nil }
        let name = PersonaStore.persona(for: personaId).name
        return "\(myName) 想顺便学\(learningLanguage)。在保持\(name)性格的前提下，适当地在对话里自然地" +
            "教TA一些\(learningLanguage)词汇或短句，可以中\(learningLanguage)对照，不用每句话都教，看情况穿插，" +
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
        let lastCount = UserDefaults.standard.integer(forKey: "\(personaId)_memory_extracted_at_count")
        guard messages.count - lastCount >= 10 else { return }
        UserDefaults.standard.set(messages.count, forKey: "\(personaId)_memory_extracted_at_count")
        Task { _ = await extractMemoriesNow(markCounter: false) }
    }

    /// 立即整理最近聊天成记忆，返回新记住的条数（记忆页的按钮也用它）
    func extractMemoriesNow(markCounter: Bool = true) async -> Int {
        guard let memory else { return 0 }
        if markCounter {
            UserDefaults.standard.set(messages.count, forKey: "\(personaId)_memory_extracted_at_count")
        }
        var recent = Array(messages.suffix(40))
        if let activities = activityLog?.recentForMemory(), !activities.isEmpty {
            let activityText = "【App 内活动】" + activities.joined(separator: "；")
            recent.append(ChatMessage(role: .user, text: activityText))
        }

        // 有状态面板的话走合并版：记忆 + 状态数值 + 漂流思绪蹭同一次调用
        if let kekeState {
            let thoughtContext = [kekeState.thoughtPoolSummary,
                                  kekeState.fatigueState != .awake ? "当前疲劳状态：\(kekeState.fatigueLabel)" : ""]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            let pName = PersonaStore.persona(for: personaId).name
            guard let result = try? await ClaudeService.extractMemoriesAndState(
                recent: recent, existing: memory.allTexts, userName: myName,
                personaName: pName,
                currentState: kekeState.promptLine,
                dimDescriptionBlock: kekeState.dimDescriptionBlock(userName: myName),
                dimJsonExample: kekeState.dimJsonExample(),
                thoughtPoolContext: thoughtContext.isEmpty ? nil : thoughtContext,
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
            recent: recent, existing: memory.allTexts, userName: myName,
            personaName: PersonaStore.persona(for: personaId).name,
            provider: provider, apiKey: apiKey,
            model: model, systemPrompt: effectiveSystemPrompt
        ), !new.isEmpty else { return 0 }
        for entry in new {
            memory.add(entry.text, importance: entry.importance, valence: entry.valence,
                       arousal: entry.arousal, status: entry.open ? .open : .none)
        }
        return new.count
    }

    /// 挂断电话后留一条通话记录：正文是"打了多久"，完整字幕存在 thinking 字段里折叠显示
    func appendCallRecord(text: String, transcript: String?) {
        // 同样是 systemNote。通话内容靠 maybeExtractCallMemories 进记忆，
        // 不需要把"📞 刚刚打了 X 电话"这行界面文案塞进每一轮上下文——
        // 塞了模型就会开始编造它根本没打过的电话
        append(ChatMessage(role: .keke, text: text, thinking: transcript, kind: .systemNote))
    }

    /// 克克主动冒泡的话（来自通知），直接写进聊天记录
    func receiveNudge(_ text: String, date: Date = Date()) {
        append(ChatMessage(role: .keke, text: text, date: date))
    }

    /// 未接来电 → 克克留的语音留言文字
    func receiveVoicemail(_ text: String) {
        let name = PersonaStore.persona(for: personaId).name
        append(ChatMessage(role: .keke, text: "📞 你没接到\(name)的电话，TA留了条语音：\n\(text)"))
    }

    /// 语音留言合成完后附上音频文件名（追加到最后一条消息的 thinking 字段里做记录）
    func attachVoicemailAudio(_ fileName: String) {
        guard !messages.isEmpty else { return }
        let last = messages.count - 1
        let existing = messages[last].thinking ?? ""
        messages[last].thinking = existing.isEmpty ? "🎵 \(fileName)" : existing + "\n🎵 \(fileName)"
        rewriteAll()
    }

    /// 打开 App 时克克先开口：距离上次聊天超过 3 小时、
    /// 且距离上次它主动开口超过 6 小时，才说一句（带记忆和本机状态）
    func kekeSpeaksFirstIfNeeded() async {
        guard speakFirstEnabled, !isThinking, !apiKey.isEmpty else { return }
        guard let last = messages.last else { return }
        guard last.date < Date().addingTimeInterval(-3 * 3600) else { return }
        let lastSpokeAt = UserDefaults.standard.double(forKey: "\(personaId)_speak_first_at")
        guard Date().timeIntervalSince1970 - lastSpokeAt > 6 * 3600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "\(personaId)_speak_first_at")

        var contextParts: [String] = []
        if let memoryBlock = memory?.contextBlock(for: nil, userName: myName) {
            contextParts.append(memoryBlock)
        }
        if let deviceBlock = await device?.contextBlock(userName: myName) {
            contextParts.append(deviceBlock)
        }
        let context = contextParts.isEmpty ? nil : contextParts.joined(separator: "\n\n")

        guard let lines = try? await ClaudeService.generateNudges(
            messages: messages, userName: myName,
            personaName: PersonaStore.persona(for: personaId).name,
            provider: provider, apiKey: apiKey, model: model,
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

    // MARK: - 重新生成 / 编辑重发

    /// 能不能重新生成这条。
    ///
    /// 只允许最后一条 AI 回复重来——重新生成会让它后面的对话全部作废，
    /// 对着三天前的回复重来一次，后面几十条就都得跟着删，这不是用户想要的
    func canRegenerate(_ message: ChatMessage) -> Bool {
        guard message.role == .keke, !isThinking else { return false }
        return visibleMessages.last?.id == message.id
    }

    /// 同一组的所有版本，按版本号排。没分过组就只有它自己
    func versions(of message: ChatMessage) -> [ChatMessage] {
        guard let groupId = message.groupId else { return [message] }
        return messages.filter { $0.groupId == groupId }
            .sorted { $0.versionIndex < $1.versionIndex }
    }

    /// 换一版回复。老的那版不删，只是不显示了，随时能切回来
    func regenerate(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }),
              canRegenerate(messages[index]) else { return }

        // 还没分组的话，现在给它建一组，它自己是第 0 版
        let groupId = messages[index].groupId ?? UUID()
        if messages[index].groupId == nil {
            messages[index].groupId = groupId
            messages[index].version = 0
        }
        // 这一组先全部收起来；新回复回来时会是唯一显示的那版
        for i in messages.indices where messages[i].groupId == groupId {
            messages[i].isActive = false
        }
        pendingRegenerationGroup = groupId
        rewriteAll()

        currentTask = Task { await requestReply() }
    }

    /// 切到这一组的第几版
    func selectVersion(groupId: UUID, version: Int) {
        var changed = false
        for i in messages.indices where messages[i].groupId == groupId {
            let shouldShow = messages[i].versionIndex == version
            if messages[i].isVisibleVersion != shouldShow {
                messages[i].isActive = shouldShow
                changed = true
            }
        }
        guard changed else { return }
        rewriteAll()
    }

    /// 改掉自己发过的一句话，重新发一遍。
    /// 这条之后的消息会被**真的删掉**——它们回答的是改之前那个问题，留着只会前言不搭后语
    func editAndResend(_ id: UUID, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking,
              let index = messages.firstIndex(where: { $0.id == id }),
              messages[index].role == .user else { return }

        messages[index].text = trimmed
        // 连同被压缩摘要覆盖过的记录一起清干净，免得留下指向已删消息的 id
        let removed = Set(messages[(index + 1)...].map(\.id))
        messages.removeSubrange((index + 1)...)
        compressedIDs.subtract(removed)
        rewriteAll()
        saveCompressionState()

        lastRhythmSnapshot = typingRhythm?.messageSent()
        currentTask = Task { await requestReply() }
    }

    func clearAll() {
        messages = [ChatMessage(role: .keke, text: "在。*挥爪*")]
        rewriteAll()
        // 摘要要一起清掉，不然会留下一段没有对应原文的"记忆"
        clearCompressionState()
    }

    /// 聊天记录改用「一行一条」的 jsonl 存：新消息只往文件末尾追加一行（O(1)），
    /// 不用每发一句就把整份记录重写一遍——聊到几万条也不会卡。
    /// 只有删除/收藏/清空这种结构性改动才整份重写（很少发生）
    private var jsonlURL: URL {
        docsDir.appendingPathComponent("\(personaId)_chat.jsonl")
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
