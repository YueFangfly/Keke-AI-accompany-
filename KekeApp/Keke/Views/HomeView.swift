import SwiftUI

/// 首页：养克克 + 一眼看到的当前信息 + 各个功能模块的入口。
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
    @State private var showAllDims = false
    @State private var showDimEditor = false

    private var lang: AppLanguage { store.appLanguage }
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }

    enum HomeSheet: Identifiable, Hashable {
        case moments, heartbeat, cycle, alarm, calendar, diary
        case stateDim(String)
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
        .sheet(isPresented: $showDimEditor) {
            DimEditorSheet()
                .environmentObject(kekeState)
                .environmentObject(store)
        }
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
                case .stateDim(let dimKey):
                    KekeStateDetailView(dimKey: dimKey)
                        .environmentObject(store).environmentObject(kekeState)
                }
            }
            .backButtonInset { withAnimation { activeSheet = nil } }
        }
    }

    // MARK: - 养克克（角色 + 状态面板）

    private static let dimPalette: [Color] = [
        Theme.crabRed, .orange, .blue, .pink, .mint, .purple,
        .cyan, .green, .yellow, .indigo, .teal, .brown,
        .red.opacity(0.7), .blue.opacity(0.7), .orange.opacity(0.7), .green.opacity(0.7),
    ]

    private var petCard: some View {
        VStack(spacing: 8) {
            characterView
                .scaleEffect(0.78)
                .frame(height: 98)
            HStack {
                Text(String(format: L.t("%@的状态", lang), personaName))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    showDimEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent.opacity(0.7))
                }
                .buttonStyle(.plain)
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

            let pinned = kekeState.pinnedDimConfigs
            if !pinned.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          alignment: .leading, spacing: 7) {
                    ForEach(pinned) { config in
                        Button {
                            withAnimation { activeSheet = .stateDim(config.dimKey) }
                        } label: {
                            stateBar(config)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let hasExpanded = kekeState.expandedDimConfigs.count > pinned.count
            if hasExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showAllDims.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAllDims ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                        Text(showAllDims ? L.t("收起", lang) : L.t("点击查看更多", lang))
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(Theme.accent.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)

                if showAllDims {
                    expandedDimPanel
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    @ViewBuilder
    private var expandedDimPanel: some View {
        let pinnedKeys = Set(kekeState.pinnedDimConfigs.map(\.dimKey))
        let states = kekeState.stateConfigs.filter { !pinnedKeys.contains($0.dimKey) }
        let drives = kekeState.driveConfigs.filter { !pinnedKeys.contains($0.dimKey) }

        VStack(alignment: .leading, spacing: 6) {
            if !states.isEmpty {
                Text(L.t("状态", lang))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          alignment: .leading, spacing: 7) {
                    ForEach(states) { config in
                        Button {
                            withAnimation { activeSheet = .stateDim(config.dimKey) }
                        } label: {
                            stateBar(config)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !drives.isEmpty {
                Text(L.t("驱力", lang))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .padding(.top, 4)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          alignment: .leading, spacing: 7) {
                    ForEach(drives) { config in
                        Button {
                            withAnimation { activeSheet = .stateDim(config.dimKey) }
                        } label: {
                            stateBar(config)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func stateBar(_ config: StateDimConfig) -> some View {
        let val = kekeState.value(forKey: config.dimKey)
        return HStack(spacing: 6) {
            Text(L.t(config.label, lang))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 42, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.backgroundDeep.opacity(0.5))
                    Capsule().fill(dimColor(config.dimKey))
                        .frame(width: geo.size.width * max(0.03, val / 100))
                }
            }
            .frame(height: 6)
            Text("\(Int(val.rounded()))")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    private func dimColor(_ dimKey: String) -> Color {
        guard let idx = kekeState.dimConfigs.firstIndex(where: { $0.dimKey == dimKey }) else {
            return Theme.accent
        }
        return Self.dimPalette[idx % Self.dimPalette.count]
    }

    @ViewBuilder
    private var characterView: some View {
        let charType = UserDefaults.standard.string(forKey: "\(store.personaId)_character_type")
            ?? PersonaStore.persona(for: store.personaId).characterType
        switch charType {
        case "octo":
            OctoCharacterView(mood: store.kekeMood, onInteract: { petStats.pet() })
        default:
            ClawdCharacterView(mood: store.kekeMood, onInteract: { petStats.pet() })
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

// MARK: - 状态面板编辑器

struct DimEditorSheet: View {
    @EnvironmentObject var kekeState: KekeStateService
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAddDim = false
    @State private var newDimName = ""
    @State private var newDimCategory: DimCategory = .state

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        NavigationView {
            List {
                let states = kekeState.dimConfigs.filter { $0.category == .state }
                let drives = kekeState.dimConfigs.filter { $0.category == .drive }

                if !states.isEmpty {
                    Section(header: Text(L.t("状态", lang))) {
                        ForEach(kekeState.dimConfigs.indices, id: \.self) { idx in
                            if kekeState.dimConfigs[idx].category == .state {
                                dimRow(index: idx)
                            }
                        }
                    }
                }
                if !drives.isEmpty {
                    Section(header: Text(L.t("驱力", lang))) {
                        ForEach(kekeState.dimConfigs.indices, id: \.self) { idx in
                            if kekeState.dimConfigs[idx].category == .drive {
                                dimRow(index: idx)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showAddDim = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Theme.accent)
                            Text(L.t("添加状态", lang))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                } footer: {
                    let pinnedCount = kekeState.dimConfigs.filter { $0.pinned && $0.enabled }.count
                    let totalCount = kekeState.dimConfigs.filter(\.enabled).count
                    Text(L.t("开关控制是否启用；📌 控制是否在首页置顶显示", lang)
                         + "\n" + String(format: L.t("置顶 %d / 共 %d", lang), pinnedCount, totalCount))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L.t("状态面板", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L.t("完成", lang)) { dismiss() }
                }
            }
            .alert(L.t("添加状态", lang), isPresented: $showAddDim) {
                TextField(L.t("名称", lang), text: $newDimName)
                Button(L.t("状态", lang)) { addDim(category: .state) }
                Button(L.t("驱力", lang)) { addDim(category: .drive) }
                Button(L.t("取消", lang), role: .cancel) { newDimName = "" }
            } message: {
                Text(L.t("输入名称并选择类型", lang))
            }
        }
    }

    private func dimRow(index idx: Int) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: $kekeState.dimConfigs[idx].enabled) {
                TextField("", text: $kekeState.dimConfigs[idx].label)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
            Button {
                kekeState.dimConfigs[idx].pinned.toggle()
            } label: {
                Image(systemName: kekeState.dimConfigs[idx].pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundStyle(kekeState.dimConfigs[idx].pinned ? Theme.accent : Theme.textSecondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!kekeState.dimConfigs[idx].enabled)
            Button(role: .destructive) {
                kekeState.removeDim(forKey: kekeState.dimConfigs[idx].dimKey)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private func addDim(category: DimCategory) {
        let name = newDimName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { newDimName = ""; return }
        let key = "custom_\(UUID().uuidString.prefix(8))"
        let config = StateDimConfig(
            dimKey: key,
            label: name,
            category: category,
            defaultValue: 50,
            growPerHour: category == .drive ? 2.0 : 0,
            pinned: true,
            enabled: true
        )
        kekeState.addDim(config)
        newDimName = ""
    }
}
