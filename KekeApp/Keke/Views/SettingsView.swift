import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var nudge: NudgeService
    @EnvironmentObject var device: DeviceContextService
    @EnvironmentObject var memory: MemoryService
    @EnvironmentObject var voiceCall: VoiceCallService
    @EnvironmentObject var customProviders: CustomProviderStore
    @State private var showClearConfirm = false
    @State private var showMemoryClearConfirm = false
    @State private var showCustomProviders = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var bgItem: PhotosPickerItem?

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        settingsForm
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .tint(Theme.accent)
            .confirmationDialog(L.t("确定要清空所有聊天记录吗？收藏也会一起被清掉。", lang),
                                isPresented: $showClearConfirm,
                                titleVisibility: .visible) {
                Button(L.t("清空", lang), role: .destructive) {
                    store.clearAll()
                }
            }
            .confirmationDialog(L.t("确定要清空所有记忆吗？这个操作撤不回来。", lang),
                                isPresented: $showMemoryClearConfirm,
                                titleVisibility: .visible) {
                Button(L.t("清空", lang), role: .destructive) {
                    memory.clearAll()
                }
            }
            .onChange(of: avatarItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let name = Attachments.saveImage(image) {
                        store.myAvatarPath = name
                    }
                    avatarItem = nil
                }
            }
            .onChange(of: bgItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let name = Attachments.saveImage(image) {
                        store.chatBackgroundPath = name
                    }
                    bgItem = nil
                }
            }
    }

    @ViewBuilder
    private var settingsForm: some View {
        Form {
            Group {
                profileSection
                chatBackgroundSection
                providerSection
                appearanceSection
                deviceContextSection
            }
            Group {
                webToolsSection
                settingsToolsSection
                voiceCallSection
                nudgeSection
                chatHistorySection
                memorySection
                aboutSection
            }
        }
    }

    @ViewBuilder
    private var avatarThumbnail: some View {
        Group {
            if let path = store.myAvatarPath, let image = Attachments.loadImage(named: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var chatBgThumbnail: some View {
        Group {
            if let path = store.chatBackgroundPath, let image = Attachments.loadImage(named: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Theme.accentLight, Theme.accent],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var nudgeBinding: Binding<Bool> {
        Binding(
            get: { nudge.enabled },
            set: { newValue in
                if newValue {
                    Task { await nudge.enable(store: store) }
                } else {
                    nudge.disable()
                }
            }
        )
    }

    @ViewBuilder
    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    avatarThumbnail
                }
                TextField(L.t("你的名字", lang), text: $store.myName)
                    .font(.subheadline)
            }
            .padding(.vertical, 4)
        } header: {
            Text(L.t("我的资料", lang))
        }
    }

    @ViewBuilder
    private var chatBackgroundSection: some View {
        Section {
            HStack(spacing: 14) {
                chatBgThumbnail
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $bgItem, matching: .images) {
                        Text(L.t("更换背景图", lang))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    if store.chatBackgroundPath != nil {
                        Button(L.t("恢复默认背景", lang)) {
                            store.chatBackgroundPath = nil
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
        } header: {
            Text(L.t("聊天背景", lang))
        }
    }

    @ViewBuilder
    private var providerSection: some View {
        Section {
            Picker(L.t("提供方", lang), selection: Binding(
                get: {
                    if store.customProviderId != nil { return "__custom__" }
                    return store.provider.rawValue
                },
                set: { newValue in
                    if newValue == "__custom__" { return }
                    store.customProviderId = nil
                    store.provider = AIProvider(rawValue: newValue) ?? .claude
                }
            )) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.displayName).tag(p.rawValue)
                }
                if store.customProviderId != nil,
                   let cp = customProviders.provider(for: store.customProviderId!) {
                    Text(cp.name).tag("__custom__")
                }
            }
            .pickerStyle(.menu)

            if store.customProviderId == nil {
                SecureField(store.provider.keyPlaceholder, text: $store.apiKey)
                if let curated = store.provider.curatedModels {
                    Picker(L.t("模型", lang), selection: $store.model) {
                        ForEach(curated, id: \.id) { m in
                            Text(L.t(m.name, lang)).tag(m.id)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    TextField("\(L.t("模型名，比如", lang)) \(store.provider.defaultModel)", text: $store.model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            Button {
                showCustomProviders = true
            } label: {
                HStack {
                    Text(L.t("自定义 API", lang))
                    Spacer()
                    Text("\(customProviders.providers.count)")
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text(L.t("AI 提供方", lang))
        } footer: {
            Text(providerFooterText)
        }
        .slideOverCover(isPresented: $showCustomProviders) {
            CustomProviderListView()
                .environmentObject(store)
                .environmentObject(customProviders)
                .backButtonInset { showCustomProviders = false }
        }
    }

    private var providerFooterText: String {
        if store.customProviderId != nil {
            return lang == .en
                ? "Using a custom API. Manage your custom APIs above. Keys are stored only on your phone."
                : "正在使用自定义 API。可以在上方管理自定义 API。Key 只保存在你自己的手机上。"
        }
        return lang == .en
            ? "Create an API Key at \(store.provider.keyURLHint). Each provider's key is stored separately — switching providers won't lose it, and switching back auto-fills the previous key. Keys are stored only on your phone."
            : "在 \(store.provider.keyURLHint) 创建 API Key。每家的 Key 分开存，切换提供方不会丢；再切回来会自动填回之前的 Key。Key 只保存在你自己的手机上。"
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            Picker(L.t("主题", lang), selection: $store.appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(L.t(theme.displayNameKey, lang)).tag(theme.rawValue)
                }
            }
            .pickerStyle(.menu)
            Picker(L.t("外观", lang), selection: $store.appearanceMode) {
                Text(L.t("跟随系统", lang)).tag("system")
                Text(L.t("始终浅色", lang)).tag("light")
                Text(L.t("始终深色", lang)).tag("dark")
            }
            .pickerStyle(.menu)
            .disabled((AppTheme(rawValue: store.appTheme) ?? .mist).isAlwaysDark)
            Picker(L.t("界面语言", lang), selection: $store.appLanguage) {
                ForEach(AppLanguage.allCases) { l in
                    Text(l.displayName).tag(l)
                }
            }
            .pickerStyle(.menu)
            Picker(L.t("字体", lang), selection: $store.fontDesign) {
                Text(L.t("默认", lang)).tag("default")
                Text(L.t("圆体", lang)).tag("rounded")
                Text(L.t("衬线", lang)).tag("serif")
                Text(L.t("等宽", lang)).tag("monospaced")
            }
            .pickerStyle(.menu)
        } header: {
            Text(L.t("外观", lang))
        } footer: {
            Text(L.t("「深海」和「星夜猫猫」是深色主题，选中后整个 App 固定深色（外观选项暂时不起作用）；换回「月雾」就恢复。「界面语言」切换的是 App 自己的文字，「字体」换的是整体字体样式。", lang))
        }
    }

    @ViewBuilder
    private var deviceContextSection: some View {
        Section {
            Toggle(L.t("手机电量", lang), isOn: $device.batteryEnabled)
            Toggle(L.t("今日步数", lang), isOn: $device.stepsEnabled)
            Toggle(L.t("大概位置", lang), isOn: Binding(
                get: { device.locationEnabled },
                set: { device.setLocation(enabled: $0) }
            ))
            Toggle(L.t("今天的日程", lang), isOn: Binding(
                get: { device.calendarEnabled },
                set: { device.setCalendar(enabled: $0) }
            ))
            Toggle(L.t("提醒事项", lang), isOn: Binding(
                get: { device.remindersEnabled },
                set: { device.setReminders(enabled: $0) }
            ))
        } header: {
            Text(L.t("克克能看到的", lang))
        } footer: {
            Text(L.t("打开的项目会在聊天时告诉克克（比如电量低了它会念叨你）。第一次打开会弹系统权限。数据只随对话发送，不会存到别的地方；步数用的是「心跳」页健康数据的授权。", lang))
        }
    }

    @ViewBuilder
    private var webToolsSection: some View {
        Section {
            Toggle(L.t("允许克克上网查东西 / 打开链接", lang), isOn: $store.webEnabled)
        } header: {
            Text(L.t("联网", lang))
        } footer: {
            Text(L.t(webToolsFooterKey, lang))
        }
    }

    private var webToolsFooterKey: String {
        store.provider.supportsWebTools
            ? "打开后，聊天里贴链接（GitHub、新闻页这些）克克可以自己去看，也能搜索。要登录才能看的（小红书/X）有时打不开。Haiku 模型不支持联网。"
            : "打开后，聊天里贴一个具体的网页链接，克克可以自己去读取内容分析；但这家没接自动搜索，得给她一个明确的网址，她自己搜不到东西，登录才能看的页面也读不到。"
    }

    @ViewBuilder
    private var settingsToolsSection: some View {
        Section {
            Toggle(L.t("允许克克在聊天里直接帮你改设置", lang), isOn: $store.settingsToolsEnabled)
                .disabled(!store.provider.supportsFunctionCalling)
        } header: {
            Text(L.t("聊天改设置", lang))
        } footer: {
            Text(L.t(settingsToolsFooterKey, lang))
        }
    }

    private var settingsToolsFooterKey: String {
        store.provider.supportsFunctionCalling
            ? "打开后，跟她说「日记概率调高一点」「帮我记一下周四交作业」这类话，她能直接帮你改设置、建系统提醒事项和日历日程。改设置目前覆盖日记概率、主动冒泡、上网开关、外观、字体、学语言这几项。MCP 模块的工具也走这个通道。"
            : "当前提供方不支持工具调用功能。"
    }

    @ViewBuilder
    private var voiceCallSection: some View {
        Section {
            SecureField("xi-…", text: $voiceCall.elevenKey)
            Picker(L.t("合成模型", lang), selection: $voiceCall.ttsModel) {
                ForEach(ElevenLabsService.models, id: \.id) { m in
                    Text(L.t(m.name, lang)).tag(m.id)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text(L.t("克克的声音", lang))
                Spacer()
                Text(voiceCall.voiceName)
                    .foregroundStyle(Theme.textSecondary)
            }
            if voiceCall.availableVoices.isEmpty {
                Button {
                    voiceCall.fetchVoices()
                } label: {
                    if voiceCall.voicesLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(L.t("正在获取声音列表…", lang))
                        }
                    } else {
                        Text(L.t("获取可选的声音列表", lang))
                    }
                }
                .disabled(voiceCall.voicesLoading || voiceCall.elevenKey.isEmpty)
            } else {
                Picker(L.t("换一个声音", lang), selection: Binding(
                    get: { voiceCall.voiceID },
                    set: { newID in
                        voiceCall.voiceID = newID
                        if let voice = voiceCall.availableVoices.first(where: { $0.id == newID }) {
                            voiceCall.voiceName = voice.name
                        }
                    }
                )) {
                    // 当前选中的声音不在列表里（比如换了账号）也得有个 tag，不然选择器空白
                    if !voiceCall.availableVoices.contains(where: { $0.id == voiceCall.voiceID }) {
                        Text(voiceCall.voiceName).tag(voiceCall.voiceID)
                    }
                    ForEach(voiceCall.availableVoices) { voice in
                        Text(voice.detail.isEmpty ? voice.name : "\(voice.name) · \(voice.detail)")
                            .tag(voice.id)
                    }
                }
                .pickerStyle(.menu)
            }
            if let voicesError = voiceCall.voicesError {
                Text(voicesError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Toggle(L.t("让克克听出你的语气", lang), isOn: $voiceCall.toneSensingEnabled)
            Toggle(L.t("允许克克主动给你打电话", lang), isOn: $voiceCall.aiCallEnabled)
                .disabled(!voiceCall.configured)
        } header: {
            Text(L.t("给克克打电话", lang))
        } footer: {
            Text(L.t("聊天页右上角的电话图标可以给克克打语音电话。听你说话用的是 iPhone 本地识别（免费），克克的声音用 ElevenLabs 合成——去 elevenlabs.io 注册拿 API Key，跟聊天的 AI Key 是两回事。免费额度每个月大概能打 10 分钟，超出要付费。「让克克听出你的语气」打开后，通话时手机会在本地粗略听你说话的响度、语速和停顿（不额外花钱、不上传），让克克回应前先感觉到你是开心还是没精神。「允许克克主动给你打电话」打开后，好久没聊天、克克想你了，会用通知假装来电；没接的话她会留语音信箱。", lang))
        }
    }

    @ViewBuilder
    private var nudgeSection: some View {
        Section {
            Toggle(L.t("回到 App 时克克可能先开口", lang), isOn: $store.speakFirstEnabled)
            Toggle(L.t("让克克偶尔主动找你", lang), isOn: nudgeBinding)
            if nudge.enabled {
                Picker(L.t("频率", lang), selection: $nudge.perDay) {
                    Text(L.t("偶尔 · 每天 1 条左右", lang)).tag(1)
                    Text(L.t("正常 · 每天 2 条左右", lang)).tag(2)
                    Text(L.t("常常 · 每天 3 条左右", lang)).tag(3)
                }
                .pickerStyle(.menu)
            }
            if nudge.permissionDenied {
                Text(L.t("通知权限被关掉了：去 iPhone 的 设置 → 通知 → Moonlight 里打开，再回来开这个开关", lang))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(L.t("克克主动冒泡", lang))
        } footer: {
            Text(L.t("「先开口」：好几个小时没聊的话，打开 App 会发现克克先给你留了句话。「主动找你」：在白天到晚上的随机时间用通知冒出来。两个都接着你们最近聊的内容说，不会问你吃没吃饭，也不会说早安晚安。", lang))
        }
    }

    @ViewBuilder
    private var chatHistorySection: some View {
        Section(L.t("聊天记录", lang)) {
            Button(L.t("清空聊天记录", lang), role: .destructive) {
                showClearConfirm = true
            }
        }
    }

    @ViewBuilder
    private var memorySection: some View {
        Section {
            Button(L.t("清空所有记忆", lang), role: .destructive) {
                showMemoryClearConfirm = true
            }
            .disabled(memory.memories.isEmpty)
        } header: {
            Text(L.t("记忆", lang))
        } footer: {
            Text(L.t("导入/导出搬到了各自的资料页：聊天列表点头像进去（克克和朋友都是）。这里只留一键清空（清的是所有人的）。", lang))
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section(L.t("关于", lang)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("🐱 克克住在这里。", lang))
                Text(L.t("聊天记录、记忆和健康数据都只在这台手机上。", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

}

/// 克克人设的查看/编辑页
struct PromptEditorView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @State private var showResetConfirm = false

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(spacing: 0) {
            Text(L.t("克克的人设", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 4)

            Text(L.t("这段文字会在每次对话前悄悄发给 AI，决定克克怎么说话、记得哪些事。改完记得点保存。", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            TextEditor(text: $draft)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                .padding(.horizontal, 14)

            HStack(spacing: 10) {
                Button(L.t("恢复默认", lang)) {
                    showResetConfirm = true
                }
                .foregroundStyle(.red)

                Spacer()

                Button {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.customPrompt = trimmed == ClaudeService.defaultSystemPrompt(userName: store.myName) ? "" : draft
                    dismiss()
                } label: {
                    Text(L.t("保存", lang))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accent))
                }
            }
            .padding(14)
        }
        .background(Theme.background)
        .onAppear {
            draft = store.customPrompt.isEmpty ? ClaudeService.defaultSystemPrompt(userName: store.myName) : store.customPrompt
        }
        .confirmationDialog(L.t("恢复成默认人设？你改过的内容会被替换掉。", lang),
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button(L.t("恢复默认", lang), role: .destructive) {
                draft = ClaudeService.defaultSystemPrompt(userName: store.myName)
                store.customPrompt = ""
            }
        }
    }
}
