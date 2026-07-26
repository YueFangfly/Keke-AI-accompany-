import Foundation
import UserNotifications

/// 一个克克闹钟
struct KekeAlarm: Identifiable, Codable, Equatable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var label: String
    var repeatsDaily: Bool
    var enabled = true
    /// 克克写的叫醒/提醒的话（创建时生成）
    var kekeText: String

    var timeText: String { String(format: "%02d:%02d", hour, minute) }
}

/// 克克闹钟：用本地通知实现（iOS 不允许第三方 App 设系统闹钟）。
/// 到点必弹、克克的话做通知内容；声音是通知声，不会像系统闹钟一直响。
@MainActor
final class AlarmService: ObservableObject {
    @Published var alarms: [KekeAlarm] = []

    private let center = UNUserNotificationCenter.current()

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keke_alarms.json")
    }

    init() {
        load()
    }

    func add(hour: Int, minute: Int, label: String, repeatsDaily: Bool, store: ChatStore) async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])

        let timeText = String(format: "%02d:%02d", hour, minute)
        let fallback = label.isEmpty
            ? "叮——克克在敲你的壳，到点啦。*挥爪*"
            : "叮——克克提醒：\(label)。*挥爪*"
        let text = (try? await ClaudeService.generateAlarmLine(
            label: label, time: timeText, userName: store.myName, provider: store.provider, apiKey: store.apiKey, model: store.model,
            systemPrompt: store.effectiveSystemPrompt
        )) ?? fallback

        let alarm = KekeAlarm(hour: hour, minute: minute, label: label,
                              repeatsDaily: repeatsDaily, kekeText: text)
        var list = alarms
        list.append(alarm)
        list.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        alarms = list
        save()
        await schedule(alarm)
    }

    func toggle(_ alarm: KekeAlarm) async {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        var updated = alarms[index]
        updated.enabled.toggle()
        alarms[index] = updated
        save()
        if updated.enabled {
            await schedule(updated)
        } else {
            unschedule(updated)
        }
    }

    func delete(_ alarm: KekeAlarm) {
        unschedule(alarm)
        alarms.removeAll { $0.id == alarm.id }
        save()
    }

    // MARK: - 排期

    private func schedule(_ alarm: KekeAlarm) async {
        unschedule(alarm)
        guard alarm.enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "克克闹钟 ⏰\(alarm.label.isEmpty ? "" : " · \(alarm.label)")"
        content.body = alarm.kekeText
        content.sound = .default

        var comps = DateComponents()
        comps.hour = alarm.hour
        comps.minute = alarm.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: alarm.repeatsDaily)
        let request = UNNotificationRequest(identifier: "alarm_\(alarm.id.uuidString)",
                                            content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func unschedule(_ alarm: KekeAlarm) {
        center.removePendingNotificationRequests(withIdentifiers: ["alarm_\(alarm.id.uuidString)"])
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([KekeAlarm].self, from: data) else { return }
        alarms = saved
    }
}
