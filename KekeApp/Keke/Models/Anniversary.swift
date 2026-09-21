import Foundation

struct Anniversary: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var date: Date
    var note: String
    var isRepeatYearly: Bool
    var emoji: String

    init(title: String, date: Date, note: String = "", isRepeatYearly: Bool = true, emoji: String = "🎉") {
        self.id = UUID().uuidString
        self.title = title
        self.date = date
        self.note = note
        self.isRepeatYearly = isRepeatYearly
        self.emoji = emoji
    }

    var daysFromNow: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if isRepeatYearly {
            var components = calendar.dateComponents([.month, .day], from: date)
            components.year = calendar.component(.year, from: today)
            guard let thisYear = calendar.date(from: components) else { return 0 }
            let target = thisYear < today
                ? calendar.date(byAdding: .year, value: 1, to: thisYear) ?? thisYear
                : thisYear
            return calendar.dateComponents([.day], from: today, to: target).day ?? 0
        } else {
            let target = calendar.startOfDay(for: date)
            return calendar.dateComponents([.day], from: today, to: target).day ?? 0
        }
    }

    var daysSince: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
    }

    var yearsCount: Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.year], from: date, to: Date()).year ?? 0
    }

    var isToday: Bool { daysFromNow == 0 }
}

@MainActor
final class AnniversaryStore: ObservableObject {
    @Published var items: [Anniversary] = []

    private let saveKey: String

    init(personaId: String = "keke") {
        self.saveKey = "\(personaId)_anniversaries"
        load()
    }

    func add(_ item: Anniversary) {
        items.append(item)
        save()
    }

    func update(_ item: Anniversary) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
            save()
        }
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    var upcoming: [Anniversary] {
        items.sorted { $0.daysFromNow < $1.daysFromNow }
    }

    func contextBlock(userName: String) -> String? {
        guard !items.isEmpty else { return nil }
        let todayItems = items.filter { $0.isToday }
        let soonItems = items.filter { !$0.isToday && $0.daysFromNow <= 7 }.sorted { $0.daysFromNow < $1.daysFromNow }

        var lines: [String] = []
        for a in todayItems {
            lines.append("今天是\(userName)的纪念日「\(a.title)」！第\(a.yearsCount)年了")
        }
        for a in soonItems {
            lines.append("还有\(a.daysFromNow)天是\(userName)的「\(a.title)」")
        }
        guard !lines.isEmpty else { return nil }
        return "纪念日提醒：\n" + lines.joined(separator: "\n")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([Anniversary].self, from: data) else { return }
        items = decoded
    }
}
