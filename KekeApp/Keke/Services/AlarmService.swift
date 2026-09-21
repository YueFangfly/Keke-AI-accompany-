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

    /// 最近一次生成闹钟寄语失败的原因。建闹钟的界面拿它提示用户，
    /// 免得闹钟静悄悄地退成中性文案而没人知道
    @Published var lastError: String?

    init() {
        load()
    }

    func add(hour: Int, minute: Int, label: String, repeatsDaily: Bool, store: ChatStore) async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])

        let timeText = String(format: "%02d:%02d", hour, minute)
        let pName = PersonaStore.persona(for: store.personaId).name
        // 生成不出来时用一句**App 口吻**的中性提醒，不替角色编话。
        // 这里跟别处不一样：通知正文是闹钟响的时候才看到的，那时候再显示
        // 「没生成出来：xxx」既帮不上忙也很吓人——出错的是几小时前建闹钟那一刻。
        // 所以正文退回中性文案，把原因通过 lastError 抛给建闹钟的界面
        let neutral = label.isEmpty ? "闹钟时间到了" : "闹钟：\(label)"
        let text: String
        switch await GenerationFallback.run({
            try await ClaudeService.generateAlarmLine(
                label: label, time: timeText, userName: store.myName,
                personaName: pName,
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt)
        }) {
        case .success(let line):
            text = line
            lastError = nil
        case .failure(let error):
            text = neutral
            lastError = GenerationFallback.message(error)
        }

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
        content.title = "闹钟 ⏰\(alarm.label.isEmpty ? "" : " · \(alarm.label)")"
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
