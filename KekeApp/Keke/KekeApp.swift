import SwiftUI

@main
struct KekeApp: App {
    var body: some Scene {
        WindowGroup {
            AppEntryView()
        }
    }
}

struct AppEntryView: View {
    @State private var selectedPersonaId: String?

    var body: some View {
        ZStack {
            if let personaId = selectedPersonaId {
                PersonaSessionView(personaId: personaId, selectedPersonaId: $selectedPersonaId)
                    .id(personaId)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                PersonaPickerView(selectedPersonaId: $selectedPersonaId)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedPersonaId)
    }
}

struct PersonaSessionView: View {
    let personaId: String
    @Binding var selectedPersonaId: String?

    @StateObject private var memory: MemoryService
    @StateObject private var device: DeviceContextService
    @StateObject private var store: ChatStore
    @StateObject private var health = HealthService()
    @StateObject private var nudge: NudgeService
    @StateObject private var alarm = AlarmService()
    @StateObject private var cycle = CycleService()
    @StateObject private var moments: MomentsStore
    @StateObject private var petStats: PetStatsService
    @StateObject private var books: BookService
    @StateObject private var calendarService = CalendarService()
    @StateObject private var diary: DiaryService
    @StateObject private var draw: DrawService
    @StateObject private var voiceCall = VoiceCallService()
    @StateObject private var contactsStore = ContactsStore()
    @StateObject private var kekeState: KekeStateService
    @StateObject private var mcpRegistry: MCPRegistry
    @StateObject private var customProviders: CustomProviderStore
    @StateObject private var toolAPIConfig: ToolAPIConfig
    @StateObject private var activityLog: ActivityLog
    @StateObject private var anniversaries: AnniversaryStore
    @StateObject private var typingRhythm: TypingRhythm

    init(personaId: String, selectedPersonaId: Binding<String?>) {
        self.personaId = personaId
        _selectedPersonaId = selectedPersonaId

        let memory = MemoryService(personaId: personaId)
        let device = DeviceContextService()
        let moments = MomentsStore(personaId: personaId)
        let petStats = PetStatsService(personaId: personaId)
        let nudge = NudgeService(personaId: personaId)
        let diary = DiaryService(personaId: personaId)
        let books = BookService(personaId: personaId)
        let draw = DrawService(personaId: personaId)
        _memory = StateObject(wrappedValue: memory)
        _device = StateObject(wrappedValue: device)
        _moments = StateObject(wrappedValue: moments)
        _petStats = StateObject(wrappedValue: petStats)
        _nudge = StateObject(wrappedValue: nudge)
        _diary = StateObject(wrappedValue: diary)
        _books = StateObject(wrappedValue: books)
        _draw = StateObject(wrappedValue: draw)
        let kekeState = KekeStateService(personaId: personaId)
        kekeState.diary = diary
        _kekeState = StateObject(wrappedValue: kekeState)
        let mcpRegistry = MCPRegistry()
        _mcpRegistry = StateObject(wrappedValue: mcpRegistry)
        let customProviders = CustomProviderStore()
        _customProviders = StateObject(wrappedValue: customProviders)
        let toolAPIConfig = ToolAPIConfig()
        _toolAPIConfig = StateObject(wrappedValue: toolAPIConfig)
        let activityLog = ActivityLog(personaId: personaId)
        _activityLog = StateObject(wrappedValue: activityLog)
        let anniversaries = AnniversaryStore(personaId: personaId)
        _anniversaries = StateObject(wrappedValue: anniversaries)
        let typingRhythm = TypingRhythm()
        _typingRhythm = StateObject(wrappedValue: typingRhythm)
        let store = ChatStore(personaId: personaId, memory: memory, device: device, moments: moments, petStats: petStats)
        store.nudge = nudge
        store.diary = diary
        store.kekeState = kekeState
        store.mcp = mcpRegistry
        store.customProviderStore = customProviders
        store.activityLog = activityLog
        store.anniversaryStore = anniversaries
        store.typingRhythm = typingRhythm
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        RootView(selectedPersonaId: $selectedPersonaId)
            .environmentObject(store)
            .environmentObject(memory)
            .environmentObject(device)
            .environmentObject(health)
            .environmentObject(nudge)
            .environmentObject(alarm)
            .environmentObject(cycle)
            .environmentObject(moments)
            .environmentObject(petStats)
            .environmentObject(books)
            .environmentObject(calendarService)
            .environmentObject(diary)
            .environmentObject(draw)
            .environmentObject(voiceCall)
            .environmentObject(contactsStore)
            .environmentObject(kekeState)
            .environmentObject(mcpRegistry)
            .environmentObject(customProviders)
            .environmentObject(toolAPIConfig)
            .environmentObject(activityLog)
            .environmentObject(anniversaries)
            .environmentObject(typingRhythm)
    }
}
