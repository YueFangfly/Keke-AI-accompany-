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

    @State private var hasEnteredApp = false

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
        ZStack {
            if hasEnteredApp {
                RootView(hasEnteredApp: $hasEnteredApp)
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
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ModelPickerView(hasEnteredApp: $hasEnteredApp)
                    .environmentObject(store)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasEnteredApp)
    }
}
