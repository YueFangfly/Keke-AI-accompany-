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
    @EnvironmentObject var mcp: MCPRegistry

    @Binding var selectedPersonaId: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: RootTab = .home
    @State private var showIncomingCall = false
    @State private var showKekeProfile = false
    @State private var showEditPersona = false
    @State private var callBlockedMessage: String?

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
                Task { await voiceCall.maybeInitiateCall(store: store) }
            }
        }
        .onChange(of: voiceCall.state) { state in
            if state == .ringing {
                showIncomingCall = true
            }
        }
        .fullScreenCover(isPresented: $showIncomingCall) {
            CallView()
                .environmentObject(store)
                .environmentObject(voiceCall)
        }
        .sheet(isPresented: $showKekeProfile) {
            KekeProfileView()
                .environmentObject(store)
                .environmentObject(contactsStore)
                .environmentObject(memory)
                .environmentObject(diary)
        }
        .sheet(isPresented: $showEditPersona) {
            EditPersonaSheet(persona: currentPersona)
        }
        .alert(L.t("现在打不了电话", store.appLanguage),
               isPresented: Binding(get: { callBlockedMessage != nil },
                                    set: { if !$0 { callBlockedMessage = nil } })) {
            Button(L.t("好", store.appLanguage), role: .cancel) {}
        } message: {
            Text(callBlockedMessage ?? "")
        }
        .simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
        .preferredColorScheme(colorScheme(for: store.appearanceMode))
        .fontDesign(store.fontDesignValue)
        .environment(\.locale, store.appLanguage == .en ? Locale(identifier: "en") : Locale(identifier: "zh-Hans"))
    }

    private func startCallIfReady() {
        var missing: [String] = []
        let lang = store.appLanguage
        if !ContactsStore.hasKey(for: store.provider) {
            missing.append(String(format: L.t("%@ 的 Key（克克想回复要用）", lang), store.provider.displayName))
        }
        if !voiceCall.configured {
            missing.append(L.t("ElevenLabs 的 Key（合成她的声音要用）", lang))
        }
        if missing.isEmpty {
            showIncomingCall = true
        } else {
            callBlockedMessage = String(format: L.t("还差：%@。去「设置」填好再来打～", lang),
                                        missing.joined(separator: "、"))
        }
    }

    private func colorScheme(for mode: String) -> ColorScheme? {
        if (AppTheme(rawValue: store.appTheme) ?? .mist).isAlwaysDark { return .dark }
        switch mode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var currentPersona: Persona {
        PersonaStore.persona(for: store.personaId)
    }

    private var topBar: some View {
        HStack {
            if tab == .home {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedPersonaId = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 16))
                        Text(L.t("切换角色", store.appLanguage))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent)
                }
                Spacer()
                Button {
                    showEditPersona = true
                } label: {
                    HStack(spacing: 4) {
                        Text(currentPersona.icon)
                            .font(.system(size: 14))
                        Text(currentPersona.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
                }
            } else if tab == .chat {
                Color.clear.frame(width: 22, height: 22)
                Spacer()
                Button {
                    showKekeProfile = true
                } label: {
                    HStack(spacing: 4) {
                        Text(contactsStore.contact("keke")?.emoji ?? "🐱")
                            .font(.system(size: 14))
                        Text(contactsStore.contact("keke")?.name ?? "克克")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                Spacer()
                Button {
                    startCallIfReady()
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accent)
                }
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
            ChatView()
        case .memory:
            MemoryView()
                .environmentObject(store)
                .environmentObject(memory)
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
                .environmentObject(mcp)
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
