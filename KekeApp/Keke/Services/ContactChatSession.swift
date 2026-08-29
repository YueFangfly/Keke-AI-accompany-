import Foundation
import SwiftUI

/// 非克克联系人的聊天会话：每个联系人一份独立的历史文件、独立的记忆分区，
/// 用联系人自己绑定的提供方/模型发请求（Key 按提供方共用，设置页里填的那份）。
/// 克克不走这里——她还是原来的 ChatStore，专属功能都在那边。
@MainActor
final class ContactChatSession: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false

    let contact: Contact
    private let memory: MemoryService?
    private let userName: String
    private var currentTask: Task<Void, Never>?

    init(contact: Contact, memory: MemoryService?, userName: String) {
        self.contact = contact
        self.memory = memory
        self.userName = userName
        load()
    }

    private static func saveURL(contactID: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat_contact_\(contactID).json")
    }

    /// 会话列表里显示的最后一句预览（不用把整个会话对象建出来）
    static func lastMessage(contactID: String) -> ChatMessage? {
        guard let data = try? Data(contentsOf: saveURL(contactID: contactID)),
              let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return nil }
        return saved.last
    }

    static func deleteHistory(contactID: String) {
        try? FileManager.default.removeItem(at: saveURL(contactID: contactID))
    }

    /// 发给模型的 system prompt。人设由用户自己写，App 不塞任何角色描述
    var effectiveSystemPrompt: String {
        // 人设由用户自己写，App 不塞任何角色描述；没写就发空的
        return contact.persona.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        save()
        currentTask = Task { await requestReply() }
    }

    func cancelSend() {
        currentTask?.cancel()
        currentTask = nil
        isThinking = false
    }

    func deleteMessage(_ id: UUID) {
        messages.removeAll { $0.id == id }
        save()
    }

    private func requestReply() async {
        isThinking = true
        do {
            let lastUserText = messages.last(where: { $0.role == .user })?.text ?? ""
            let context = memory?.contextBlock(for: lastUserText, userName: userName, contact: contact.id)
            let result = try await ClaudeService.send(
                messages: messages.compactMap(\.modelPayload), userName: userName,
                provider: contact.provider,
                apiKey: ContactsStore.apiKey(for: contact.provider),
                model: contact.model,
                systemPrompt: effectiveSystemPrompt,
                extraContext: context, webTools: false, toolExecutor: nil)
            try Task.checkCancellation()
            let reply = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            messages.append(ChatMessage(role: .keke, text: reply,
                                        usage: result.usage.isEmpty ? nil : result.usage,
                                        durationMs: result.durationMs,
                                        model: contact.model,
                                        providerId: contact.provider.rawValue))
            maybeExtractMemories()
        } catch is CancellationError {
            // 用户主动停止
        } catch {
            messages.append(ChatMessage(role: .keke, text: "（好像出了点问题：\(error.localizedDescription)）"))
        }
        isThinking = false
        save()
    }

    /// 跟克克一样：每积累 10 条新消息，后台提炼一次记忆，存进这个联系人自己的分区
    private func maybeExtractMemories() {
        guard let memory else { return }
        let counterKey = "memory_extracted_at_count_\(contact.id)"
        let lastCount = UserDefaults.standard.integer(forKey: counterKey)
        guard messages.count - lastCount >= 10 else { return }
        UserDefaults.standard.set(messages.count, forKey: counterKey)

        let recent = Array(messages.suffix(40))
        let contactID = contact.id
        let provider = contact.provider
        let model = contact.model
        let systemPrompt = effectiveSystemPrompt
        let userName = userName
        Task { [weak memory] in
            guard let memory else { return }
            guard let new = try? await ClaudeService.extractMemories(
                recent: recent, existing: memory.allTexts(contact: contactID), userName: userName,
                personaName: contact.name,
                provider: provider, apiKey: ContactsStore.apiKey(for: provider),
                model: model, systemPrompt: systemPrompt
            ), !new.isEmpty else { return }
            for entry in new {
                memory.add(entry.text, importance: entry.importance, valence: entry.valence,
                           arousal: entry.arousal, status: entry.open ? .open : .none,
                           contact: contactID)
            }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: Self.saveURL(contactID: contact.id), options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.saveURL(contactID: contact.id)),
              let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return }
        messages = saved
    }
}
