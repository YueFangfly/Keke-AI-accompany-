import SwiftUI
import UserNotifications

/// 陪伴计时器引擎：开始时把结束时间写进 UserDefaults、排一串本地通知，
/// 所以退出页面、甚至杀掉 App 计时都还算数；剩余时间是按结束时间现算的。
/// 完成的统计（今天几次、共几分钟）也存在 UserDefaults，跨天自动清零
@MainActor
final class CompanionTimer: ObservableObject {
    @Published var endDate: Date?
    @Published var totalMinutes: Int = 25
    @Published var label: String = "专注"

    /// 这一轮她要说的话。台词是异步生成的，回来了再填进来
    @Published private(set) var plan: CompanionPlan?
    /// 台词没生成出来的原因。**不拿假话顶上**，直接把原因摆在界面上
    @Published private(set) var lineProblem: String?
    /// 每次 start 换一个。台词生成得慢，回来的时候可能已经是下一轮了，
    /// 靠它认出「这批台词是上一轮的」然后丢掉
    @Published private(set) var sessionToken = UUID()

    private let defaults = UserDefaults.standard

    init() {
        // 捞回上次还没走完（或走完了还没回来看）的计时
        let end = defaults.double(forKey: "timer_end_at")
        if end > 0 {
            endDate = Date(timeIntervalSince1970: end)
            totalMinutes = max(1, defaults.integer(forKey: "timer_minutes"))
            label = defaults.string(forKey: "timer_label") ?? "专注"
            // 台词也一起捞回来：App 被杀掉再打开，中途通知照样会弹，
            // 界面上却空着一块会很怪——她"说过"的话应该还在
            if let data = defaults.data(forKey: "timer_plan") {
                plan = try? JSONDecoder().decode(CompanionPlan.self, from: data)
            }
        }
    }

    var isRunning: Bool { endDate != nil }

    /// 这一轮是什么时候开始的。台词按「第几分钟」编排，得有个原点
    var startDate: Date? {
        endDate?.addingTimeInterval(-TimeInterval(totalMinutes * 60))
    }

    func start(minutes: Int, label: String, title: String, notificationBody: String) {
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        endDate = end
        totalMinutes = minutes
        self.label = label
        plan = nil
        lineProblem = nil
        sessionToken = UUID()
        defaults.set(end.timeIntervalSince1970, forKey: "timer_end_at")
        defaults.set(minutes, forKey: "timer_minutes")
        defaults.set(label, forKey: "timer_label")
        defaults.removeObject(forKey: "timer_plan")

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        // 这里只能用中性的事实陈述：按下开始的这一刻还不知道她要说什么。
        // 台词生成回来之后 `CompanionSession.schedule` 会用同一个 id 覆盖掉它
        content.body = notificationBody
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        center.add(UNNotificationRequest(identifier: CompanionSession.timer.end,
                                         content: content, trigger: trigger))
    }

    /// 台词到手了
    func apply(_ plan: CompanionPlan) {
        self.plan = plan
        lineProblem = nil
        if let data = try? JSONEncoder().encode(plan) {
            defaults.set(data, forKey: "timer_plan")
        }
    }

    func noteLineProblem(_ reason: String) {
        lineProblem = reason
    }

    /// 清计时、撤掉所有还没响的通知。**中途那几条也要撤**——
    /// 人都退出了还在后台弹「加油」是最招人烦的一种 bug
    func cancel() {
        endDate = nil
        plan = nil
        lineProblem = nil
        defaults.removeObject(forKey: "timer_end_at")
        defaults.removeObject(forKey: "timer_plan")
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: CompanionSession.timer.all)
    }

    /// 中途放弃。返回已经坚持了多少分钟。
    ///
    /// 参考 `3lmglow/Phosphene` 的账本思路：**只记成功是一本假账**。
    /// 25 分钟里第 3 分钟就跑掉了，这件事比「今天专注 0 次」有信息量得多。
    /// 这里只算分钟数、不说任何话——刚放弃的人不需要被念叨，
    /// 落进活动记录就够了，她以后想提起来的时候有据可查
    func abandon() -> Int {
        let elapsed = startDate.map { Int(Date().timeIntervalSince($0) / 60) } ?? 0
        cancel()
        return max(0, min(elapsed, totalMinutes))
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

/// 探索页 → 陪伴计时器：番茄钟/做饭计时，克克在旁边陪着；
/// 中途会开口、时间到了会发通知，走完的那轮还会在聊天里留一句话
struct CompanionTimerView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var activityLog: ActivityLog
    @StateObject private var engine = CompanionTimer()
    @State private var pickedMinutes = 25
    @State private var pickedLabel = "专注"
    @State private var doneMessage: String?
    @State private var now = Date()

    private let labels = ["专注", "学习", "做饭", "休息"]
    private let durations = [5, 10, 15, 25, 45, 60]

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
            Text(String(format: L.t("%@会一直陪着，中途也会说话；记得允许通知，不然她喊不到你", lang), personaName))
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
        // 结束那句要在 finishAndRecord 之前拿走——那一步会把台词表清掉
        let ending = engine.plan?.endingLine
        engine.finishAndRecord()
        activityLog.log(.timer, "陪着完成了「\(label)」\(minutes) 分钟")
        // 界面上先显示一句 App 口吻的事实陈述（几分钟、什么事），
        // 角色要说的那句由人设生成，回来了再补进聊天
        doneMessage = completionFact(label: label, minutes: minutes)
        Task { await announceCompletion(label: label, minutes: minutes, ending: ending) }
    }

    /// App 口吻的事实陈述：只说发生了什么，不带任何角色语气
    private func completionFact(label: String, minutes: Int) -> String {
        let what = label.isEmpty ? L.t("专注", lang) : label
        return L.count(minutes, "「\(what)」%d 分钟到了", "\(what): %d minutes are up", lang)
    }

    /// 角色那句话由用户自己的人设 prompt 生成。
    /// 以前是四条写死的本地模板（"效率小猫奖励你一个 *蹭蹭*"），
    /// 不但跟人设对不上，还直接以角色的名义塞进了聊天记录。
    ///
    /// 现在优先用开始时就生成好的那句：**通知里弹的和界面上写的是同一句话**。
    /// 只有开始时没生成成功（断网、Key 不对）才在这里再试一次
    private func announceCompletion(label: String, minutes: Int, ending: String?) async {
        if let ending {
            doneMessage = ending
            store.receiveNudge(ending)
            return
        }
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

    /// 按下开始之后异步生成整段台词。
    ///
    /// 先让计时跑起来、别让人对着转圈等 API；台词回来了再把中途通知排进去、
    /// 把结束那条中性通知换成她自己的话
    private func prepareLines(label: String, minutes: Int) async {
        let token = engine.sessionToken
        let checkpoints = CompanionSession.checkpoints(totalMinutes: minutes)
        let startedAt = engine.startDate ?? Date()
        let result = await GenerationFallback.run({
            try await ClaudeService.generateCompanionLines(
                label: label, minutes: minutes, checkpoints: checkpoints,
                userName: store.myName, provider: store.provider, apiKey: store.apiKey,
                model: store.model, systemPrompt: store.effectiveSystemPrompt)
        })
        // 这中间人可能已经取消了、或者又开了新的一轮
        guard engine.isRunning, engine.sessionToken == token else { return }

        switch result {
        case .success(let raw):
            guard let plan = CompanionSession.parse(raw, checkpoints: checkpoints) else {
                engine.noteLineProblem(L.t("（模型没按格式回，这次中途不说话了）", lang))
                return
            }
            engine.apply(plan)
            CompanionSession.schedule(plan, startedAt: startedAt, totalMinutes: minutes,
                                      title: personaName, ids: CompanionSession.timer)
        case .failure(let error):
            engine.noteLineProblem(GenerationFallback.message(error))
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
                let minutes = pickedMinutes
                let label = pickedLabel
                engine.start(minutes: minutes, label: label, title: personaName,
                             // 通知正文得在**开始计时**的时候就排进系统，
                             // 等不到结束时再生成，所以这里先用中性的事实陈述占位
                             notificationBody: completionFact(label: label, minutes: minutes))
                activityLog.log(.timer, "开始了\(minutes)分钟的「\(label)」陪伴计时")
                Task { await prepareLines(label: label, minutes: minutes) }
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

            companionLine

            Button {
                // 标签要在 abandon 之前拿：那一步之后引擎已经不是这一轮了
                let label = engine.label
                let kept = engine.abandon()
                activityLog.log(.timer, "「\(label)」中途停了，只坚持了 \(kept) 分钟")
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

    /// 她此刻"最近说过"的那句。
    ///
    /// **界面和通知说的是同一句**：通知在第 12 分钟弹了什么，
    /// 人点进来看到的就还是那句，不是另一条随机语录。
    /// 以前这里是六条写死的句子每 30 秒轮播一次——它们跟用户自己写的人设毫无关系，
    /// 「尾巴给你摇一个」在一个没有尾巴的角色身上就是穿帮
    @ViewBuilder private var companionLine: some View {
        if let plan = engine.plan {
            if let text = plan.current(elapsedMinutes: elapsedMinutes) {
                lineChip(text)
            }
        } else if let problem = engine.lineProblem {
            lineChip(problem)
        } else {
            lineChip(L.t("正在准备这段时间要说的话…", lang))
        }
    }

    private var elapsedMinutes: Int {
        guard let start = engine.startDate else { return 0 }
        return max(0, Int(now.timeIntervalSince(start) / 60))
    }

    private func lineChip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.card.opacity(0.9)))
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.3), value: text)
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
