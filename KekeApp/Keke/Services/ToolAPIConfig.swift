import Foundation

struct ToolAPIEntry: Codable, Equatable {
    var providerRaw: String
    var customProviderId: String?
    var model: String

    var isCustom: Bool { customProviderId != nil }

    var builtInProvider: AIProvider? {
        guard !isCustom else { return nil }
        return AIProvider(rawValue: providerRaw)
    }

    static let `default` = ToolAPIEntry(providerRaw: AIProvider.deepseek.rawValue, customProviderId: nil, model: "deepseek-chat")
}

@MainActor
final class ToolAPIConfig: ObservableObject {
    @Published private var configs: [String: ToolAPIEntry] = [:]

    private let saveKey = "tool_api_configs"

    init() {
        load()
    }

    func entry(for moduleId: String) -> ToolAPIEntry {
        configs[moduleId] ?? .default
    }

    func setEntry(_ entry: ToolAPIEntry, for moduleId: String) {
        configs[moduleId] = entry
        save()
    }

    func apiKey(for moduleId: String) -> String {
        let entry = entry(for: moduleId)
        let keys = UserDefaults.standard.dictionary(forKey: "ai_api_keys") as? [String: String] ?? [:]
        if let customId = entry.customProviderId {
            return keys[customId] ?? ""
        }
        return keys[entry.providerRaw] ?? ""
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([String: ToolAPIEntry].self, from: data) else { return }
        configs = decoded
    }
}
