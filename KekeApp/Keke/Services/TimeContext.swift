import Foundation

/// 时段划分。边界可配，默认深夜是 23:00–05:00。
///
/// 存的是每个时段的**开始小时**。判定就是「找最后一个开始小时 ≤ 当前小时」——
/// 找不到就说明现在在**跨午夜的那一段**里（默认是深夜），取排序后的最后一个。
/// 跨午夜这件事不特殊处理的话，凌晨两点会被判成「傍晚」
struct TimePhaseConfig: Codable, Equatable {
    var earlyMorning = 5     // 清晨
    var morning = 8          // 上午
    var afternoon = 12       // 下午
    var evening = 18         // 傍晚
    var lateNight = 23       // 深夜（跨午夜）

    static let `default` = TimePhaseConfig()

    private static let key = "time_phase_config"

    static var current: TimePhaseConfig {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = try? JSONDecoder().decode(TimePhaseConfig.self, from: data)
            else { return .default }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 按开始小时排好的五段。名字固定，只有边界可调
    var stops: [(hour: Int, name: String)] {
        [(earlyMorning, "清晨"), (morning, "上午"), (afternoon, "下午"),
         (evening, "傍晚"), (lateNight, "深夜")]
            .map { (hour: min(23, max(0, $0.0)), name: $0.1) }
            .sorted { $0.hour < $1.hour }
    }
}

/// 每轮都要塞进 system prompt 末尾的那一行时间。
///
/// **为什么必须在末尾**：缓存是前缀匹配的，渲染顺序是 `tools → system → messages`。
/// 时间每轮都变，放在缓存断点之前会让整个 prompt 的缓存永远命中不了。
/// 克克这边 `system` 拆成两块，断点打在第一块（人设）末尾，
/// 这一行跟着 `extraContext` 走第二块，所以天然在断点之外。
///
/// 纯函数：`now`、`lastMessageAt`、时区、配置全从参数进，不看时钟也不读设置。
enum TimeContext {

    /// 时区。没选过就跟着设备走——**不写死**，用户出国了她该知道
    private static let zoneKey = "time_context_zone"

    static var timeZoneIdentifier: String? {
        get { UserDefaults.standard.string(forKey: zoneKey) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: zoneKey) }
            else { UserDefaults.standard.removeObject(forKey: zoneKey) }
        }
    }

    static var timeZone: TimeZone {
        guard let id = timeZoneIdentifier, let zone = TimeZone(identifier: id) else {
            return .current
        }
        return zone
    }

    /// 现在算哪个时段
    static func phase(hour: Int, config: TimePhaseConfig = .default) -> String {
        let stops = config.stops
        guard let last = stops.last else { return "" }
        // 兜底取最后一段：它是跨午夜的那一段，凌晨的小时数比谁都小，一个都匹配不上
        var current = last.name
        for stop in stops where hour >= stop.hour { current = stop.name }
        return current
    }

    /// 「距上次对话」那一段。`nil` = 第一次说话，整段省掉
    static func elapsed(from last: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(last))
        if seconds < 60 { return "刚刚" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前" }
        let days = hours / 24
        if days < 30 { return "\(days) 天前" }
        return "\(days / 30) 个月前"
    }

    /// 拼出整行。
    ///
    /// `现在是 2026年9月12日 星期六 23:47（深夜）｜距上次对话：6 小时前`
    static func line(now: Date,
                     lastMessageAt: Date?,
                     timeZone: TimeZone = .current,
                     config: TimePhaseConfig = .default) -> String {
        let formatter = DateFormatter()
        // locale 钉死 zh_CN：跟着系统语言变的话，同一台设备换个语言输出就变了，
        // 而这行是要进 prompt 的
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: now)

        var line = "现在是 \(formatter.string(from: now))（\(phase(hour: hour, config: config))）"
        // 第一次说话就没有「距上次」可言，整段省掉而不是写「距上次对话：无」
        if let lastMessageAt {
            line += "｜距上次对话：\(elapsed(from: lastMessageAt, to: now))"
        }
        return line
    }
}
