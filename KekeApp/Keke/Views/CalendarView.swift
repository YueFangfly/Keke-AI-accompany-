import SwiftUI

/// 日历：一个屏幕搞定——默认月视图（今天浅色圆圈标记），点一个日期收起成周视图，
/// 下面直接跟着那天的心情/待办/聊天摘要，不用再跳到另一个页面
struct CalendarView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var device: DeviceContextService

    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var isWeekMode = false
    @State private var segment = 0
    @State private var events: [DeviceContextService.TodayEvent] = []
    @State private var reminders: [DeviceContextService.ReminderItem] = []
    @State private var summaryText: String?
    @State private var loadingSummary = false
    @State private var detectingMood = false
    // 心情手帐的草稿（跟着 selectedDate 走）
    @State private var draftMood: String?
    @State private var draftNote = ""
    @State private var tellKekeToggle = false
    @State private var savedFlash = false

    private let calendar = Calendar.current
    private let weekdaySymbolsZh = ["日", "一", "二", "三", "四", "五", "六"]
    private let weekdaySymbolsEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private var weekdaySymbols: [String] { store.appLanguage == .en ? weekdaySymbolsEn : weekdaySymbolsZh }
    private var lang: AppLanguage { store.appLanguage }
    private let moodOptions = ["😊", "🙂", "😐", "😢", "😡", "🥱"]
    /// 我的心情手帐用的大网格（参考款：16 个可选）
    private let myMoodOptions = ["😊", "🥰", "😆", "🥳", "😌", "🙂", "😐", "🤔",
                                 "🥱", "😪", "😢", "😭", "😡", "😰", "🤒", "😶‍🌫️"]

    var body: some View {
        VStack(spacing: 0) {
            calendarHeader
            ScrollView {
                VStack(spacing: 0) {
                    moodRow
                    fortuneCard
                    Picker("", selection: $segment) {
                        Text(L.t("待办", lang)).tag(0)
                        Text(L.t("聊天摘要", lang)).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    if segment == 0 {
                        todoPanel
                    } else {
                        summaryPanel
                    }
                }
            }
        }
        .background(Theme.background)
        .task(id: selectedDate) {
            events = device.events(on: selectedDate)
            reminders = await device.reminderItems(dueOn: selectedDate)
            summaryText = nil
            // 心情手帐草稿切到这一天已保存的内容
            draftMood = calendarService.myMood(on: selectedDate)
            draftNote = calendarService.note(on: selectedDate) ?? ""
            tellKekeToggle = false
            savedFlash = false
        }
    }

    // MARK: - 头部：月视图 / 周视图

    @ViewBuilder
    private var calendarHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: shiftBackward) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                }
                Spacer()
                Text(isWeekMode ? weekTitle : monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: shiftForward) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                }
            }

            HStack {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            if isWeekMode {
                weekRow
            } else {
                monthGrid
            }

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isWeekMode.toggle() }
            } label: {
                Image(systemName: isWeekMode ? "chevron.down" : "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private var weekRow: some View {
        HStack(spacing: 6) {
            ForEach(weekCells, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let myMood = calendarService.myMood(on: day)
        let kekeMood = calendarService.kekeMood(on: day)

        return Button {
            selectedDate = day
            if !isWeekMode {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isWeekMode = true }
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 1) {
                    Text(myMood ?? " ")
                    Text(kekeMood ?? "")
                }
                .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                ZStack {
                    if isSelected {
                        Circle().fill(Theme.accentLight.opacity(0.35)).frame(width: 34, height: 34)
                    }
                    if isToday {
                        Circle().stroke(Theme.accent, lineWidth: 1.5).frame(width: 34, height: 34)
                    }
                }
            )
        }
    }

    private func shiftBackward() {
        if isWeekMode {
            if let prev = calendar.date(byAdding: .day, value: -7, to: selectedDate) { selectedDate = prev }
        } else if let prev = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = prev
        }
    }

    private func shiftForward() {
        if isWeekMode {
            if let next = calendar.date(byAdding: .day, value: 7, to: selectedDate) { selectedDate = next }
        } else if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        if lang == .en {
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMMM yyyy"
        } else {
            formatter.dateFormat = "yyyy年M月"
        }
        return formatter.string(from: displayedMonth)
    }

    private var weekTitle: String {
        let formatter = DateFormatter()
        if lang == .en {
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "M月d日"
        }
        guard let first = weekCells.first, let last = weekCells.last else { return "" }
        return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
    }

    private var monthCells: [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let first = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let leadingBlanks = calendar.component(.weekday, from: first) - 1
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: first))
        }
        return cells
    }

    private var weekCells: [Date] {
        let weekday = calendar.component(.weekday, from: selectedDate)
        let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1),
                                        to: calendar.startOfDay(for: selectedDate)) ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    // MARK: - 心情打点

    private var moodRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            myMoodCard
            HStack(spacing: 18) {
                moodPicker(title: L.t("克克", lang), current: calendarService.kekeMood(on: selectedDate)) { emoji in
                    calendarService.setKekeMood(emoji, on: selectedDate)
                }
            }
            Button {
                detectingMood = true
                Task {
                    await calendarService.autoDetectMoods(for: selectedDate, store: store, options: moodOptions)
                    detectingMood = false
                }
            } label: {
                HStack(spacing: 4) {
                    if detectingMood {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(L.t("让克克看看这天心情如何", lang))
                }
                .font(.caption2)
                .foregroundStyle(Theme.accent)
            }
            .disabled(detectingMood || store.apiKey.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    /// 我的心情手帐：emoji 网格 + 一句小记 + 「顺便告诉克克」+ 保存/清除
    private var myMoodCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: L.t("%@ 这天的心情", lang), store.myName))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 6) {
                ForEach(myMoodOptions, id: \.self) { emoji in
                    Button {
                        draftMood = (draftMood == emoji) ? nil : emoji
                    } label: {
                        Text(emoji)
                            .font(.system(size: 18))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(draftMood == emoji ? Theme.accentLight.opacity(0.7) : Color.clear)
                            )
                    }
                }
            }

            TextField(L.t("这天的小记…", lang), text: $draftNote)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.backgroundDeep.opacity(0.5)))

            Toggle(isOn: $tellKekeToggle) {
                Text(L.t("顺便告诉克克", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(Theme.accent)

            HStack(spacing: 10) {
                Button {
                    saveMyDay()
                } label: {
                    Text(L.t(savedFlash ? "✓ 记好啦" : "保存这天的心情", lang))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
                }
                .disabled(draftMood == nil)
                .opacity(draftMood == nil ? 0.5 : 1)

                Button {
                    calendarService.clearMyDay(on: selectedDate)
                    draftMood = nil
                    draftNote = ""
                    savedFlash = false
                } label: {
                    Text(L.t("清除", lang))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.backgroundDeep.opacity(0.5)))
                }
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 12)
    }

    private func saveMyDay() {
        guard let mood = draftMood else { return }
        calendarService.setMyDay(mood: mood, note: draftNote, on: selectedDate)
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedFlash = false }
        if tellKekeToggle {
            let date = selectedDate
            let note = draftNote
            Task { await calendarService.tellKeke(mood: mood, note: note, date: date, store: store) }
        }
    }

    private func moodPicker(title: String, current: String?, onPick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                ForEach(moodOptions, id: \.self) { emoji in
                    Button {
                        onPick(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 16))
                            .frame(width: 26, height: 26)
                            .background(
                                Circle().fill(current == emoji ? Theme.accentLight.opacity(0.7) : Color.clear)
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassCard(cornerRadius: 12)
    }

    /// 那天如果抽过「今日小签」，同步显示在这——跟小游戏页面读的是同一份数据
    @ViewBuilder
    private var fortuneCard: some View {
        if let fortuneText = DailyFortuneStore.text(for: selectedDate) {
            HStack(alignment: .top, spacing: 8) {
                Text("🔮")
                Text(fortuneText)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(10)
            .glassCard(cornerRadius: 12)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - 待办 / 聊天摘要

    /// 待办：日程和提醒事项合在一起显示，日程在上（只读、按时间），提醒事项在下（能勾选完成）
    private var todoPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !device.hasCalendarAccess && !device.hasReminderAccess {
                Text(L.t("未开启权限", lang))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            } else if events.isEmpty && reminders.isEmpty {
                Text(L.t("这天没有安排", lang))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                if device.hasCalendarAccess && !events.isEmpty {
                    ForEach(events) { event in
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundStyle(Theme.accent)
                            Text(event.timeText.map { "\($0) " } ?? "")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                            Text(event.title)
                                .font(.caption)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                    }
                }
                if device.hasReminderAccess && !reminders.isEmpty {
                    ForEach(reminders) { reminder in
                        reminderRow(reminder)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14)
        .padding(16)
    }

    private func reminderRow(_ reminder: DeviceContextService.ReminderItem) -> some View {
        Button {
            let newValue = !reminder.isCompleted
            device.setReminderCompleted(id: reminder.id, completed: newValue)
            if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
                reminders[index].isCompleted = newValue
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reminder.isCompleted ? Theme.accent : Theme.textSecondary)
                Text(reminder.title)
                    .font(.caption)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? Theme.textSecondary : Theme.textPrimary)
                Spacer()
            }
        }
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if loadingSummary {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else if let summaryText {
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: 14)
            } else {
                Button {
                    loadingSummary = true
                    let dateAtRequest = selectedDate
                    Task {
                        let text = await calendarService.summary(for: dateAtRequest, store: store)
                        guard dateAtRequest == selectedDate else { return }
                        summaryText = text
                        loadingSummary = false
                    }
                } label: {
                    Text(L.t("生成这天的聊天摘要", lang))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
                }
                .disabled(store.apiKey.isEmpty)
            }
        }
        .padding(16)
    }
}
