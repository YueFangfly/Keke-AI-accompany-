import SwiftUI

struct Persona: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var icon: String
    var color: String
    var subtitle: String
    var systemPrompt: String
    var characterType: String

    init(id: String, name: String, icon: String, color: String, subtitle: String,
         systemPrompt: String, characterType: String = "clawd") {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.subtitle = subtitle
        self.systemPrompt = systemPrompt
        self.characterType = characterType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decode(String.self, forKey: .icon)
        color = try c.decode(String.self, forKey: .color)
        subtitle = try c.decode(String.self, forKey: .subtitle)
        systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        characterType = try c.decodeIfPresent(String.self, forKey: .characterType) ?? "clawd"
    }

    var displayColor: Color {
        switch color {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "cyan": return .cyan
        case "red": return .red
        case "yellow": return .yellow
        default: return .gray
        }
    }
}

enum PersonaStore {
    private static let customKey = "keke_custom_personas"

    static var builtIn: [Persona] {
        []
    }

    static func allPersonas() -> [Persona] {
        builtIn + loadCustom()
    }

    static func loadCustom() -> [Persona] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let list = try? JSONDecoder().decode([Persona].self, from: data) else { return [] }
        return list
    }

    static func saveCustom(_ list: [Persona]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
    }

    static func addCustom(_ p: Persona) {
        var list = loadCustom()
        list.append(p)
        saveCustom(list)
    }

    static func removeCustom(id: String) {
        var list = loadCustom()
        list.removeAll { $0.id == id }
        saveCustom(list)
    }

    static func activePersonaId() -> String? {
        let saved = UserDefaults.standard.string(forKey: "keke_active_persona")
        if let saved, allPersonas().contains(where: { $0.id == saved }) { return saved }
        return allPersonas().first?.id
    }

    static func setActivePersonaId(_ id: String) {
        UserDefaults.standard.set(id, forKey: "keke_active_persona")
    }

    static func persona(for id: String) -> Persona {
        allPersonas().first { $0.id == id }
            ?? allPersonas().first
            ?? Persona(id: "placeholder", name: "AI", icon: "🤖", color: "purple",
                       subtitle: "", systemPrompt: "", characterType: "clawd")
    }
}
