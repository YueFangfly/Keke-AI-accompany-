import Foundation

/// 一个聊天联系人（微信化改造）：克克是特殊的那一个（专属功能都绑她），
/// 其他联系人是"纯聊天"——自定义备注、头像 emoji、绑定的提供方/模型、人设（可空白）、
/// 各自独立的聊天历史和记忆分区。
struct Contact: Identifiable, Codable, Equatable {
    /// 用字符串当 id：克克固定是 "keke"（跟记忆分区的默认值对上），其他人是 uuid
    var id: String
    var name: String
    var emoji: String
    var provider: AIProvider
    var model: String
    /// 人设（system prompt）；空字符串 = 没有人设，只发一句极简说明 + 这个人的记忆
    var persona: String
    /// 克克专属：朋友圈主动发/日记/养猫/打电话/冒泡这些功能只绑她
    var isKeke: Bool
    var createdAt: Date = Date()
}

/// 联系人列表：第一次启动种下 克克 / Claude / GPT / DeepSeek 四个，
/// 之后可以随便加新朋友（选模型、写备注和人设）、编辑、删除（克克不能删）
@MainActor
final class ContactsStore: ObservableObject {
    @Published var contacts: [Contact] = []

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keke_contacts.json")
    }

    init() {
        load()
        if contacts.isEmpty {
            contacts = Self.seeds
            save()
        }
    }

    /// 初始四个：克克（特殊）+ 三个空白人设的"光板"模型
    private static var seeds: [Contact] {
        [
            Contact(id: "keke", name: "克克", emoji: "🐱",
                    provider: .deepseek, model: AIProvider.deepseek.defaultModel,
                    persona: "", isKeke: true),
            Contact(id: "claude", name: "Claude", emoji: "✳️",
                    provider: .claude, model: AIProvider.claude.defaultModel,
                    persona: "", isKeke: false),
            Contact(id: "gpt", name: "GPT", emoji: "🌀",
                    provider: .openai, model: AIProvider.openai.defaultModel,
                    persona: "", isKeke: false),
            Contact(id: "deepseek", name: "DeepSeek", emoji: "🐳",
                    provider: .deepseek, model: AIProvider.deepseek.defaultModel,
                    persona: "", isKeke: false),
        ]
    }

    var keke: Contact? { contacts.first(where: \.isKeke) }
    var friends: [Contact] { contacts.filter { !$0.isKeke } }

    func contact(_ id: String) -> Contact? {
        contacts.first(where: { $0.id == id })
    }

    func add(name: String, emoji: String, provider: AIProvider, model: String, persona: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let contact = Contact(id: UUID().uuidString, name: trimmed,
                              emoji: emoji.isEmpty ? "💬" : emoji,
                              provider: provider,
                              model: model.isEmpty ? provider.defaultModel : model,
                              persona: persona, isKeke: false)
        contacts.append(contact)
        save()
    }

    func update(_ contact: Contact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[index] = contact
        save()
    }

    /// 删除联系人（克克删不掉），聊天记录文件一起清；记忆分区留着不动（记忆页里还能看）
    func delete(_ id: String) {
        guard let contact = contact(id), !contact.isKeke else { return }
        contacts.removeAll { $0.id == id }
        ContactChatSession.deleteHistory(contactID: id)
        save()
    }

    /// 这个联系人的提供方有没有填 Key（Key 是按提供方共用的，在设置页填）
    static func hasKey(for provider: AIProvider) -> Bool {
        APIKeyStore.hasKey(for: provider.id)
    }

    static func apiKey(for provider: AIProvider) -> String {
        APIKeyStore.key(for: provider.id)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([Contact].self, from: data) else { return }
        contacts = saved
    }
}
