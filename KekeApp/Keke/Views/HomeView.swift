import SwiftUI

/// 首页：养克克 + 一眼看到的当前信息 + 各个功能模块的入口。
/// 特意做得不用上下滑动——都在一屏里
struct HomeView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var device: DeviceContextService
    @EnvironmentObject var petStats: PetStatsService
    @EnvironmentObject var kekeState: KekeStateService
    @EnvironmentObject var moments: MomentsStore
    @EnvironmentObject var health: HealthService
    @EnvironmentObject var cycle: CycleService
    @EnvironmentObject var alarm: AlarmService
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var diary: DiaryService

    @State private var activeSheet: HomeSheet?
    @State private var reminderTitles: [String] = []
    @State private var events: [DeviceContextService.TodayEvent] = []

    private var lang: AppLanguage { store.appLanguage }

    enum HomeSheet: Identifiable, Hashable {
        case moments, heartbeat, cycle, alarm, calendar, diary
        case stateDim(KekeStateDim)
        var id: Self { self }
    }

    var body: some View {
        // 状态面板上线后一屏塞不下了：改成可滚动，
        // 不然小屏上最底排的模块按钮（日历/日记）会被挤到 tab 栏底下点不到
        ScrollView {
            VStack(spacing: 12) {
                petCard
                quickInfoRow
                HStack(spacing: 10) {
                    remindersCard
                    calendarCard
                }
                moduleRow
            }
            .padding(14)
        }
        .background(Theme.background)
        .task {
            events = device.todayEvents()
            reminderTitles = await device.incompleteReminderTitles()
        }
        .slideOverCover(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .moments:
                    MomentsView().environmentObject(store).environmentObject(moments)
                case .heartbeat:
                    HealthView(switchToChat: { withAnimation { activeSheet = nil } })
                        .environmentObject(store).environmentObject(health)
                case .cycle:
                    CycleView().environmentObject(store).environmentObject(cycle)
                case .alarm:
                    AlarmView().environmentObject(store).environmentObject(alarm)
                case .calendar:
                    CalendarView().environmentObject(store).environmentObject(calendarService).environmentObject(device)
                case .diary:
                    DiaryListView()
                        .environmentObject(store).environmentObject(diary)
                case .stateDim(let dim):
                    KekeStateDetailView(dim: dim)
                        .environmentObject(store).environmentObject(kekeState)
                }
            }
            .backButtonInset { withAnimation { activeSheet = nil } }
        }
    }

    // MARK: - 养克克（Clawd 小螃蟹 + 状态面板）

    private var petCard: some View {
        VStack(spacing: 8) {
            ClawdCharacterView(mood: store.kekeMood, onInteract: { petStats.pet() })
                .scaleEffect(0.78)
                .frame(height: 98)
            HStack {
                Text("☽ " + L.t("克克的状态", lang))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                HStack(spacing: 4) {
                    fatigueIndicator
                    Text(L.t("点一条看曲线和思绪", lang))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
            }
            if let obs = kekeState.dominantObsession {
                HStack(spacing: 4) {
                    Text("💭")
                        .font(.system(size: 9))
                    Text(L.t("执念", lang) + "：" + obs.text)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.accent.opacity(0.85))
                        .lineLimit(1)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: 7) {
                ForEach(KekeStateDim.allCases) { dim in
                    Button {
                        withAnimation { activeSheet = .stateDim(dim) }
                    } label: {
                        stateBar(dim)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private func stateBar(_ dim: KekeStateDim) -> some View {
        let value = kekeState.value(dim)
        return HStack(spacing: 6) {
            Text(L.t(dim.labelKey, lang))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 42, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.backgroundDeep.opacity(0.5))
                    Capsule().fill(stateColor(dim))
                        .frame(width: geo.size.width * max(0.03, value / 100))
                }
            }
            .frame(height: 6)
            Text("\(Int(value.rounded()))")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    private func stateColor(_ dim: KekeStateDim) -> Color {
        switch dim {
        case .possess: return Theme.crabRed
        case .heat: return .orange
        case .pent: return .purple
        case .sensitive: return .mint
        case .control: return .blue
        case .soft: return .pink
        }
    }

    @ViewBuilder
    private var fatigueIndicator: some View {
        switch kekeState.fatigueState {
        case .awake:
            EmptyView()
        case .drowsy:
            Text("😪")
                .font(.system(size: 9))
        case .sleeping:
            Text("😴")
                .font(.system(size: 9))
        }
    }

    // MARK: - 当前信息一行

    private var quickInfoRow: some View {
        HStack(spacing: 10) {
            if let percent = device.batteryPercent() {
                HStack(spacing: 6) {
                    Image(systemName: batteryIcon(percent))
                        .foregroundStyle(percent <= 20 && !device.isCharging() ? .orange : Theme.textSecondary)
                    Text("\(percent)%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if device.isCharging() {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
            }
            Spacer()
            Text(Date(), style: .date)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassCard(cornerRadius: 14)
    }

    private func batteryIcon(_ percent: Int) -> String {
        switch percent {
        case ..<15: return "battery.0"
        case ..<40: return "battery.25"
        case ..<65: return "battery.50"
        case ..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    // MARK: - 提醒事项 + 日程

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(L.t("提醒事项", lang), systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            if !device.hasReminderAccess {
                Text(L.t("未开启权限", lang)).font(.caption2).foregroundStyle(Theme.textSecondary)
            } else if reminderTitles.isEmpty {
                Text(L.t("都做完啦", lang)).font(.caption2).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(reminderTitles.prefix(2), id: \.self) { title in
                    Text("· \(title)")
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 14)
    }

    private var calendarCard: some View {
        Button {
            withAnimation { activeSheet = .calendar }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Label(L.t("今天的日程", lang), systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !device.hasCalendarAccess {
                    Text(L.t("未开启权限", lang)).font(.caption2).foregroundStyle(Theme.textSecondary)
                } else if events.isEmpty {
                    Text(L.t("今天没有安排", lang)).font(.caption2).foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(events.prefix(2)) { event in
                        Text("· \(event.timeText.map { "\($0) " } ?? "")\(event.title)")
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 功能模块入口

    private var moduleRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            moduleButton(icon: "photo.on.rectangle.angled", label: "朋友圈") { withAnimation { activeSheet = .moments } }
            moduleButton(icon: "waveform.path.ecg", label: "心跳") { withAnimation { activeSheet = .heartbeat } }
            moduleButton(icon: "drop.fill", label: "经期") { withAnimation { activeSheet = .cycle } }
            moduleButton(icon: "alarm.fill", label: "闹钟") { withAnimation { activeSheet = .alarm } }
            moduleButton(icon: "calendar", label: "日历") { withAnimation { activeSheet = .calendar } }
            moduleButton(icon: "book.closed.fill", label: "日记") { withAnimation { activeSheet = .diary } }
        }
    }

    private func moduleButton(icon: String, label: String, soon: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                Text(L.t(label, lang))
                    .font(.system(size: 10))
            }
            .foregroundStyle(soon ? Theme.textSecondary.opacity(0.6) : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .glassCard(cornerRadius: 14)
        }
    }
}
