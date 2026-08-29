import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var nudge: NudgeService
    @EnvironmentObject var device: DeviceContextService
    @EnvironmentObject var memory: MemoryService
    @EnvironmentObject var voiceCall: VoiceCallService
    @EnvironmentObject var customProviders: CustomProviderStore
    @ObservedObject private var errorLog = ErrorLog.shared
    @State private var showClearConfirm = false
    @State private var showMemoryClearConfirm = false
    @State private var showProfileSheet = false
    @State private var showAPISheet = false
    @State private var showUsageSheet = false
    @State private var showBackupSheet = false
    @State private var showErrorLog = false
    @State private var showMCPServers = false

    private var lang: AppLanguage { store.appLanguage }
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }

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
            .slideOverCover(isPresented: $showProfileSheet) {
                ProfileSettingsSheet()
                    .environmentObject(store)
                    .backButtonInset { showProfileSheet = false }
            }
            .slideOverCover(isPresented: $showAPISheet) {
                APISettingsSheet()
                    .environmentObject(store)
                    .environmentObject(customProviders)
                    .environmentObject(voiceCall)
                    .backButtonInset { showAPISheet = false }
            }
            .slideOverCover(isPresented: $showUsageSheet) {
                UsageStatsView()
                    .environmentObject(store)
                    .backButtonInset { showUsageSheet = false }
            }
            .slideOverCover(isPresented: $showBackupSheet) {
                BackupView()
                    .environmentObject(store)
                    .backButtonInset { showBackupSheet = false }
            }
            .slideOverCover(isPresented: $showErrorLog) {
                ErrorLogView()
                    .environmentObject(store)
                    .backButtonInset { showErrorLog = false }
            }
            .slideOverCover(isPresented: $showMCPServers) {
                MCPServersView()
                    .environmentObject(store)
                    .backButtonInset { showMCPServers = false }
            }
    }

    @ViewBuilder
    private var settingsForm: some View {
        Form {
            Group {
                profileRow
                apiRow
                appearanceSection
                deviceContextSection
            }
            // 分成两个 Group 是因为 ViewBuilder 一次最多接 10 个子视图，
            // 上面那组已经顶到 10 了，再加一项就编译不过
            Group {
                webToolsSection
                settingsToolsSection
                mcpSection
                streamSection
                usageSection
                voiceCallSection
                nudgeSection
            }
            Group {
                chatHistorySection
                memorySection
                diagnosticsSection
                aboutSection
            }
        }
    }

    @ViewBuilder
    private var profileRow: some View {
        Section {
            Button {
                showProfileSheet = true
            } label: {
                HStack(spacing: 14) {
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
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.myName.isEmpty ? L.t("设置资料", lang) : store.myName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(L.t("头像、名字、聊天背景", lang))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(L.t("我的资料", lang))
        }
    }

    @ViewBuilder
    private var apiRow: some View {
        Section {
            Button {
                showAPISheet = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("API 设置", lang))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 4) {
                            Text(store.provider.displayName)
                            if !store.model.isEmpty {
                                Text("·")
                                Text(store.model.count > 16 ? String(store.model.prefix(14)) + "…" : store.model)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(L.t("AI 提供方", lang))
        } footer: {
            Text(L.t("Key 只保存在你自己的手机上。", lang))
        }
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
            Text(String(format: L.t("%@能看到的", lang), personaName))
        } footer: {
            Text(String(format: L.t("打开的项目会在聊天时告诉%@（比如电量低了TA会念叨你）。第一次打开会弹系统权限。数据只随对话发送，不会存到别的地方；步数用的是「心跳」页健康数据的授权。", lang), personaName))
        }
    }

    @ViewBuilder
    private var webToolsSection: some View {
        Section {
            Toggle(String(format: L.t("允许%@上网查东西 / 打开链接", lang), personaName), isOn: $store.webEnabled)
        } header: {
            Text(L.t("联网", lang))
        } footer: {
            Text(L.t(webToolsFooterKey, lang))
        }
    }

    private var webToolsFooterKey: String {
        store.provider.supportsWebTools
            ? String(format: "打开后，聊天里贴链接（GitHub、新闻页这些）%@可以自己去看，也能搜索。要登录才能看的（小红书/X）有时打不开。Haiku 模型不支持联网。", personaName)
            : String(format: "打开后，聊天里贴一个具体的网页链接，%@可以自己去读取内容分析；但这家没接自动搜索，得给TA一个明确的网址，TA自己搜不到东西，登录才能看的页面也读不到。", personaName)
    }

    @ViewBuilder
    private var settingsToolsSection: some View {
        Section {
            Toggle(String(format: L.t("允许%@在聊天里直接帮你改设置", lang), personaName), isOn: $store.settingsToolsEnabled)
                .disabled(!store.provider.supportsFunctionCalling)
        } header: {
            Text(L.t("聊天改设置", lang))
        } footer: {
            Text(L.t(settingsToolsFooterKey, lang))
        }
    }

    @ViewBuilder
    private var streamSection: some View {
        Section {
            Toggle(String(format: L.t("边想边说（%@的话一个字一个字出现）", lang), personaName),
                   isOn: $store.streamEnabled)
        } header: {
            Text(L.t("回复方式", lang))
        } footer: {
            Text(String(format: L.t("打开后不用干等，%@想到哪儿说到哪儿，中途还能按停止把已经说的留下来。极个别自建中转站不支持这种方式，要是打开后聊天报错或者一直没反应，关掉就好。", lang), personaName))
        }
    }

    /// 用户自己加的 MCP 服务器。内置那 7 个模块是写死的，这里能挂第三方的
    @ViewBuilder
    private var mcpSection: some View {
        Section {
            Button {
                showMCPServers = true
            } label: {
                HStack {
                    Text(L.t("MCP 服务器", lang))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    let connected = MCPServerRegistry.shared.servers.filter {
                        MCPServerRegistry.shared.status[$0.id]?.isConnected == true
                    }.count
                    if connected > 0 {
                        Text("\(connected)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } footer: {
            Text(L.t("接第三方 MCP 服务器，给 TA 加内置模块之外的新工具。填个地址就能用，工具可以逐个开关。", lang))
        }
    }

    /// 全 App 的报错入口。平时不打扰，出问题时能一口气看完、复制走。
    /// 有记录时把条数亮出来——不然用户不知道有东西可看
    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {
            Button {
                showErrorLog = true
            } label: {
                HStack {
                    Text(L.t("报错记录", lang))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if !errorLog.entries.isEmpty {
                        Text("\(errorLog.entries.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } footer: {
            Text(L.t("聊天报错、以及那些在后台悄悄失败的生成（写日记、发朋友圈、提炼记忆…）都会记到这里。可以整份复制出来，也可以长按删掉单条。", lang))
        }
    }

    @ViewBuilder
    private var usageSection: some View {
        Section {
            Toggle(L.t("在每条回复下显示用量", lang), isOn: $store.showUsage)
            Button {
                showUsageSheet = true
            } label: {
                HStack {
                    Text(L.t("用量统计", lang))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text(L.t("Token 用量", lang))
        } footer: {
            Text(L.t("显示的是模型、这次用掉的 token 和耗时。统计页里能看到缓存命中比例——那是判断 prompt caching 有没有生效的直接证据。", lang))
        }
    }

    private var settingsToolsFooterKey: String {
        store.provider.supportsFunctionCalling
            ? String(format: "打开后，跟TA说「日记概率调高一点」「帮我记一下周四交作业」这类话，%@能直接帮你改设置、建系统提醒事项和日历日程。改设置目前覆盖日记概率、主动冒泡、上网开关、外观、字体、学语言这几项。MCP 模块的工具也走这个通道。", personaName)
            : "当前提供方不支持工具调用功能。"
    }

    @ViewBuilder
    private var voiceCallSection: some View {
        Section {
            Group {
                HStack {
                    Text(String(format: L.t("%@的声音", lang), personaName))
                    Spacer()
                    Text(voiceCall.voiceName)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Group {
                Toggle(String(format: L.t("让%@听出你的语气", lang), personaName), isOn: $voiceCall.toneSensingEnabled)
                Toggle(String(format: L.t("允许%@主动给你打电话", lang), personaName), isOn: $voiceCall.aiCallEnabled)
                    .disabled(!voiceCall.configured)
            }
        } header: {
            Text(String(format: L.t("给%@打电话", lang), personaName))
        } footer: {
            Text(String(format: L.t("ElevenLabs 的 Key 和声音选择已移到「API 设置」里。「让%@听出你的语气」打开后，通话时手机会在本地粗略听你说话的响度、语速和停顿（不额外花钱、不上传）。「允许%@主动给你打电话」打开后，好久没聊天、%@想你了，会用通知假装来电。", lang), personaName, personaName, personaName))
        }
    }

    @ViewBuilder
    private var nudgeSection: some View {
        Section {
            Toggle(String(format: L.t("回到 App 时%@可能先开口", lang), personaName), isOn: $store.speakFirstEnabled)
            Toggle(String(format: L.t("让%@偶尔主动找你", lang), personaName), isOn: nudgeBinding)
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
            Text(String(format: L.t("%@主动冒泡", lang), personaName))
        } footer: {
            Text(String(format: L.t("「先开口」：好几个小时没聊的话，打开 App 会发现%@先给你留了句话。「主动找你」：在白天到晚上的随机时间用通知冒出来。两个都接着你们最近聊的内容说，不会问你吃没吃饭，也不会说早安晚安。", lang), personaName))
        }
    }

    @ViewBuilder
    private var chatHistorySection: some View {
        Section {
            Button {
                showBackupSheet = true
            } label: {
                HStack {
                    Text(L.t("备份导出", lang))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Button(L.t("清空聊天记录", lang), role: .destructive) {
                showClearConfirm = true
            }
        } header: {
            Text(L.t("聊天记录", lang))
        } footer: {
            Text(L.t("备份会把聊天记录、记忆、朋友圈、日记这些一起打包成一个文件，可以存到「文件」App 或者发给自己。不含 API Key。", lang))
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
            Text(L.t("导入/导出搬到了各自的资料页：聊天列表点头像进去。这里只留一键清空（清的是所有人的）。", lang))
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section(L.t("关于", lang)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: L.t("%@ 住在这里。", lang), PersonaStore.persona(for: store.personaId).icon + " " + personaName))
                Text(L.t("聊天记录、记忆和健康数据都只在这台手机上。", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

}

// MARK: - Profile Settings Sheet

struct ProfileSettingsSheet: View {
    @EnvironmentObject var store: ChatStore
    @State private var avatarItem: PhotosPickerItem?
    @State private var bgItem: PhotosPickerItem?

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(spacing: 0) {
            Text(L.t("我的资料", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            VStack(spacing: 6) {
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
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())

                                Text(L.t("更换头像", lang))
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassCard(cornerRadius: 14)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("你的名字", lang))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        TextField(L.t("你的名字", lang), text: $store.myName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(10)
                            .glassCard(cornerRadius: 10)
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t("聊天背景", lang))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)

                        HStack(spacing: 14) {
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
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 14)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
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
}

// MARK: - API Settings Sheet

struct APISettingsSheet: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var customProviders: CustomProviderStore
    @EnvironmentObject var voiceCall: VoiceCallService
    @State private var showCustomProviders = false

    private var lang: AppLanguage { store.appLanguage }

    private var providerPickerBinding: Binding<String> {
        Binding(
            get: {
                if store.customProviderId != nil { return "__custom__" }
                return store.provider.rawValue
            },
            set: { newValue in
                if newValue == "__custom__" { return }
                store.customProviderId = nil
                store.provider = AIProvider(rawValue: newValue) ?? .claude
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L.t("API 设置", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 4)
            Text(L.t("Key 只保存在你自己的手机上", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t("AI 提供方", lang))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)

                        Picker(L.t("提供方", lang), selection: providerPickerBinding) {
                            ForEach(AIProvider.allCases) { p in
                                Text(p.displayName).tag(p.rawValue)
                            }
                            if store.customProviderId != nil,
                               let cp = customProviders.provider(for: store.customProviderId!) {
                                Text(cp.name).tag("__custom__")
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(10)
                        .glassCard(cornerRadius: 10)

                        if store.customProviderId == nil {
                            SecureField(store.provider.keyPlaceholder, text: $store.apiKey)
                                .font(.subheadline)
                                .padding(10)
                                .glassCard(cornerRadius: 10)

                            if let curated = store.provider.curatedModels {
                                Picker(L.t("模型", lang), selection: $store.model) {
                                    ForEach(curated, id: \.id) { m in
                                        Text(L.t(m.name, lang)).tag(m.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding(10)
                                .glassCard(cornerRadius: 10)
                            } else {
                                TextField("\(L.t("模型名，比如", lang)) \(store.provider.defaultModel)", text: $store.model)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .font(.subheadline)
                                    .padding(10)
                                    .glassCard(cornerRadius: 10)
                            }
                        }

                        Text(providerFooterText)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 14)

                    Button {
                        showCustomProviders = true
                    } label: {
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundStyle(Theme.accent)
                            Text(L.t("自定义 API", lang))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(customProviders.providers.count)")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(14)
                        .glassCard(cornerRadius: 14)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t("ElevenLabs（语音通话）", lang))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)

                        SecureField("xi-…", text: $voiceCall.elevenKey)
                            .font(.subheadline)
                            .padding(10)
                            .glassCard(cornerRadius: 10)

                        Picker(L.t("合成模型", lang), selection: $voiceCall.ttsModel) {
                            ForEach(ElevenLabsService.models, id: \.id) { m in
                                Text(L.t(m.name, lang)).tag(m.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(10)
                        .glassCard(cornerRadius: 10)

                        voicePickerOrFetch

                        if let voicesError = voiceCall.voicesError {
                            Text(voicesError)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Text(L.t("去 elevenlabs.io 注册拿 Key，跟聊天的 AI Key 是两回事。免费额度每月大概能打 10 分钟。", lang))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 14)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
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
                ? "Using a custom API. Manage your custom APIs above."
                : "正在使用自定义 API。可以在上方管理自定义 API。"
        }
        return lang == .en
            ? "Create an API Key at \(store.provider.keyURLHint). Each provider's key is stored separately — switching providers won't lose it."
            : "在 \(store.provider.keyURLHint) 创建 API Key。每家的 Key 分开存，切换提供方不会丢。"
    }

    @ViewBuilder
    private var voicePickerOrFetch: some View {
        if voiceCall.availableVoices.isEmpty {
            Button {
                voiceCall.fetchVoices()
            } label: {
                HStack(spacing: 8) {
                    if voiceCall.voicesLoading {
                        ProgressView()
                        Text(L.t("正在获取声音列表…", lang))
                    } else {
                        Text(L.t("获取可选的声音列表", lang))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(10)
                .glassCard(cornerRadius: 10)
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
                if !voiceCall.availableVoices.contains(where: { $0.id == voiceCall.voiceID }) {
                    Text(voiceCall.voiceName).tag(voiceCall.voiceID)
                }
                ForEach(voiceCall.availableVoices) { voice in
                    Text(voice.detail.isEmpty ? voice.name : "\(voice.name) · \(voice.detail)")
                        .tag(voice.id)
                }
            }
            .pickerStyle(.menu)
            .padding(10)
            .glassCard(cornerRadius: 10)
        }
    }
}

// MARK: - Prompt Editor

struct PromptEditorView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @State private var showResetConfirm = false
    @State private var generating = false

    private var lang: AppLanguage { store.appLanguage }
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }

    /// temperature / top_p 滑杆。只有还认这两个参数的模型才显示
    @ViewBuilder
    private var samplingSliders: some View {
        HStack {
            Text("Temperature")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if store.temperature < 0 {
                Text(L.t("默认", lang))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(String(format: "%.2f", store.temperature))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        HStack(spacing: 8) {
            Slider(value: Binding(
                get: { store.temperature < 0 ? 1.0 : store.temperature },
                set: { store.temperature = $0 }
            ), in: 0...2, step: 0.05)
            .tint(Theme.accent)
            Button {
                store.temperature = -1
            } label: {
                Text(L.t("重置", lang))
                    .font(.caption2)
                    .foregroundStyle(store.temperature < 0 ? Theme.textSecondary.opacity(0.4) : Theme.accent)
            }
            .disabled(store.temperature < 0)
        }

        HStack {
            Text("Top P")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if store.topP < 0 {
                Text(L.t("默认", lang))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(String(format: "%.2f", store.topP))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        HStack(spacing: 8) {
            Slider(value: Binding(
                get: { store.topP < 0 ? 1.0 : store.topP },
                set: { store.topP = $0 }
            ), in: 0...1, step: 0.05)
            .tint(Theme.accent)
            Button {
                store.topP = -1
            } label: {
                Text(L.t("重置", lang))
                    .font(.caption2)
                    .foregroundStyle(store.topP < 0 ? Theme.textSecondary.opacity(0.4) : Theme.accent)
            }
            .disabled(store.topP < 0)
        }

        Text(L.t("Temperature 越高回复越随机，越低越稳定。Top P 控制词汇采样范围。不调则用 API 默认值。", lang))
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 生成投入档位。新的 Claude 模型用它替代了采样参数
    @ViewBuilder
    private var effortPicker: some View {
        HStack {
            Text(L.t("动脑程度", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Picker("", selection: $store.effort) {
                ForEach(ReasoningEffort.allCases) { level in
                    Text(L.t(level.displayName, lang)).tag(level)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
        }
        Text(L.t("这个模型不再用 Temperature / Top P 那套参数了，改用「动脑程度」：越高想得越久越周全，也越贵。默认「高」就挺好，简单闲聊可以调低省钱。", lang))
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 一次回复的长度上限
    @ViewBuilder
    private var maxTokensPicker: some View {
        HStack {
            Text(L.t("单次回复长度上限", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Picker("", selection: $store.maxTokens) {
                ForEach(ChatStore.maxTokensOptions, id: \.self) { n in
                    Text("\(n / 1024)k").tag(n)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
        }
        Text(L.t("一次最多生成多少 token。调高了能写更长的东西，但如果超过模型自己的上限，请求会直接失败。写小作文调高，日常闲聊 4k 够用。", lang))
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 让模型先想再答
    @ViewBuilder
    private var thinkingToggle: some View {
        Toggle(L.t("先想再说（可以点开看TA想了什么）", lang), isOn: $store.thinkingEnabled)
            .font(.caption)
            .tint(Theme.accent)
        Text(L.t("打开后回答之前会先推理一遍，复杂问题答得更好，但更慢也更花钱。思考过程会折叠在回复上面，点一下能展开。", lang))
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(String(format: L.t("%@的人设", lang), personaName))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 4)

            Text(String(format: L.t("这段文字会在每次对话前悄悄发给 AI，决定%@怎么说话、记得哪些事。改完记得点保存。", lang), personaName))
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

            VStack(spacing: 8) {
                if store.supportsSampling {
                    samplingSliders
                } else {
                    // 这个模型移除了 temperature / top_p（传过去会 400），
                    // 换成官方的替代品：生成投入档位
                    effortPicker
                }
                maxTokensPicker
                if store.supportsThinking {
                    thinkingToggle
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)

            HStack(spacing: 10) {
                Button(L.t("清空", lang)) {
                    showResetConfirm = true
                }
                .foregroundStyle(.red)

                Button {
                    generateProfile()
                } label: {
                    HStack(spacing: 4) {
                        if generating {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                        }
                        Text(L.t("AI 整理", lang))
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().stroke(Theme.accent, lineWidth: 1))
                }
                .disabled(generating || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.apiKey.isEmpty)

                Spacer()

                Button {
                    store.customPrompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if !store.customPrompt.isEmpty {
                draft = store.customPrompt
            } else {
                let personaPrompt = PersonaStore.persona(for: store.personaId).systemPrompt
                draft = personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : personaPrompt
            }
        }
        .confirmationDialog(L.t("确定要清空人设内容吗？", lang),
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button(L.t("清空", lang), role: .destructive) {
                draft = ""
                store.customPrompt = ""
            }
        }
    }

    private func generateProfile() {
        generating = true
        Task {
            do {
                let profile = try await ClaudeService.generateProfileFromPrompt(
                    currentPrompt: draft,
                    personaName: personaName,
                    provider: store.provider,
                    apiKey: store.apiKey,
                    model: store.model
                )
                draft = profile
            } catch { }
            generating = false
        }
    }
}
