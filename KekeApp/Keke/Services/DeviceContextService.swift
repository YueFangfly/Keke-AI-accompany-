import Foundation
import UIKit
import CoreLocation
import EventKit
import HealthKit

/// 克克能看到的本机状态：电池、步数、大概位置、今天的日程、提醒事项。
/// 每一项都有 App 内开关，开了才请求系统权限、才随聊天发给克克。
final class DeviceContextService: NSObject, ObservableObject, CLLocationManagerDelegate {

    let personaId: String

    @Published var batteryEnabled: Bool = false {
        didSet { UserDefaults.standard.set(batteryEnabled, forKey: "\(personaId)_ctx_battery") }
    }
    @Published var stepsEnabled: Bool = false {
        didSet { UserDefaults.standard.set(stepsEnabled, forKey: "\(personaId)_ctx_steps") }
    }
    @Published var locationEnabled: Bool = false {
        didSet { UserDefaults.standard.set(locationEnabled, forKey: "\(personaId)_ctx_location") }
    }
    @Published var calendarEnabled: Bool = false {
        didSet { UserDefaults.standard.set(calendarEnabled, forKey: "\(personaId)_ctx_calendar") }
    }
    @Published var remindersEnabled: Bool = false {
        didSet { UserDefaults.standard.set(remindersEnabled, forKey: "\(personaId)_ctx_reminders") }
    }

    private let locationManager = CLLocationManager()
    private let eventStore = EKEventStore()
    private let healthStore = HKHealthStore()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    init(personaId: String = "keke") {
        self.personaId = personaId
        super.init()
        let ud = UserDefaults.standard
        batteryEnabled = (ud.object(forKey: "\(personaId)_ctx_battery") as? Bool)
            ?? ud.bool(forKey: "ctx_battery")
        stepsEnabled = (ud.object(forKey: "\(personaId)_ctx_steps") as? Bool)
            ?? ud.bool(forKey: "ctx_steps")
        locationEnabled = (ud.object(forKey: "\(personaId)_ctx_location") as? Bool)
            ?? ud.bool(forKey: "ctx_location")
        calendarEnabled = (ud.object(forKey: "\(personaId)_ctx_calendar") as? Bool)
            ?? ud.bool(forKey: "ctx_calendar")
        remindersEnabled = (ud.object(forKey: "\(personaId)_ctx_reminders") as? Bool)
            ?? ud.bool(forKey: "ctx_reminders")
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: - 开关（打开时顺便请求系统权限）

    func setLocation(enabled: Bool) {
        locationEnabled = enabled
        if enabled, locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func setCalendar(enabled: Bool) {
        calendarEnabled = enabled
        if enabled, EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            Task { _ = try? await eventStore.requestAccess(to: .event) }
        }
    }

    func setReminders(enabled: Bool) {
        remindersEnabled = enabled
        if enabled, EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            Task { _ = try? await eventStore.requestAccess(to: .reminder) }
        }
    }

    /// 老接口的 authorized（rawValue 3）在 iOS 17+ 上就是 fullAccess，
    /// 老 SDK 编译的 App 系统会自动走兼容行为，所以只判断这个就够了
    private func hasEventAccess(_ type: EKEntityType) -> Bool {
        EKEventStore.authorizationStatus(for: type) == .authorized
    }

    // MARK: - 汇总给克克的状态块

    func contextBlock(userName: String = "wifey") async -> String? {
        var lines: [String] = []

        if batteryEnabled, let battery = batteryLine() { lines.append(battery) }
        if stepsEnabled, let steps = await stepsLine() { lines.append(steps) }
        if locationEnabled, let place = await locationLine() { lines.append(place) }
        if calendarEnabled, let events = calendarLine() { lines.append(events) }
        if remindersEnabled, let todos = await remindersLine() { lines.append(todos) }

        guard !lines.isEmpty else { return nil }
        return "\(userName) 现在的状态（她在设置里允许你看到的，自然地留意，不用逐条复述）：\n"
            + lines.map { "- " + $0 }.joined(separator: "\n")
    }

    // MARK: - 各项采集

    private func batteryLine() -> String? {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        guard level >= 0 else { return nil }
        let percent = Int(level * 100)
        let charging = device.batteryState == .charging || device.batteryState == .full
        var line = "手机电量 \(percent)%\(charging ? "（在充电）" : "")"
        if percent <= 20 && !charging { line += "，有点低了" }
        return line
    }

    private func stepsLine() async -> String? {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let steps: Double? = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type,
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()))
            }
            healthStore.execute(query)
        }
        guard let steps else { return nil }
        return "今天走了 \(Int(steps)) 步"
    }

    private func locationLine() async -> String? {
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        guard let location = await currentLocation() else { return nil }
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let mark = placemarks?.first else { return nil }
        let place = [mark.locality, mark.subLocality].compactMap { $0 }.joined(separator: "")
        guard !place.isEmpty else { return nil }
        return "现在大概在 \(place)"
    }

    private func currentLocation() async -> CLLocation? {
        if let cached = locationManager.location,
           cached.timestamp > Date().addingTimeInterval(-600) {
            return cached
        }
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locationContinuation?.resume(returning: locations.first)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }

    private func calendarLine() -> String? {
        guard hasEventAccess(.event) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return nil }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate).prefix(5)
        guard !events.isEmpty else { return "今天日历上没有安排" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let items = events.map { event in
            let title = event.title ?? "（无标题）"
            return event.isAllDay ? title : "\(formatter.string(from: event.startDate)) \(title)"
        }
        return "今天的日程：" + items.joined(separator: "、")
    }

    private func remindersLine() async -> String? {
        guard hasEventAccess(.reminder) else { return nil }
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: Date().addingTimeInterval(7 * 86400),
            calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }
        let items = reminders.prefix(5).compactMap { $0.title }
        guard !items.isEmpty else { return nil }
        return "没做完的提醒事项：" + items.joined(separator: "、")
    }

    // MARK: - 写：克克在聊天里帮忙建提醒/日程（工具调用）

    /// 没请求过权限就现场请求一次；被拒绝过就直接失败（引导去系统设置开）
    private func ensureEventAccess(_ type: EKEntityType) async -> Bool {
        if hasEventAccess(type) { return true }
        guard EKEventStore.authorizationStatus(for: type) == .notDetermined else { return false }
        return (try? await eventStore.requestAccess(to: type)) ?? false
    }

    /// 建一条系统提醒事项；due 为空就是无期限的待办
    func createReminder(title: String, due: Date?, notes: String?) async -> Bool {
        guard await ensureEventAccess(.reminder) else { return false }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        if let notes, !notes.isEmpty { reminder.notes = notes }
        return (try? eventStore.save(reminder, commit: true)) != nil
    }

    /// 建一个系统日历日程；end 为空默认一小时
    func createCalendarEvent(title: String, start: Date, end: Date?, notes: String?) async -> Bool {
        guard await ensureEventAccess(.event) else { return false }
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = end ?? start.addingTimeInterval(3600)
        if let notes, !notes.isEmpty { event.notes = notes }
        event.calendar = eventStore.defaultCalendarForNewEvents
        return (try? eventStore.save(event, span: .thisEvent, commit: true)) != nil
    }

    // MARK: - 给 Home 小组件用的结构化数据（我自己看的，跟发给克克的文字块分开，
    // 不受"克克能看到的"那几个开关影响——那几个开关管的是要不要告诉克克，不是我自己能不能看）

    struct TodayEvent: Identifiable {
        let id = UUID()
        let title: String
        let timeText: String?
    }

    var hasCalendarAccess: Bool { hasEventAccess(.event) }
    var hasReminderAccess: Bool { hasEventAccess(.reminder) }

    func batteryPercent() -> Int? {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        return level >= 0 ? Int(level * 100) : nil
    }

    func isCharging() -> Bool {
        UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
    }

    func todayEvents(limit: Int = 3) -> [TodayEvent] {
        events(on: Date(), limit: limit)
    }

    /// 指定某一天的日程（给日历页用，不只是今天）
    func events(on date: Date, limit: Int = 20) -> [TodayEvent] {
        guard hasEventAccess(.event) else { return [] }
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return eventStore.events(matching: predicate).prefix(limit).map {
            TodayEvent(title: $0.title ?? "", timeText: $0.isAllDay ? nil : formatter.string(from: $0.startDate))
        }
    }

    func incompleteReminderTitles(limit: Int = 3) async -> [String] {
        guard hasEventAccess(.reminder) else { return [] }
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }
        return reminders.prefix(limit).compactMap(\.title)
    }

    // MARK: - 日历页：某一天的待办（跟系统「提醒事项」同步，能读也能勾选完成）

    struct ReminderItem: Identifiable {
        let id: String
        let title: String
        var isCompleted: Bool
    }

    func reminderItems(dueOn date: Date, limit: Int = 30) async -> [ReminderItem] {
        guard hasEventAccess(.reminder) else { return [] }
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = eventStore.predicateForReminders(in: nil)
        let all: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }
        let filtered = all.filter { reminder in
            guard let comps = reminder.dueDateComponents, let due = Calendar.current.date(from: comps) else { return false }
            return due >= start && due < end
        }
        return filtered.prefix(limit).map {
            ReminderItem(id: $0.calendarItemIdentifier, title: $0.title ?? "", isCompleted: $0.isCompleted)
        }
    }

    func setReminderCompleted(id: String, completed: Bool) {
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = completed
        try? eventStore.save(reminder, commit: true)
    }
}
