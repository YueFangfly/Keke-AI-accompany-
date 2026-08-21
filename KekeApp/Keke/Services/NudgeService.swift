import Foundation
import UserNotifications
import SwiftUI

/// 克克主动冒泡：根据最近聊天生成几句想说的话，
/// 挑 11:00–22:59 之间的随机时间用本地通知冒出来。
/// 内容规则里明确禁止"吃没吃饭"和"早安/晚安"式问候。
@MainActor
final class NudgeService: NSObject, ObservableObject {
    let personaId: String

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "\(personaId)_nudge_enabled") }
    }

    /// 每天大约几条（1~3）
    @Published var perDay: Int {
        didSet { UserDefaults.standard.set(perDay, forKey: "\(personaId)_nudge_per_day") }
    }

    @Published var permissionDenied = false

    private let center = UNUserNotificationCenter.current()

    private var pendingTexts: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: "\(personaId)_nudge_pending") as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "\(personaId)_nudge_pending") }
    }

    init(personaId: String = "keke") {
        self.personaId = personaId
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "\(personaId)_nudge_enabled")
        let saved = d.integer(forKey: "\(personaId)_nudge_per_day")
        perDay = (1...3).contains(saved) ? saved : 2
        super.init()
        center.delegate = self
    }

    // MARK: - 开关

    func enable(store: ChatStore) async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                permissionDenied = false
                enabled = true
                await refill(store: store)
            } else {
                permissionDenied = true
                enabled = false
            }
        } catch {
            enabled = false
        }
    }

    func disable() {
        enabled = false
        center.removeAllPendingNotificationRequests()
        pendingTexts = [:]
    }

    /// App 回到前台时调用：先把已经弹过的冒泡写进聊天，再补足接下来的排期
    func onAppActive(store: ChatStore) async {
        await collectDelivered(store: store)
        if enabled {
            await refill(store: store)
        }
    }

    // MARK: - 内部

    /// 把已经弹出过的通知内容写进聊天记录
    private func collectDelivered(store: ChatStore) async {
        let delivered = await center.deliveredNotifications()
        guard !delivered.isEmpty else { return }
        var pending = pendingTexts
        for note in delivered {
            let id = note.request.identifier
            guard id.hasPrefix("nudge_"), let text = pending[id] else { continue }
            store.receiveNudge(text, date: note.date)
            pending.removeValue(forKey: id)
        }
        pendingTexts = pending
        center.removeAllDeliveredNotifications()
    }

    /// 保持未来两天里有 perDay*2 条待弹出的冒泡
    private func refill(store: ChatStore) async {
        let requests = await center.pendingNotificationRequests()
        let systemIDs = Set(requests.map(\.identifier))
        var pending = pendingTexts.filter { systemIDs.contains($0.key) }

        let target = perDay * 2
        let need = target - pending.count
        guard need > 0 else {
            pendingTexts = pending
            return
        }

        guard let texts = try? await ClaudeService.generateNudges(
            messages: store.messages,
            userName: store.myName,
            personaName: PersonaStore.persona(for: personaId).name,
            provider: store.provider,
            apiKey: store.apiKey,
            model: store.model,
            systemPrompt: store.effectiveSystemPrompt,
            count: need,
            extraContext: store.memory?.contextBlock(for: nil, userName: store.myName)
        ), !texts.isEmpty else {
            pendingTexts = pending
            return
        }

        let existingDates = requests.compactMap {
            ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        }
        let dates = randomDates(count: texts.count, existing: existingDates)

        for (text, date) in zip(texts, dates) {
            let id = "nudge_\(UUID().uuidString)"
            let content = UNMutableNotificationContent()
            content.title = PersonaStore.persona(for: personaId).name
            content.body = text
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(request)
            pending[id] = text
        }
        pendingTexts = pending
    }

    /// 在接下来两天的 11:00–22:59 之间取随机时间，彼此至少隔两小时
    private func randomDates(count: Int, existing: [Date]) -> [Date] {
        let calendar = Calendar.current
        var result: [Date] = []
        var attempts = 0
        while result.count < count && attempts < 200 {
            attempts += 1
            let dayOffset = Int.random(in: 0...1)
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = Int.random(in: 11...22)
            comps.minute = Int.random(in: 0...59)
            guard let candidate = calendar.date(from: comps),
                  candidate > Date().addingTimeInterval(45 * 60) else { continue }
            let tooClose = (existing + result).contains {
                abs($0.timeIntervalSince(candidate)) < 2 * 3600
            }
            if !tooClose {
                result.append(candidate)
            }
        }
        return result
    }
}

extension NudgeService: UNUserNotificationCenterDelegate {
    /// App 在前台时也把冒泡显示成横幅
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
