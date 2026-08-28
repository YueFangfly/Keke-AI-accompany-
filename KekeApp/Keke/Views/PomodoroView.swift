import SwiftUI
import UserNotifications

struct PomodoroView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var activityLog: ActivityLog

    enum Phase { case idle, focus, rest, done }

    @State private var phase: Phase = .idle
    @State private var focusMinutes = 25
    @State private var restMinutes = 5
    @State private var secondsLeft = 0
    @State private var timer: Timer?
    @State private var sessionsToday = 0
    @State private var totalMinutesToday = 0
    @State private var showCustomFocus = false
    @State private var showCustomRest = false
    @State private var customFocusText = ""
    @State private var customRestText = ""

    private var lang: AppLanguage { store.appLanguage }
    private let focusOptions = [15, 25, 45, 60]
    private let restOptions = [5, 10, 15]

    private let octopusQuiet = ["🐙", "🫧"]
    private let octopusActive = ["🐙💨", "🐙✨", "🐙🎉"]

    @State private var octoFrame = 0

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
        .onDisappear { timer?.invalidate() }
    }

    private var octopusAnimation: some View {
        VStack(spacing: 6) {
            Text(phase == .rest ? octopusActive[octoFrame % octopusActive.count] : octopusQuiet[octoFrame % octopusQuiet.count])
                .font(.system(size: 64))
                .animation(.easeInOut(duration: 0.3), value: octoFrame)

            if phase == .focus {
                let lines = [
                    L.t("我在旁边陪着呢，不许摸鱼哦", lang),
                    L.t("*安静地趴在旁边看你*", lang),
                    L.t("加油加油，尾巴给你摇一个", lang),
                    L.t("你认真起来的样子很好看", lang),
                    L.t("*偷偷瞄了你一眼又装没看*", lang),
                    L.t("坚持住，等下奖励你摸摸头", lang),
                ]
                Text(lines[(secondsLeft / 30) % lines.count])
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            } else if phase == .rest {
                Text(lang == .en ? "Rest time! Stretch a bit~" : "休息一下！伸个懒腰~")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
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
                cancelTimer()
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

    private func startFocus() {
        phase = .focus
        secondsLeft = focusMinutes * 60
        startTimer()
        activityLog.log(.timer, "开始了\(focusMinutes)分钟的番茄钟专注")
    }

    private func startRest() {
        phase = .rest
        secondsLeft = restMinutes * 60
        startTimer()
        scheduleNotification(title: lang == .en ? "Rest is over!" : "休息结束啦！",
                            body: lang == .en ? "Time to focus again~" : "该专注啦~",
                            seconds: restMinutes * 60)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if secondsLeft > 0 {
                    secondsLeft -= 1
                    if phase == .rest { octoFrame += 1 }
                } else {
                    timer?.invalidate()
                    if phase == .focus {
                        sessionsToday += 1
                        totalMinutesToday += focusMinutes
                        saveTodayStats()
                        scheduleNotification(
                            title: lang == .en ? "Focus complete!" : "专注结束！",
                            body: lang == .en ? "Time to rest~" : "休息一下吧~",
                            seconds: 0)
                        startRest()
                    } else {
                        activityLog.log(.timer, "完成了一轮番茄钟（\(focusMinutes)分钟专注+\(restMinutes)分钟休息）")
                        phase = .done
                    }
                }
            }
        }
    }

    private func cancelTimer() {
        timer?.invalidate()
        phase = .idle
    }

    private func timeString(_ total: Int) -> String {
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func scheduleNotification(title: String, body: String, seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = seconds > 0
            ? UNTimeIntervalNotificationTrigger(timeInterval: Double(seconds), repeats: false)
            : nil
        let request = UNNotificationRequest(identifier: "pomodoro_\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
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
