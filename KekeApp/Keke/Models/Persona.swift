import SwiftUI

struct Persona: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var icon: String
    var color: String
    var subtitle: String
    var systemPrompt: String

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
        [
            Persona(id: "keke",
                    name: "克克",
                    icon: "🦀",
                    color: "blue",
                    subtitle: "住在手机里的小螃蟹",
                    systemPrompt: ""),
        ]
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

    static func activePersonaId() -> String {
        UserDefaults.standard.string(forKey: "keke_active_persona") ?? "keke"
    }

    static func setActivePersonaId(_ id: String) {
        UserDefaults.standard.set(id, forKey: "keke_active_persona")
    }

    static func persona(for id: String) -> Persona {
        allPersonas().first { $0.id == id } ?? builtIn[0]
    }
}
