import SwiftUI
import UserNotifications

/// 陪伴计时器引擎：开始时把结束时间写进 UserDefaults、排一条本地通知，
/// 所以退出页面、甚至杀掉 App 计时都还算数；剩余时间是按结束时间现算的。
/// 完成的统计（今天几次、共几分钟）也存在 UserDefaults，跨天自动清零
@MainActor
final class CompanionTimer: ObservableObject {
    @Published var endDate: Date?
    @Published var totalMinutes: Int = 25
    @Published var label: String = "专注"

    private let defaults = UserDefaults.standard
    static let notificationID = "keke_timer_done"

    init() {
        // 捞回上次还没走完（或走完了还没回来看）的计时
        let end = defaults.double(forKey: "timer_end_at")
        if end > 0 {
            endDate = Date(timeIntervalSince1970: end)
            totalMinutes = max(1, defaults.integer(forKey: "timer_minutes"))
            label = defaults.string(forKey: "timer_label") ?? "专注"
        }
    }

    var isRunning: Bool { endDate != nil }

    func start(minutes: Int, label: String, notificationBody: String) {
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        endDate = end
        totalMinutes = minutes
        self.label = label
        defaults.set(end.timeIntervalSince1970, forKey: "timer_end_at")
        defaults.set(minutes, forKey: "timer_minutes")
        defaults.set(label, forKey: "timer_label")

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Moonlight"
        content.body = notificationBody
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }

    /// 中途放弃：清计时、撤掉还没响的通知，不记统计
    func cancel() {
        endDate = nil
        defaults.removeObject(forKey: "timer_end_at")
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    /// 时间走完了：清计时 + 记一笔今天的统计
    func finishAndRecord() {
        let minutes = totalMinutes
        cancel()
        let dayKey = Self.dayKey(Date())
        if defaults.string(forKey: "timer_stat_day") != dayKey {
            defaults.set(dayKey, forKey: "timer_stat_day")
            defaults.set(0, forKey: "timer_stat_count")
            defaults.set(0, forKey: "timer_stat_minutes")
        }
        defaults.set(defaults.integer(forKey: "timer_stat_count") + 1, forKey: "timer_stat_count")
        defaults.set(defaults.integer(forKey: "timer_stat_minutes") + minutes, forKey: "timer_stat_minutes")
    }

    /// 今天完成了几次、一共几分钟
    func todayStats() -> (count: Int, minutes: Int) {
        guard defaults.string(forKey: "timer_stat_day") == Self.dayKey(Date()) else { return (0, 0) }
        return (defaults.integer(forKey: "timer_stat_count"),
                defaults.integer(forKey: "timer_stat_minutes"))
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// 探索页 → 陪伴计时器：番茄钟/做饭计时，克克在旁边陪着说话打气；
/// 时间到了会发通知，走完的那轮她还会在聊天里留一句话
struct CompanionTimerView: View {
    @EnvironmentObject var store: ChatStore
    @StateObject private var engine = CompanionTimer()
    @State private var pickedMinutes = 25
    @State private var pickedLabel = "专注"
    @State private var doneMessage: String?
    @State private var now = Date()

    private let labels = ["专注", "学习", "做饭", "休息"]
    private let durations = [5, 10, 15, 25, 45, 60]
    private let encouragements = [
        "我在旁边陪着呢，不许摸鱼哦",
        "*安静地趴在旁边看你*",
        "加油加油，尾巴给你摇一个",
        "你认真起来的样子很好看",
        "*偷偷瞄了你一眼又装没看*",
        "坚持住，等下奖励你摸摸头",
    ]

    private var lang: AppLanguage { store.appLanguage }
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }
    /// 秒针：存成属性，别内联在 onReceive 里（那样每次渲染都会新建一个计时器）
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            Text("⏳ " + L.t("陪伴计时器", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 14)
            Text(String(format: L.t("%@会一直陪着；时间到了会用通知喊你（记得允许通知）", lang), personaName))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 28)

            if engine.isRunning {
                runningView
            } else if let doneMessage {
                doneView(doneMessage)
            } else {
                setupView
            }

            Spacer(minLength: 0)

            statsRow
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onReceive(clock) { date in
            now = date
            checkCompletion(at: date)
        }
        .onAppear {
            // 上次开的计时在离开期间走完了：回来直接结算
            checkCompletion(at: Date())
        }
    }

    private func checkCompletion(at date: Date) {
        guard let end = engine.endDate, date >= end else { return }
        let minutes = engine.totalMinutes
        let label = engine.label
        engine.finishAndRecord()
        // 界面上先显示一句 App 口吻的事实陈述（几分钟、什么事），
        // 角色要说的那句由人设生成，回来了再补进聊天
        doneMessage = completionFact(label: label, minutes: minutes)
        Task { await announceCompletion(label: label, minutes: minutes) }
    }

    /// App 口吻的事实陈述：只说发生了什么，不带任何角色语气
    private func completionFact(label: String, minutes: Int) -> String {
        let what = label.isEmpty ? L.t("专注", lang) : label
        return L.count(minutes, "「\(what)」%d 分钟到了", "\(what): %d minutes are up", lang)
    }

    /// 角色那句话由用户自己的人设 prompt 生成。
    /// 以前是四条写死的本地模板（"效率小猫奖励你一个 *蹭蹭*"），
    /// 不但跟人设对不上，还直接以角色的名义塞进了聊天记录
    private func announceCompletion(label: String, minutes: Int) async {
        switch await GenerationFallback.run({
            try await ClaudeService.generateTimerDoneLine(
                label: label, minutes: minutes, userName: store.myName,
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt)
        }) {
        case .success(let line):
            doneMessage = line
            store.receiveNudge(line)
        case .failure(let error):
            // 生成不出来就不往聊天里塞话，只在计时器界面上说明原因
            doneMessage = completionFact(label: label, minutes: minutes)
                + "\n" + GenerationFallback.message(error)
        }
    }

    // MARK: - 选时长

    private var setupView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(labels, id: \.self) { label in
                    Button {
                        pickedLabel = label
                    } label: {
                        Text(L.t(label, lang))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(pickedLabel == label ? .white : Theme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(pickedLabel == label
                                               ? AnyShapeStyle(Theme.accent)
                                               : AnyShapeStyle(Theme.card))
                            )
                    }
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(durations, id: \.self) { minutes in
                    Button {
                        pickedMinutes = minutes
                    } label: {
                        Text(L.count(minutes, "%d 分钟", "%d min", lang))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(pickedMinutes == minutes
                                          ? AnyShapeStyle(Theme.accentLight.opacity(0.7))
                                          : AnyShapeStyle(Theme.card))
                            )
                    }
                }
            }
            .padding(.horizontal, 24)

            Button {
                doneMessage = nil
                engine.start(minutes: pickedMinutes, label: pickedLabel,
                             // 通知正文得在**开始计时**的时候就排进系统，
                             // 等不到结束时再生成，所以这里用中性的事实陈述
                             notificationBody: completionFact(label: pickedLabel, minutes: pickedMinutes))
            } label: {
                Text(L.t("开始", lang))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent))
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
        }
        .padding(.top, 10)
    }

    // MARK: - 计时中

    private var runningView: some View {
        let end = engine.endDate ?? now
        let total = TimeInterval(engine.totalMinutes * 60)
        let remaining = max(0, end.timeIntervalSince(now))
        let progress = total > 0 ? remaining / total : 0
        // 每 30 秒换一句陪伴语
        let line = encouragements[Int(now.timeIntervalSince1970 / 30) % encouragements.count]

        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Theme.backgroundDeep.opacity(0.6), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 6) {
                    Text("🦀")
                        .font(.system(size: 34))
                    Text(timeText(remaining))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L.t(engine.label, lang))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 210, height: 210)
            .padding(.top, 10)

            Text(L.t(line, lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.card.opacity(0.9)))
                .animation(.easeInOut(duration: 0.3), value: line)

            Button {
                engine.cancel()
            } label: {
                Text(L.t("先不计了", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.backgroundDeep.opacity(0.5)))
            }
        }
    }

    private func timeText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - 完成

    private func doneView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text("🎉")
                .font(.system(size: 46))
                .padding(.top, 24)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 30)
            Button {
                doneMessage = nil
            } label: {
                Text(L.t("再来一轮", lang))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.accent))
            }
        }
    }

    private var statsRow: some View {
        let stats = engine.todayStats()
        return Group {
            if stats.count > 0 {
                Text(String(format: L.t("今天陪了你 %d 次 · 共 %d 分钟", lang), stats.count, stats.minutes))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
