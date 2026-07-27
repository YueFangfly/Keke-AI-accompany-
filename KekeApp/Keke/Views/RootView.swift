import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var memory: MemoryService
    @EnvironmentObject var device: DeviceContextService
    @EnvironmentObject var health: HealthService
    @EnvironmentObject var nudge: NudgeService
    @EnvironmentObject var alarm: AlarmService
    @EnvironmentObject var cycle: CycleService
    @EnvironmentObject var moments: MomentsStore
    @EnvironmentObject var petStats: PetStatsService
    @EnvironmentObject var books: BookService
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var diary: DiaryService
    @EnvironmentObject var draw: DrawService
    @EnvironmentObject var voiceCall: VoiceCallService
    @EnvironmentObject var contactsStore: ContactsStore
    @EnvironmentObject var kekeState: KekeStateService

    @Binding var hasEnteredApp: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: RootTab = .home

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
            BottomTabBar(tab: $tab, language: store.appLanguage)
        }
        .background(Theme.background.ignoresSafeArea())
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
        .simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
        .preferredColorScheme(colorScheme(for: store.appearanceMode))
        .fontDesign(store.fontDesignValue)
        .environment(\.locale, store.appLanguage == .en ? Locale(identifier: "en") : Locale(identifier: "zh-Hans"))
    }

    private func colorScheme(for mode: String) -> ColorScheme? {
        if (AppTheme(rawValue: store.appTheme) ?? .mist).isAlwaysDark { return .dark }
        switch mode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var topBar: some View {
        HStack {
            if tab == .home {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasEnteredApp = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 16))
                        Text(L.t("切换模型", store.appLanguage))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent)
                }
                Spacer()
                Text(currentModelName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(title(for: tab))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Theme.background)
    }

    private var currentModelName: String {
        if let cid = store.activeCustomProviderId,
           let custom = store.customProviders.first(where: { $0.id == cid }) {
            return custom.name
        }
        return store.provider.displayName
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
