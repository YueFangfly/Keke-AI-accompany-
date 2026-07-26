import Foundation
import HealthKit

/// 读取健康数据：步数、步行距离、睡眠、心率、月经记录
@MainActor
final class HealthService: ObservableObject {
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    @Published var authorized = UserDefaults.standard.bool(forKey: "health_authorized")
    @Published var steps: Double?
    @Published var distanceKM: Double?
    @Published var sleepHours: Double?
    @Published var heartRate: Double?
    @Published var lastPeriodDate: Date?

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .menstrualFlow) { types.insert(t) }
        return types
    }

    func requestAuthorization() async {
        guard Self.isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorized = true
            UserDefaults.standard.set(true, forKey: "health_authorized")
            await refresh()
        } catch {
            // 授权弹窗被取消或系统错误，保持未授权状态即可
        }
    }

    func refresh() async {
        steps = await todaySum(.stepCount, unit: .count())
        let meters = await todaySum(.distanceWalkingRunning, unit: .meter())
        distanceKM = meters.map { $0 / 1000 }
        heartRate = await latestHeartRate()
        sleepHours = await lastNightSleepHours()
        lastPeriodDate = await latestPeriodDate()
    }

    /// 组织一段给克克看的健康数据摘要
    func summaryForKeke(userName: String) -> String {
        var parts: [String] = []
        if let steps { parts.append("今天走了 \(Int(steps)) 步") }
        if let distanceKM { parts.append(String(format: "步行 %.1f 公里", distanceKM)) }
        if let sleepHours { parts.append(String(format: "昨晚睡了 %.1f 小时", sleepHours)) }
        if let heartRate { parts.append("最近心率 \(Int(heartRate)) 次/分") }
        if let lastPeriodDate {
            let days = Calendar.current.dateComponents([.day], from: lastPeriodDate, to: Date()).day ?? 0
            parts.append(days == 0 ? "今天有月经记录" : "\(days) 天前有月经记录")
        }
        if parts.isEmpty {
            return "（\(userName) 想分享健康数据，但今天还没有记录。）"
        }
        return "（\(userName) 分享了今天的健康数据：" + parts.joined(separator: "，") + "。请自然地回应和关心她，不用逐条复述。）"
    }

    // MARK: - 查询

    private func todaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type,
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latestHeartRate() async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil,
                                      limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let bpm = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: bpm)
            }
            store.execute(query)
        }
    }

    private func lastNightSleepHours() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let calendar = Calendar.current
        let now = Date()
        // 从昨晚 18 点开始算
        let start = calendar.date(byAdding: .hour, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let seconds = (samples as? [HKCategorySample])?
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
                continuation.resume(returning: seconds > 0 ? seconds / 3600 : nil)
            }
            store.execute(query)
        }
    }

    private func latestPeriodDate() async -> Date? {
        guard let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -60, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: 10, sortDescriptors: [sort]) { _, samples, _ in
                let sample = (samples as? [HKCategorySample])?
                    .first { $0.value != HKCategoryValueMenstrualFlow.none.rawValue }
                continuation.resume(returning: sample?.startDate)
            }
            store.execute(query)
        }
    }
}
