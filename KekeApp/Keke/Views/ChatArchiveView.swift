import SwiftUI
import UniformTypeIdentifiers

// MARK: - 数据结构

/// 档案里的一条消息（role 只有 "user" / "other" 两种）
struct ArchivedMessage: Codable {
    let role: String
    let text: String
    let date: Date?
}

/// 从 conversations.json 里解析出来、还没入库的一场对话
struct ParsedConversation: Identifiable {
    let id = UUID()
    let title: String
    let messages: [ArchivedMessage]
}

/// 聊天档案仓库：每个联系人一份索引 + 每场对话一个文件。
/// 完整聊天记录存在这里随时翻看，不并进实时聊天窗口——
/// 十万级的记录塞进聊天窗口每次启动都要全量解析，会卡死
@MainActor
final class ChatArchiveStore: ObservableObject {
    struct Meta: Codable, Identifiable {
        let id: String
        var title: String
        let messageCount: Int
        let importedAt: Date
    }

    let contactID: String
    @Published private(set) var metas: [Meta] = []

    init(contactID: String) {
        self.contactID = contactID
        load()
    }

    private static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var indexURL: URL {
        Self.docs.appendingPathComponent("chat_archive_index_\(contactID).json")
    }
    private func messagesURL(_ id: String) -> URL {
        Self.docs.appendingPathComponent("chat_archive_\(contactID)_\(id).json")
    }

    /// 把挑好的对话存进档案，返回存了几场
    @discardableResult
    func importParsed(_ conversations: [ParsedConversation]) -> Int {
        var added = 0
        for conversation in conversations {
            let id = UUID().uuidString
            guard let data = try? JSONEncoder().encode(conversation.messages) else { continue }
            try? data.write(to: messagesURL(id), options: .atomic)
            metas.insert(Meta(id: id, title: conversation.title,
                              messageCount: conversation.messages.count, importedAt: Date()), at: 0)
            added += 1
        }
        saveIndex()
        return added
    }

    func messages(of id: String) -> [ArchivedMessage] {
        guard let data = try? Data(contentsOf: messagesURL(id)),
              let messages = try? JSONDecoder().decode([ArchivedMessage].self, from: data) else { return [] }
        return messages
    }

    func delete(_ id: String) {
        metas.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: messagesURL(id))
        saveIndex()
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(metas) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? JSONDecoder().decode([Meta].self, from: data) else { return }
        metas = saved
    }

    // MARK: - 解析 conversations.json（claude.ai 和 ChatGPT 两种官方导出都认）

    nonisolated static func parseConversations(_ data: Data) -> [ParsedConversation] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var result: [ParsedConversation] = []
        for item in root {
            if let chatMessages = item["chat_messages"] as? [[String: Any]] {
                // claude.ai 导出：{name, chat_messages: [{sender, text/content, created_at}]}
                var messages: [ArchivedMessage] = []
                for m in chatMessages {
                    let sender = m["sender"] as? String ?? ""
                    var text = m["text"] as? String ?? ""
                    if text.isEmpty, let contents = m["content"] as? [[String: Any]] {
                        text = contents.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    messages.append(ArchivedMessage(role: sender == "human" ? "user" : "other",
                                                    text: trimmed,
                                                    date: isoDate(m["created_at"] as? String)))
                }
                guard !messages.isEmpty else { continue }
                let name = (item["name"] as? String) ?? ""
                result.append(ParsedConversation(title: name.isEmpty ? "未命名对话" : name,
                                                 messages: messages))
            } else if let mapping = item["mapping"] as? [String: Any] {
                // ChatGPT 导出：{title, mapping: {id: {message: {author{role}, content{parts}, create_time}}}}
                var entries: [(Double, ArchivedMessage)] = []
                for value in mapping.values {
                    guard let node = value as? [String: Any],
                          let message = node["message"] as? [String: Any],
                          let author = message["author"] as? [String: Any],
                          let role = author["role"] as? String,
                          role == "user" || role == "assistant" else { continue }
                    var text = ""
                    if let content = message["content"] as? [String: Any] {
                        if let parts = content["parts"] as? [Any] {
                            text = parts.compactMap { $0 as? String }.joined(separator: "\n")
                        } else if let plain = content["text"] as? String {
                            text = plain
                        }
                    }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    let time = message["create_time"] as? Double ?? 0
                    entries.append((time, ArchivedMessage(role: role == "user" ? "user" : "other",
                                                          text: trimmed,
                                                          date: time > 0 ? Date(timeIntervalSince1970: time) : nil)))
                }
                guard !entries.isEmpty else { continue }
                entries.sort { $0.0 < $1.0 }
                let title = (item["title"] as? String) ?? ""
                result.append(ParsedConversation(title: title.isEmpty ? "未命名对话" : title,
                                                 messages: entries.map { $0.1 }))
            }
        }
        return result
    }

    nonisolated private static func isoDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

// MARK: - 档案管理页（资料页 → 聊天档案）

/// 某个联系人（克克或好友）的聊天档案：导入 conversations.json、翻看完整记录、
/// 分批提炼成 TA 的记忆。挂在资料页的 NavigationLink 里
struct ChatArchiveManagerView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var memory: MemoryService
    let contact: Contact
    @StateObject private var archive: ChatArchiveStore

    @State private var showImporter = false
    @State private var parsing = false
    @State private var parseFailed = false
    @State private var parsedBatch: [ParsedConversation]?
    @State private var reading: ChatArchiveStore.Meta?
    // 提炼状态
    @State private var distillingID: String?
    @State private var distillDone = 0
    @State private var distillTotal = 0
    @State private var distillAdded: Int?
    @State private var distillCancelled = false

    init(contact: Contact) {
        self.contact = contact
        _archive = StateObject(wrappedValue: ChatArchiveStore(contactID: contact.id))
    }

    private var lang: AppLanguage { store.appLanguage }

    /// 提炼用哪套模型/人设：克克走当前设置，好友走自己绑定的那套
    private var aiParams: (provider: AIProvider, apiKey: String, model: String, systemPrompt: String) {
        if contact.isKeke {
            return (store.provider, store.apiKey, store.model, store.effectiveSystemPrompt)
        }
        let persona = contact.persona.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = persona.isEmpty
            ? "你的名字是\(contact.name)。你在手机上和 \(store.myName) 聊天。"
            : persona
        return (contact.provider, ContactsStore.apiKey(for: contact.provider), contact.model, prompt)
    }

    var body: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    if parsing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L.t("在解析文件…", lang))
                        }
                    } else {
                        Label(L.t("导入 conversations.json", lang), systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(parsing)
                if parseFailed {
                    Text(L.t("没识别出对话——看看选的是不是导出包里的 conversations.json", lang))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text(L.t("claude.ai：网页版 头像 → Settings → Privacy → Export data，邮件里下载 zip，解压出 conversations.json。ChatGPT：Settings → Data controls → Export。完整记录存在档案里随时翻看，不会塞进聊天窗口。", lang))
            }

            Section {
                if archive.metas.isEmpty {
                    Text(L.t("还没导入过聊天档案", lang))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(archive.metas) { meta in
                        archiveRow(meta)
                    }
                }
            } header: {
                Text(L.t("已导入的对话", lang))
            } footer: {
                Text(L.t("「提炼成记忆」：每约 40 条聊天占一次 AI 调用，很长的对话会连着跑很多次、费一点 token，随时可以停；提炼出来的都进 TA 自己的记忆分区。", lang))
            }
        }
        .navigationTitle(L.t("聊天档案", lang))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json, .plainText, .item]) { result in
            guard case .success(let url) = result else { return }
            importFile(url)
        }
        .sheet(item: $reading) { meta in
            ArchiveReaderView(title: meta.title, contactName: contact.name,
                              messages: archive.messages(of: meta.id))
                .environmentObject(store)
        }
        .sheet(isPresented: Binding(get: { parsedBatch != nil },
                                    set: { if !$0 { parsedBatch = nil } })) {
            if let parsedBatch {
                ArchiveImportPicker(conversations: parsedBatch) { picked in
                    archive.importParsed(picked)
                    self.parsedBatch = nil
                }
                .environmentObject(store)
            }
        }
    }

    private func archiveRow(_ meta: ChatArchiveStore.Meta) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                reading = meta
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meta.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(L.count(meta.messageCount, "%d 条 · 点开翻看", "%d messages · tap to read", lang))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if distillingID == meta.id {
                HStack(spacing: 8) {
                    ProgressView(value: Double(distillDone), total: Double(max(distillTotal, 1)))
                    Text("\(distillDone)/\(distillTotal)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Button(L.t("停", lang)) { distillCancelled = true }
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        distill(meta)
                    } label: {
                        Label(L.t("提炼成记忆", lang), systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(aiParams.apiKey.isEmpty ? Theme.textSecondary : Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(aiParams.apiKey.isEmpty || distillingID != nil)
                    if let distillAdded, distillingID == nil {
                        Text(L.count(distillAdded, "上轮记住了 %d 件事", "Last run remembered %d", lang))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                archive.delete(meta.id)
            } label: {
                Label(L.t("删除", lang), systemImage: "trash")
            }
        }
    }

    // MARK: - 导入

    private func importFile(_ url: URL) {
        parsing = true
        parseFailed = false
        Task {
            let secured = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            if secured { url.stopAccessingSecurityScopedResource() }
            let parsed = data.map { ChatArchiveStore.parseConversations($0) } ?? []
            parsing = false
            if parsed.isEmpty {
                parseFailed = true
            } else {
                parsedBatch = parsed
            }
        }
    }

    // MARK: - 分批提炼

    private func distill(_ meta: ChatArchiveStore.Meta) {
        let all = archive.messages(of: meta.id)
        guard !all.isEmpty else { return }
        let chunkSize = 40
        var chunks: [[ArchivedMessage]] = []
        var index = 0
        while index < all.count {
            chunks.append(Array(all[index ..< min(index + chunkSize, all.count)]))
            index += chunkSize
        }

        distillingID = meta.id
        distillDone = 0
        distillTotal = chunks.count
        distillAdded = nil
        distillCancelled = false
        let params = aiParams
        let contactID = contact.id
        let userName = store.myName

        Task {
            var added = 0
            for chunk in chunks {
                if distillCancelled { break }
                let recent = chunk.map {
                    ChatMessage(role: $0.role == "user" ? .user : .keke, text: $0.text)
                }
                if let new = try? await ClaudeService.extractMemories(
                    recent: recent, existing: memory.allTexts(contact: contactID), userName: userName,
                    provider: params.provider, apiKey: params.apiKey,
                    model: params.model, systemPrompt: params.systemPrompt
                ) {
                    for entry in new {
                        memory.add(entry.text, importance: entry.importance, valence: entry.valence,
                                   arousal: entry.arousal, status: entry.open ? .open : .none,
                                   contact: contactID)
                    }
                    added += new.count
                }
                distillDone += 1
            }
            distillAdded = added
            distillingID = nil
        }
    }
}

// MARK: - 挑选要导入的对话

struct ArchiveImportPicker: View {
    @EnvironmentObject var store: ChatStore
    let conversations: [ParsedConversation]
    let onImport: ([ParsedConversation]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(conversations) { conversation in
                        Button {
                            if selected.contains(conversation.id) {
                                selected.remove(conversation.id)
                            } else {
                                selected.insert(conversation.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conversation.title)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    Text(L.count(conversation.messages.count, "%d 条", "%d messages", lang))
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(conversation.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(conversation.id)
                                                     ? Theme.accent : Theme.textSecondary)
                            }
                        }
                    }
                } header: {
                    Text(L.count(conversations.count, "识别出 %d 场对话", "Found %d conversations", lang))
                }
            }
            .navigationTitle(L.t("挑选要导入的对话", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("取消", lang)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.count == conversations.count
                           ? L.t("全不选", lang) : L.t("全选", lang)) {
                        if selected.count == conversations.count {
                            selected = []
                        } else {
                            selected = Set(conversations.map(\.id))
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onImport(conversations.filter { selected.contains($0.id) })
                } label: {
                    Text(L.count(selected.count, "导入所选（%d 场）", "Import Selected (%d)", lang))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
                }
                .disabled(selected.isEmpty)
                .opacity(selected.isEmpty ? 0.5 : 1)
                .padding(14)
                .background(Theme.backgroundDeep)
            }
        }
        .onAppear {
            // 默认全选，反着取消更省事
            selected = Set(conversations.map(\.id))
        }
    }
}

// MARK: - 翻看一场存档的完整记录

struct ArchiveReaderView: View {
    @EnvironmentObject var store: ChatStore
    let title: String
    let contactName: String
    let messages: [ArchivedMessage]
    @Environment(\.dismiss) private var dismiss

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        bubble(message)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("关闭", lang)) { dismiss() }
                }
            }
        }
    }

    private func bubble(_ message: ArchivedMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 40) }
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(message.role == "user" ? Theme.bubbleUser : Theme.bubbleKeke)
                    )
                    .textSelection(.enabled)
                if let date = message.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if message.role != "user" { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 14)
    }
}
