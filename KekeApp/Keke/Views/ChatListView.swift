import SwiftUI
import UniformTypeIdentifiers

/// 聊天 tab 的会话列表（微信化）：克克置顶，下面是各个好友窗口；
/// 右上角可以加新朋友（自选备注/emoji/模型/人设）。点进去从右滑入对应的聊天页。
struct ChatListView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var contacts: ContactsStore
    @EnvironmentObject var memory: MemoryService
    @EnvironmentObject var voiceCall: VoiceCallService
    @EnvironmentObject var diary: DiaryService

    /// slideOverCover 需要 Identifiable 的 item
    private struct OpenChat: Identifiable { let id: String }
    @State private var opened: OpenChat?
    @State private var editing: Contact?
    @State private var showNew = false
    @State private var showKekeProfile = false
    @State private var showCall = false
    /// 缺 Key 打不了电话时的提示文字（非 nil 就弹窗）
    @State private var callBlockedMessage: String?
    /// 好友窗口的最后一句预览缓存（避免每次渲染都读文件）
    @State private var previews: [String: String] = [:]
    @Environment(\.scenePhase) private var scenePhase

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        listBody
            .slideOverCover(item: $opened) { open in
                if let contact = contacts.contact(open.id) {
                    if contact.isKeke {
                        kekeChat(contact)
                    } else {
                        ContactChatView(contact: contact, memory: memory, userName: store.myName) {
                            withAnimation(.easeOut(duration: 0.22)) { opened = nil }
                            reloadPreviews()
                        }
                        .environmentObject(store)
                        .environmentObject(contacts)
                        .environmentObject(memory)
                    }
                }
            }
            .sheet(isPresented: $showNew) {
                ContactEditorView(contact: nil)
                    .environmentObject(store)
                    .environmentObject(contacts)
                    .environmentObject(memory)
            }
            .sheet(item: $editing) { contact in
                ContactEditorView(contact: contact)
                    .environmentObject(store)
                    .environmentObject(contacts)
                    .environmentObject(memory)
            }
            .sheet(isPresented: $showKekeProfile) {
                KekeProfileView()
                    .environmentObject(store)
                    .environmentObject(contacts)
                    .environmentObject(memory)
                    .environmentObject(diary)
            }
            .fullScreenCover(isPresented: $showCall) {
                CallView()
                    .environmentObject(store)
                    .environmentObject(voiceCall)
            }
            .onAppear { reloadPreviews() }
            // App 退到后台就挂断电话（后台没有录音权限，留着通话会假死）
            .onChange(of: scenePhase) { phase in
                if phase == .background, showCall {
                    voiceCall.hangUp()
                    showCall = false
                }
            }
            .alert(L.t("现在打不了电话", lang),
                   isPresented: Binding(get: { callBlockedMessage != nil },
                                        set: { if !$0 { callBlockedMessage = nil } })) {
                Button(L.t("好", lang), role: .cancel) {}
            } message: {
                Text(callBlockedMessage ?? "")
            }
    }

    /// 打电话前先把两样 Key 都验一遍：缺哪样直接说清楚，不进通话页。
    /// （听你说话用的是 iPhone 本地识别，免费、不用接任何 API）
    private func startCallIfReady() {
        var missing: [String] = []
        if !ContactsStore.hasKey(for: store.provider) {
            missing.append(String(format: L.t("%@ 的 Key（%@想回复要用）", lang), store.provider.displayName, PersonaStore.persona(for: store.personaId).name))
        }
        if !voiceCall.configured {
            missing.append(String(format: L.t("ElevenLabs 的 Key（合成%@的声音要用）", lang), PersonaStore.persona(for: store.personaId).name))
        }
        if missing.isEmpty {
            showCall = true
        } else {
            callBlockedMessage = String(format: L.t("还差：%@。去「设置」填好再来打～", lang),
                                        missing.joined(separator: "、"))
        }
    }

    private var listBody: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                HStack {
                    Text(L.count(contacts.contacts.count, "联系人 · %d", "Contacts · %d", lang))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button {
                        showNew = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text(L.t("加个新朋友", lang))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 4)

                ForEach(sortedContacts) { contact in
                    contactRow(contact)
                }
            }
            .padding(14)
        }
        .background(Theme.background)
    }

    /// 克克永远在最上面，其他按创建时间
    private var sortedContacts: [Contact] {
        let keke = contacts.contacts.filter(\.isKeke)
        let rest = contacts.friends.sorted { $0.createdAt < $1.createdAt }
        return keke + rest
    }

    private func contactRow(_ contact: Contact) -> some View {
        let hasKey = ContactsStore.hasKey(for: contact.isKeke ? store.provider : contact.provider)
        let preview: String = contact.isKeke
            ? (store.messages.last?.text ?? "")
            : (previews[contact.id] ?? "")

        return HStack(spacing: 12) {
            // 头像单独可点：好友点头像进编辑页（备注/模型/人设/导记忆），
            // 克克点头像进她自己的专属资料页（人设/日记概率/记忆导入导出）——两套页面完全分开
            Button {
                if contact.isKeke {
                    showKekeProfile = true
                } else {
                    editing = contact
                }
            } label: {
                Text(contact.emoji)
                    .font(.system(size: 26))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Theme.accentLight.opacity(0.35)))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.22)) { opened = OpenChat(id: contact.id) }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(contact.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            if contact.isKeke {
                                Text("🌙")
                                    .font(.caption2)
                            }
                            if !hasKey {
                                Text(L.t("还没接 Key", lang))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                            }
                        }
                        Text(preview.isEmpty ? L.t("还没聊过，点进去说句话吧", lang) : preview)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
        .opacity(hasKey ? 1 : 0.6)
        .contextMenu {
            if contact.isKeke {
                Button {
                    showKekeProfile = true
                } label: {
                    Label(String(format: L.t("%@的资料", lang), PersonaStore.persona(for: store.personaId).name), systemImage: "person.crop.circle")
                }
            } else {
                Button {
                    editing = contact
                } label: {
                    Label(L.t("编辑资料", lang), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    contacts.delete(contact.id)
                } label: {
                    Label(L.t("删除这个朋友", lang), systemImage: "trash")
                }
            }
        }
    }

    /// 克克的聊天：原来的 ChatView 原封不动，套一个带返回和电话按钮的头
    private func kekeChat(_ contact: Contact) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.22)) { opened = nil }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                // 点名字进克克的专属资料页（人设/日记概率/记忆导入导出）
                Button {
                    showKekeProfile = true
                } label: {
                    HStack(spacing: 4) {
                        Text("\(contact.emoji) \(contact.name)")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Button {
                    startCallIfReady()
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.background)

            ChatView()
                .environmentObject(store)
        }
        .background(Theme.background)
    }

    private func reloadPreviews() {
        var result: [String: String] = [:]
        for contact in contacts.friends {
            result[contact.id] = ContactChatSession.lastMessage(contactID: contact.id)?.text ?? ""
        }
        previews = result
    }
}

/// 好友（非克克）的聊天页：独立历史、独立记忆分区、用他自己绑定的模型。
/// 纯文字聊天（图片/文档/贴纸这些克克专属的功能这里没有）
struct ContactChatView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var contacts: ContactsStore
    @EnvironmentObject var memoryStore: MemoryService
    @StateObject private var session: ContactChatSession
    @StateObject private var keyboard = KeyboardObserver()
    @State private var input = ""
    @State private var showProfile = false
    @FocusState private var inputFocused: Bool
    private let onBack: () -> Void

    init(contact: Contact, memory: MemoryService, userName: String, onBack: @escaping () -> Void) {
        _session = StateObject(wrappedValue: ContactChatSession(contact: contact, memory: memory, userName: userName))
        self.onBack = onBack
    }

    private var lang: AppLanguage { store.appLanguage }
    private var hasKey: Bool { ContactsStore.hasKey(for: session.contact.provider) }

    var body: some View {
        VStack(spacing: 0) {
            header
            messagesList
            if !hasKey {
                Text(String(format: L.t("先去「设置」填上 %@ 的 API Key 才能开始聊", lang),
                            session.contact.provider.displayName))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
            }
            inputBar
        }
        .background(Theme.background)
        .padding(.bottom, max(0, keyboard.height - bottomSafeInset))
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var bottomSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first }
            .first?.safeAreaInsets.bottom ?? 0
    }

    private var header: some View {
        // 名字实时从通讯录取（资料页里改了备注马上生效）
        let live = contacts.contact(session.contact.id)
        return HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            // 点名字进资料页：改备注/换模型/改人设/导记忆
            Button {
                showProfile = true
            } label: {
                HStack(spacing: 4) {
                    Text("\(live?.emoji ?? session.contact.emoji) \(live?.name ?? session.contact.name)")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            // 左右对称占位，让名字居中
            Image(systemName: "chevron.left.circle.fill")
                .font(.system(size: 22))
                .opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.background)
        .sheet(isPresented: $showProfile) {
            ContactEditorView(contact: contacts.contact(session.contact.id) ?? session.contact)
                .environmentObject(store)
                .environmentObject(contacts)
                .environmentObject(memoryStore)
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(session.messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                    if session.isThinking {
                        HStack {
                            TypingIndicator()
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.vertical, 12)
            }
            .onTapGesture { inputFocused = false }
            .onChange(of: session.messages.count) { _ in
                if let last = session.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onAppear {
                if let last = session.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 17)
                            .fill(message.role == .user ? Theme.bubbleUser : Theme.bubbleKeke)
                    )
                Text(message.date, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            if message.role == .keke { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 14)
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label(L.t("复制", lang), systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                session.deleteMessage(message.id)
            } label: {
                Label(L.t("删除", lang), systemImage: "trash")
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(L.t("说点什么…", lang), text: $input, axis: .vertical)
                .lineLimit(1...4)
                .font(.subheadline)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
                .focused($inputFocused)
                .disabled(!hasKey)

            if session.isThinking {
                Button {
                    session.cancelSend()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.red.opacity(0.82)))
                }
            } else {
                Button {
                    session.send(input)
                    input = ""
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.accent))
                }
                .disabled(!hasKey || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(!hasKey || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.backgroundDeep)
    }
}

/// 新建/编辑联系人：备注、头像 emoji、绑定的提供方和模型、人设（可空白）
struct ContactEditorView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var contacts: ContactsStore
    @EnvironmentObject var memory: MemoryService
    @Environment(\.dismiss) private var dismiss

    let contact: Contact?     // nil = 新建

    @State private var name = ""
    @State private var emoji = "💬"
    @State private var provider: AIProvider = .deepseek
    @State private var model = ""
    @State private var persona = ""
    @State private var showDeleteConfirm = false
    @State private var showMemoryImporter = false
    @State private var importResult: String?

    private var lang: AppLanguage { store.appLanguage }

    /// 这位朋友自己分区的记忆（连归档一起），导出用
    private func memoriesText(of contactID: String) -> String {
        memory.memories.filter { $0.contact == contactID }.map(\.text).joined(separator: "\n")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(L.t("备注名", lang), text: $name)
                    TextField(L.t("头像 emoji（一个就好）", lang), text: $emoji)
                } header: {
                    Text(L.t("备注", lang))
                } footer: {
                    Text(String(format: L.t("这里编辑的是这位朋友；%@的名字、人设在TA自己的资料页里，互不影响", lang), PersonaStore.persona(for: store.personaId).name))
                }
                Section {
                    Picker(L.t("提供方", lang), selection: $provider) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    if let curated = provider.curatedModels {
                        Picker(L.t("模型", lang), selection: $model) {
                            ForEach(curated, id: \.id) { m in
                                Text(L.t(m.name, lang)).tag(m.id)
                            }
                        }
                    } else {
                        TextField("\(L.t("模型名，比如", lang)) \(provider.defaultModel)", text: $model)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text(L.t("绑定的模型", lang))
                } footer: {
                    Text(ContactsStore.hasKey(for: provider)
                         ? L.t("这家的 API Key 已经填过了，建好就能聊", lang)
                         : L.t("这家的 API Key 还没填：去「设置 → AI 提供方」切到这家填一下", lang))
                }
                Section {
                    TextEditor(text: $persona)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 120)
                } header: {
                    Text(L.t("人设（可留空）", lang))
                } footer: {
                    Text(L.t("留空 = 没有人设，只告诉 TA 自己叫什么名字，其他全靠聊出来和记忆养出来。记忆可以在「记忆」页切到 TA 的分区导入。", lang))
                }
                if let contact {
                    Section {
                        Button {
                            showMemoryImporter = true
                        } label: {
                            Label(L.t("导入记忆（md / txt / json）", lang), systemImage: "square.and.arrow.down")
                        }
                        if let importResult {
                            Text(importResult)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        ShareLink(item: memoriesText(of: contact.id)) {
                            Label(L.t("导出记忆", lang), systemImage: "square.and.arrow.up")
                        }
                        .disabled(memoriesText(of: contact.id).isEmpty)
                        NavigationLink {
                            ChatArchiveManagerView(contact: contact)
                                .environmentObject(store)
                                .environmentObject(memory)
                        } label: {
                            Label(L.t("聊天档案（完整聊天记录）", lang), systemImage: "archivebox")
                        }
                    } header: {
                        Text(L.t("记忆", lang))
                    } footer: {
                        Text(L.t("md/txt 按行导入（一行一条）；json 认 claude.ai 和 ChatGPT 的官方导出文件（自动解析对话内容），也认字符串数组。导进来的都存在 TA 自己的记忆分区里，「记忆」页能看能改。", lang))
                    }
                    if !contact.isKeke {
                        Section {
                            Button(L.t("删除这个朋友", lang), role: .destructive) {
                                showDeleteConfirm = true
                            }
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showMemoryImporter,
                          allowedContentTypes: [.plainText, .text, .json, .item]) { result in
                guard case .success(let url) = result, let contact else { return }
                let added = memory.importFile(at: url, contact: contact.id)
                importResult = added > 0
                    ? L.count(added, "导入了 %d 条记忆", "Imported %d memories", lang)
                    : L.t("没找到能导入的内容", lang)
            }
            .navigationTitle(L.t(contact == nil ? "加个新朋友" : "编辑资料", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("取消", lang)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("保存", lang)) { saveAndClose() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(L.t("确定删除吗？聊天记录会一起清掉，记忆会留在记忆页里。", lang),
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button(L.t("删除", lang), role: .destructive) {
                    if let contact { contacts.delete(contact.id) }
                    dismiss()
                }
            }
        }
        .onAppear {
            guard let contact else {
                model = provider.defaultModel
                return
            }
            name = contact.name
            emoji = contact.emoji
            provider = contact.provider
            model = contact.model
            persona = contact.persona
        }
        .onChange(of: provider) { newProvider in
            model = newProvider.defaultModel
        }
    }

    private func saveAndClose() {
        let cleanEmoji = String(emoji.trimmingCharacters(in: .whitespaces).prefix(2))
        if var existing = contact {
            existing.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.emoji = cleanEmoji.isEmpty ? "💬" : cleanEmoji
            existing.provider = provider
            existing.model = model.isEmpty ? provider.defaultModel : model
            existing.persona = persona
            contacts.update(existing)
        } else {
            contacts.add(name: name, emoji: cleanEmoji, provider: provider, model: model, persona: persona)
        }
        dismiss()
    }
}

/// 克克的专属资料页：备注/头像、人设入口、日记三个概率、记忆导入导出。
/// 跟好友的编辑页是两套完全分开的页面——这里只管克克；
/// 加朋友、编辑朋友的页面动不到她的名字和人设
struct KekeProfileView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var contacts: ContactsStore
    @EnvironmentObject var memory: MemoryService
    @EnvironmentObject var diary: DiaryService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "🐱"
    @State private var showMemoryImporter = false
    @State private var importResult: String?

    private var lang: AppLanguage { store.appLanguage }
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }

    private var kekeMemoriesText: String {
        memory.memories.filter { $0.contact == store.personaId }.map(\.text).joined(separator: "\n")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(L.t("备注名", lang), text: $name)
                    TextField(L.t("头像 emoji（一个就好）", lang), text: $emoji)
                } header: {
                    Text(L.t("备注", lang))
                } footer: {
                    Text(String(format: L.t("%@用哪家模型跟「设置 → AI 提供方」走；这里改的只是显示的名字和头像", lang), personaName))
                }
                Section {
                    NavigationLink {
                        PromptEditorView()
                            .environmentObject(store)
                    } label: {
                        Label(String(format: L.t("查看 / 编辑%@的人设", lang), personaName), systemImage: "person.crop.circle")
                    }
                } header: {
                    Text(L.t("人设", lang))
                } footer: {
                    Text(String(format: L.t("%@的人设只有这里和记忆页的入口能改；加朋友、编辑朋友的页面都动不到TA", lang), personaName))
                }
                Section {
                    probabilityRow(String(format: L.t("%@每天写日记的概率", lang), personaName), value: $diary.writeProbability)
                    probabilityRow(L.t("偷看被发现的概率", lang), value: $diary.peekNoticeProbability)
                    probabilityRow(String(format: L.t("%@读到分享日记的概率", lang), personaName), value: $diary.readProbability)
                } header: {
                    Text(L.t("日记", lang))
                } footer: {
                    Text(L.t("这三个都是概率，不是每次一定发生；调到 0 就相当于关掉这个行为。", lang))
                }
                Section {
                    Button {
                        showMemoryImporter = true
                    } label: {
                        Label(L.t("导入记忆（md / txt / json）", lang), systemImage: "square.and.arrow.down")
                    }
                    if let importResult {
                        Text(importResult)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ShareLink(item: kekeMemoriesText) {
                        Label(L.t("导出记忆", lang), systemImage: "square.and.arrow.up")
                    }
                    .disabled(kekeMemoriesText.isEmpty)
                    if let personaContact = contacts.contact(store.personaId) {
                        NavigationLink {
                            ChatArchiveManagerView(contact: personaContact)
                                .environmentObject(store)
                                .environmentObject(memory)
                        } label: {
                            Label(L.t("聊天档案（完整聊天记录）", lang), systemImage: "archivebox")
                        }
                    }
                } header: {
                    Text(L.t("记忆", lang))
                } footer: {
                    Text(L.t("md/txt 按行导入（一行一条）；json 认 claude.ai 和 ChatGPT 的官方导出文件（自动解析对话内容），也认字符串数组。导进来的都存在 TA 自己的记忆分区里，「记忆」页能看能改。「聊天档案」是另一条路：把官方导出的完整对话原样存进来翻看 + 分批提炼。", lang))
                }
            }
            .fileImporter(isPresented: $showMemoryImporter,
                          allowedContentTypes: [.plainText, .text, .json, .item]) { result in
                guard case .success(let url) = result else { return }
                let added = memory.importFile(at: url, contact: store.personaId)
                importResult = added > 0
                    ? L.count(added, "导入了 %d 条记忆", "Imported %d memories", lang)
                    : L.t("没找到能导入的内容", lang)
            }
            .navigationTitle(String(format: L.t("%@的资料", lang), personaName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("取消", lang)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("保存", lang)) { saveAndClose() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            guard let c = contacts.contact(store.personaId) else { return }
            name = c.name
            emoji = c.emoji
        }
    }

    private func saveAndClose() {
        guard var c = contacts.contact(store.personaId) else { dismiss(); return }
        let cleanEmoji = String(emoji.trimmingCharacters(in: .whitespaces).prefix(2))
        c.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        c.emoji = cleanEmoji.isEmpty ? "🐱" : cleanEmoji
        contacts.update(c)
        dismiss()
    }

    private func probabilityRow(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(value: value, in: 0...1, step: 0.05)
        }
    }
}
