import Foundation
import HealthKit

/// 经期日历：健康 App 的月经记录（只读）+ App 内手动标记（本地保存），
/// 根据历史周期起始日算平均周期、预测下次日期
@MainActor
final class CycleService: ObservableObject {
    /// 手动标记的经期日（都是当天 0 点）
    @Published private(set) var manualDays: Set<Date> = []
    /// 从健康 App 读到的经期日
    @Published private(set) var healthDays: Set<Date> = []

    private let healthStore = HKHealthStore()
    private let calendar = Calendar.current

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keke_cycle.json")
    }

    init() {
        load()
    }

    var allDays: Set<Date> { manualDays.union(healthDays) }

    func isPeriodDay(_ date: Date) -> Bool {
        allDays.contains(calendar.startOfDay(for: date))
    }

    /// 点日历某天：切换手动标记
    func toggle(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        if manualDays.contains(day) {
            manualDays.remove(day)
        } else {
            manualDays.insert(day)
        }
        save()
    }

    /// 从健康 App 同步最近 8 个月的月经记录
    func refreshFromHealth() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else { return }
        let start = calendar.date(byAdding: .day, value: -240, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, result, _ in
                continuation.resume(returning: (result as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        var days: Set<Date> = []
        for sample in samples where sample.value != HKCategoryValueMenstrualFlow.none.rawValue {
            var day = calendar.startOfDay(for: sample.startDate)
            while day <= sample.endDate {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        healthDays = days
    }

    // MARK: - 周期计算

    /// 每次经期的开始日（相邻 2 天内算同一次）
    var episodeStarts: [Date] {
        let sorted = allDays.sorted()
        var starts: [Date] = []
        var previous: Date?
        for day in sorted {
            if let previous,
               let gap = calendar.dateComponents([.day], from: previous, to: day).day,
               gap <= 2 {
                // 还是同一次
            } else {
                starts.append(day)
            }
            previous = day
        }
        return starts
    }

    /// 平均周期天数（取最近几次，剔除异常值）
    var averageCycleLength: Int? {
        let starts = episodeStarts
        guard starts.count >= 2 else { return nil }
        let gaps = zip(starts.dropFirst(), starts)
            .compactMap { calendar.dateComponents([.day], from: $1, to: $0).day }
            .filter { (15...60).contains($0) }
        guard !gaps.isEmpty else { return nil }
        let recent = gaps.suffix(6)
        return recent.reduce(0, +) / recent.count
    }

    var lastStart: Date? { episodeStarts.last }

    /// 预测下次开始日
    var predictedNextStart: Date? {
        guard let lastStart, let average = averageCycleLength else { return nil }
        let predicted = calendar.date(byAdding: .day, value: average, to: lastStart)
        // 已经过了预测日就不再显示旧预测
        if let predicted, predicted < calendar.startOfDay(for: Date()) { return nil }
        return predicted
    }

    /// 预测的那次经期（标 5 天，用浅色画在日历上）
    var predictedDays: Set<Date> {
        guard let start = predictedNextStart else { return [] }
        var days: Set<Date> = []
        for offset in 0..<5 {
            if let day = calendar.date(byAdding: .day, value: offset, to: start) {
                days.insert(calendar.startOfDay(for: day))
            }
        }
        return days
    }

    /// 顶部的状态文字
    func statusLines(lang: AppLanguage) -> [String] {
        var lines: [String] = []
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.locale = lang == .en ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN")
        formatter.dateFormat = lang == .en ? "MMM d" : "M月d日"

        if allDays.contains(today),
           let start = episodeStarts.last(where: { $0 <= today }),
           let dayIndex = calendar.dateComponents([.day], from: start, to: today).day {
            lines.append(lang == .en
                ? "Day \(dayIndex + 1) of your period — drink something warm, Keke's with you"
                : "今天是经期第 \(dayIndex + 1) 天，多喝热水，克克陪着你")
        }
        if let lastStart {
            lines.append(lang == .en
                ? "Last: started \(formatter.string(from: lastStart))"
                : "上次：\(formatter.string(from: lastStart)) 开始")
        }
        if let average = averageCycleLength {
            lines.append(lang == .en
                ? "Average cycle: \(average) days"
                : "平均周期：\(average) 天")
        }
        if let next = predictedNextStart,
           let remaining = calendar.dateComponents([.day], from: today, to: next).day {
            if remaining == 0 {
                lines.append(lang == .en
                    ? "Expected today — bring what you need"
                    : "预计今天来，记得带上需要的东西")
            } else {
                lines.append(lang == .en
                    ? "Next expected: \(formatter.string(from: next)) (in \(remaining) days)"
                    : "预计下次：\(formatter.string(from: next))（还有 \(remaining) 天）")
            }
        }
        if lines.isEmpty {
            lines.append(lang == .en
                ? "No records yet. Tap a date on the calendar to mark it, or authorize Health data on the \"Heartbeat\" page to sync automatically"
                : "还没有记录。点日历上的日期就能标记，或在「心跳」页授权健康数据自动同步")
        }
        return lines
    }

    // MARK: - 存取

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(manualDays)) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([Date].self, from: data) else { return }
        manualDays = Set(saved.map { calendar.startOfDay(for: $0) })
    }
}
