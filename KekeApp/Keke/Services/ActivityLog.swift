import Foundation

struct ActivityEntry: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let category: ActivityCategory
    let summary: String

    init(category: ActivityCategory, summary: String) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.category = category
        self.summary = summary
    }

    enum ActivityCategory: String, Codable {
        case game
        case translation
        case exchangeRate
        case news
        case drawing
        case reading
        case timer
        case codeReview
        case diary
        case calendar
        case health
        case settings
        case homepage
        case explore
    }
}

@MainActor
final class ActivityLog: ObservableObject {
    @Published private(set) var entries: [ActivityEntry] = []

    private let saveKey: String
    private let maxEntries = 100

    init(personaId: String = "keke") {
        self.saveKey = "\(personaId)_activity_log"
        load()
    }

    func log(_ category: ActivityEntry.ActivityCategory, _ summary: String) {
        let entry = ActivityEntry(category: category, summary: summary)
        entries.append(entry)
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
        save()
    }

    func contextBlock(userName: String = "wifey") -> String? {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let recent = entries.filter { $0.timestamp >= cutoff }
        guard !recent.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let lines = recent.suffix(15).map { entry in
            let time = formatter.string(from: entry.timestamp)
            return "[\(time)] \(entry.summary)"
        }

        return "\(userName) 最近在 App 里做的事（你可以自然地提起、关心她）：\n" +
            lines.joined(separator: "\n")
    }

    func recentForMemory() -> [String] {
        let cutoff = Date().addingTimeInterval(-6 * 3600)
        return entries
            .filter { $0.timestamp >= cutoff }
            .map { $0.summary }
    }

    func clearOlderThan(_ interval: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-interval)
        entries.removeAll { $0.timestamp < cutoff }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([ActivityEntry].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        entries = decoded.filter { $0.timestamp >= cutoff }
    }
}
