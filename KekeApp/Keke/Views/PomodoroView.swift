import SwiftUI
import UserNotifications

struct PomodoroView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var activityLog: ActivityLog

    enum Phase { case idle, focus, rest, done }

    @State private var phase: Phase = .idle
    @State private var focusMinutes = 25
    @State private var restMinutes = 5
    /// 倒计时按**结束时刻**算，不按每秒减一。
    /// App 一切到后台 Timer 就冻住了，减一那套回来之后时间是错的——
    /// 而专注的时候 App 恰恰全程都在后台
    @State private var endDate: Date?
    @State private var now = Date()
    @State private var timer: Timer?
    @State private var sessionsToday = 0
    @State private var totalMinutesToday = 0
    @State private var showCustomFocus = false
    @State private var showCustomRest = false
    @State private var customFocusText = ""
    @State private var customRestText = ""
    /// 这一轮专注她要说的话。跟陪伴计时器共用一套编排
    @State private var plan: CompanionPlan?
    @State private var lineProblem: String?
    @State private var sessionToken = UUID()

    private var lang: AppLanguage { store.appLanguage }
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }
    private let focusOptions = [15, 25, 45, 60]
    private let restOptions = [5, 10, 15]

    private let octopusQuiet = ["🐙", "🫧"]
    private let octopusActive = ["🐙💨", "🐙✨", "🐙🎉"]

    @State private var octoFrame = 0

    private var secondsLeft: Int {
        guard let endDate else { return 0 }
        return max(0, Int(endDate.timeIntervalSince(now).rounded()))
    }

    /// 这一段已经过去几分钟。台词是按「第几分钟」编排的，得有这个数
    private var elapsedMinutes: Int {
        let total = phase == .rest ? restMinutes : focusMinutes
        return max(0, total - Int((Double(secondsLeft) / 60).rounded(.up)))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L.t("番茄钟", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 4)
            Text(L.t("专注的时候章鱼安静陪伴，休息的时候一起玩", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 16) {
                    octopusAnimation
                        .padding(.top, 10)

                    if phase == .idle {
                        idleControls
                    } else if phase == .done {
                        doneControls
                    } else {
                        timerDisplay
                    }

                    if sessionsToday > 0 {
                        Text(L.count(sessionsToday, "今天陪了你 %d 次 · 共 \(totalMinutesToday) 分钟",
                                      "Kept you company %d time(s) today · \(totalMinutesToday) min total", lang))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
        .onAppear { loadTodayStats() }
        // 离开页面 = 这一轮就算了。@State 随着页面一起销毁，计时本来也留不住；
        // 真正会留下的是已经排进系统的通知——那个必须一起撤掉，
        // 否则人早就走了，半小时后手机还会冒出一句「加油」
        .onDisappear { stopEverything(logAbandon: true) }
    }

    private var octopusAnimation: some View {
        VStack(spacing: 6) {
            Text(phase == .rest ? octopusActive[octoFrame % octopusActive.count] : octopusQuiet[octoFrame % octopusQuiet.count])
                .font(.system(size: 64))
                .animation(.easeInOut(duration: 0.3), value: octoFrame)

            if phase == .focus {
                focusLine
            } else if phase == .rest {
                Text(lang == .en ? "Rest time! Stretch a bit~" : "休息一下！伸个懒腰~")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    /// 专注中她"最近说过"的那句。
    ///
    /// 以前这里是六条写死的句子每 30 秒轮播一次，跟陪伴计时器里那六条一字不差——
    /// 同一段假台词复制在两个文件里。它们跟用户自己写的人设毫无关系，
    /// 「尾巴给你摇一个」放在一个没有尾巴的角色身上就是穿帮。
    /// 现在跟通知里弹的是同一句：点进来看到的就是刚才手机上那句
    @ViewBuilder private var focusLine: some View {
        if let plan {
            if let text = plan.current(elapsedMinutes: elapsedMinutes) {
                lineChip(text)
            }
        } else if let lineProblem {
            lineChip(lineProblem)
        } else {
            lineChip(L.t("正在准备这段时间要说的话…", lang))
        }
    }

    private func lineChip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .transition(.opacity)
    }

    private var idleControls: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("专注时间", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    ForEach(focusOptions, id: \.self) { m in
                        Button {
                            focusMinutes = m
                            showCustomFocus = false
                        } label: {
                            Text("\(m)" + (lang == .en ? "m" : "分"))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(focusMinutes == m && !showCustomFocus ? Theme.accent.opacity(0.2) : Color.clear)
                                .foregroundStyle(Theme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    Button {
                        showCustomFocus = true
                    } label: {
                        Text(L.t("自定义", lang))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(showCustomFocus ? Theme.accent.opacity(0.2) : Color.clear)
                            .foregroundStyle(Theme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                if showCustomFocus {
                    TextField(lang == .en ? "Minutes" : "分钟数", text: $customFocusText)
                        .keyboardType(.numberPad)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(8)
                        .glassCard(cornerRadius: 8)
                        .onChange(of: customFocusText) { v in
                            if let n = Int(v), n > 0 { focusMinutes = n }
                        }
                }
            }
            .padding(12)
            .glassCard(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("休息时间", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    ForEach(restOptions, id: \.self) { m in
                        Button {
                            restMinutes = m
                            showCustomRest = false
                        } label: {
                            Text("\(m)" + (lang == .en ? "m" : "分"))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(restMinutes == m && !showCustomRest ? Theme.accent.opacity(0.2) : Color.clear)
                                .foregroundStyle(Theme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    Button {
                        showCustomRest = true
                    } label: {
                        Text(L.t("自定义", lang))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(showCustomRest ? Theme.accent.opacity(0.2) : Color.clear)
                            .foregroundStyle(Theme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                if showCustomRest {
                    TextField(lang == .en ? "Minutes" : "分钟数", text: $customRestText)
                        .keyboardType(.numberPad)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(8)
                        .glassCard(cornerRadius: 8)
                        .onChange(of: customRestText) { v in
                            if let n = Int(v), n > 0 { restMinutes = n }
                        }
                }
            }
            .padding(12)
            .glassCard(cornerRadius: 12)

            Button {
                startFocus()
            } label: {
                Text(L.t("开始专注", lang))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var timerDisplay: some View {
        VStack(spacing: 14) {
            Text(phase == .focus ? L.t("专注中", lang) : L.t("休息中", lang))
                .font(.caption.weight(.semibold))
                .foregroundStyle(phase == .focus ? Theme.accent : Theme.textSecondary)

            Text(timeString(secondsLeft))
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)

            Button {
                stopEverything(logAbandon: true)
                phase = .idle
            } label: {
                Text(L.t("先不计了", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 16)
    }

    private var doneControls: some View {
        VStack(spacing: 14) {
            Text("🎉")
                .font(.system(size: 44))
            Text(lang == .en ? "Great job!" : "辛苦啦！")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)

            Button {
                phase = .idle
            } label: {
                Text(L.t("再来一轮", lang))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - 计时

    private func startFocus() {
        let start = Date()
        phase = .focus
        plan = nil
        lineProblem = nil
        sessionToken = UUID()
        endDate = start.addingTimeInterval(TimeInterval(focusMinutes * 60))
        now = start
        startTimer()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // 结束通知在**开始时**就排进系统。原来是等倒计时归零的那一刻才排，
        // 可 App 进了后台 Timer 根本不会走到零——通知也就永远不会响
        scheduleNotification(id: CompanionSession.pomodoro.end,
                             title: personaName,
                             body: focusDoneFact(),
                             seconds: focusMinutes * 60)
        activityLog.log(.timer, "开始了\(focusMinutes)分钟的番茄钟专注")
        Task { await prepareLines(start: start) }
    }

    private func startRest() {
        let start = Date()
        phase = .rest
        endDate = start.addingTimeInterval(TimeInterval(restMinutes * 60))
        now = start
        startTimer()
        scheduleNotification(id: CompanionSession.pomodoro.rest,
                             title: lang == .en ? "Rest is over!" : "休息结束啦！",
                             body: lang == .en ? "Time to focus again~" : "该专注啦~",
                             seconds: restMinutes * 60)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
    }

    private func tick() {
        now = Date()
        if phase == .rest { octoFrame += 1 }
        guard let end = endDate, now >= end else { return }
        timer?.invalidate()
        if phase == .focus {
            sessionsToday += 1
            totalMinutesToday += focusMinutes
            saveTodayStats()
            startRest()
        } else {
            activityLog.log(.timer, "完成了一轮番茄钟（\(focusMinutes)分钟专注+\(restMinutes)分钟休息）")
            endDate = nil
            phase = .done
        }
    }

    /// 停掉计时、撤掉所有还没响的通知，顺手把「中途跑了」记一笔。
    ///
    /// 参考 `3lmglow/Phosphene` 的账本思路：**只记成功是一本假账**。
    /// 25 分钟里第 3 分钟就退出去了，这件事比「今天专注 0 次」有信息量得多；
    /// 这里只落记录、不说任何话——刚放弃的人不需要被念叨
    private func stopEverything(logAbandon: Bool) {
        timer?.invalidate()
        timer = nil
        if logAbandon, phase == .focus {
            activityLog.log(.timer, "番茄钟中途停了，只专注了 \(elapsedMinutes) 分钟")
        }
        endDate = nil
        plan = nil
        lineProblem = nil
        sessionToken = UUID()
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: CompanionSession.pomodoro.all)
    }

    /// App 口吻的事实陈述：开始的那一刻还不知道她要说什么，先拿这句占位
    private func focusDoneFact() -> String {
        L.count(focusMinutes, "专注的 %d 分钟到了", "%d focused minutes are up", lang)
    }

    /// 按下开始之后异步生成整段台词，回来了再把中途通知排进去、
    /// 把结束那条中性通知换成她自己的话
    private func prepareLines(start: Date) async {
        let token = sessionToken
        let minutes = focusMinutes
        let checkpoints = CompanionSession.checkpoints(totalMinutes: minutes)
        let result = await GenerationFallback.run({
            try await ClaudeService.generateCompanionLines(
                // 标签原样传中文：instruction 本身是中文写的，
                // 回什么语言该由用户自己的人设决定，不该被界面语言带偏
                label: "专注", minutes: minutes, checkpoints: checkpoints,
                userName: store.myName, provider: store.provider, apiKey: store.apiKey,
                model: store.model, systemPrompt: store.effectiveSystemPrompt)
        })
        // 这中间人可能已经退出了、或者又开了新的一轮
        guard sessionToken == token, phase == .focus else { return }

        switch result {
        case .success(let raw):
            guard let made = CompanionSession.parse(raw, checkpoints: checkpoints) else {
                lineProblem = L.t("（模型没按格式回，这次中途不说话了）", lang)
                return
            }
            plan = made
            CompanionSession.schedule(made, startedAt: start, totalMinutes: minutes,
                                      title: personaName, ids: CompanionSession.pomodoro)
        case .failure(let error):
            lineProblem = GenerationFallback.message(error)
        }
    }

    private func timeString(_ total: Int) -> String {
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// 固定 id：撤销的时候要找得回来。原来用的是随机 UUID，
    /// 排进去就再也撤不掉了——按了「先不计了」，通知照样会响
    private func scheduleNotification(id: String, title: String, body: String, seconds: Int) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(seconds), repeats: false)
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private var statsKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "pomodoro_\(f.string(from: Date()))"
    }

    private func loadTodayStats() {
        let dict = UserDefaults.standard.dictionary(forKey: statsKey) as? [String: Int] ?? [:]
        sessionsToday = dict["sessions"] ?? 0
        totalMinutesToday = dict["minutes"] ?? 0
    }

    private func saveTodayStats() {
        let dict: [String: Int] = ["sessions": sessionsToday, "minutes": totalMinutesToday]
        UserDefaults.standard.set(dict, forKey: statsKey)
    }
}
