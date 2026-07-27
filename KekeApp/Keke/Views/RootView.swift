import SwiftUI
import UIKit

struct RootView: View {
    @StateObject private var memory: MemoryService
    @StateObject private var device: DeviceContextService
    @StateObject private var store: ChatStore
    @StateObject private var health = HealthService()
    @StateObject private var nudge: NudgeService
    @StateObject private var alarm = AlarmService()
    @StateObject private var cycle = CycleService()
    @StateObject private var moments: MomentsStore
    @StateObject private var petStats: PetStatsService
    @StateObject private var books = BookService()
    @StateObject private var calendarService = CalendarService()
    @StateObject private var diary: DiaryService
    @StateObject private var draw = DrawService()
    @StateObject private var voiceCall = VoiceCallService()
    @StateObject private var contactsStore = ContactsStore()
    @StateObject private var kekeState: KekeStateService
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: RootTab = .home

    init() {
        let memory = MemoryService()
        let device = DeviceContextService()
        let moments = MomentsStore()
        let petStats = PetStatsService()
        let nudge = NudgeService()
        let diary = DiaryService()
        _memory = StateObject(wrappedValue: memory)
        _device = StateObject(wrappedValue: device)
        _moments = StateObject(wrappedValue: moments)
        _petStats = StateObject(wrappedValue: petStats)
        _nudge = StateObject(wrappedValue: nudge)
        _diary = StateObject(wrappedValue: diary)
        let kekeState = KekeStateService()
        kekeState.diary = diary
        _kekeState = StateObject(wrappedValue: kekeState)
        let store = ChatStore(memory: memory, device: device, moments: moments, petStats: petStats)
        store.nudge = nudge
        store.diary = diary
        store.kekeState = kekeState
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
            BottomTabBar(tab: $tab, language: store.appLanguage)
        }
        .background(Theme.background.ignoresSafeArea())
        // 底部导航栏不要跟着键盘跑；聊天页自己算了输入框要跟键盘走多少
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                kekeState.applyDrift()
                Task { await nudge.onAppActive(store: store) }
                Task { await store.kekeSpeaksFirstIfNeeded() }
                Task { await moments.checkPendingReactions(store: store, friends: contactsStore.friends) }
                Task { await books.maybeReadAlong(store: store) }
                Task { await diary.maybeWriteKekeDiary(store: store, petStats: petStats, moments: moments) }
                Task { await diary.maybeReadMyDiary(store: store) }
                Task { await diary.maybeReplyToComments(store: store) }
                Task { await memory.maybeRunWeeklyMaintenance(store: store) }
            }
        }
        // 点输入框以外的任何地方都收起键盘
        .simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
        .preferredColorScheme(colorScheme(for: store.appearanceMode))
        .fontDesign(store.fontDesignValue)
        .environment(\.locale, store.appLanguage == .en ? Locale(identifier: "en") : Locale(identifier: "zh-Hans"))
    }

    private func colorScheme(for mode: String) -> ColorScheme? {
        // 深海/星夜这类天生的深色主题：整个 App 锁深色，毛玻璃材质才会渲染成暗色
        if (AppTheme(rawValue: store.appTheme) ?? .mist).isAlwaysDark { return .dark }
        switch mode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var topBar: some View {
        HStack {
            Text(title(for: tab))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.background)
    }

    private func title(for tab: RootTab) -> String {
        let key: String
        switch tab {
        case .chat: key = "聊天"
        case .memory: key = "记忆"
        case .home: key = "首页"
        case .explore: key = "探索"
        case .settings: key = "设置"
        }
        return L.t(key, store.appLanguage)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .chat:
            ChatListView()
                .environmentObject(store)
                .environmentObject(contactsStore)
                .environmentObject(memory)
                .environmentObject(voiceCall)
                .environmentObject(diary)
        case .memory:
            MemoryView()
                .environmentObject(store)
                .environmentObject(memory)
                .environmentObject(contactsStore)
        case .home:
            HomeView()
                .environmentObject(store)
                .environmentObject(device)
                .environmentObject(petStats)
                .environmentObject(kekeState)
                .environmentObject(moments)
                .environmentObject(contactsStore)
                .environmentObject(health)
                .environmentObject(cycle)
                .environmentObject(alarm)
                .environmentObject(calendarService)
                .environmentObject(diary)
        case .explore:
            ExploreView()
                .environmentObject(store)
                .environmentObject(books)
                .environmentObject(draw)
        case .settings:
            SettingsView()
                .environmentObject(store)
                .environmentObject(nudge)
                .environmentObject(device)
                .environmentObject(memory)
                .environmentObject(diary)
                .environmentObject(voiceCall)
        }
    }
}
