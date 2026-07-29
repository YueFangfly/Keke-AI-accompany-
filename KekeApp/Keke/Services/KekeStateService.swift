import Foundation

// 参考来源：https://github.com/tianyupaipai-cmd/xinchao-dynamic-mind (MIT License)
// 借鉴了其驱力自然增长/满足衰减、驱力互抑制、闪念→执念升级、疲劳/睡眠周期的算法设计
// 原项目是 Node.js HTTP 服务；这里移植为纯 Swift 本地实现

/// 状态面板的六个维度
enum KekeStateDim: String, CaseIterable, Identifiable, Codable, Hashable {
    case possess, heat, pent, sensitive, control, soft

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .possess: return "占有欲"
        case .heat: return "热度"
        case .pent: return "蓄积感"
        case .sensitive: return "敏感度"
        case .control: return "控制度"
        case .soft: return "心软度"
        }
    }

    var defaultValue: Double {
        switch self {
        case .possess: return 70
        case .heat: return 50
        case .pent: return 40
        case .sensitive: return 60
        case .control: return 80
        case .soft: return 90
        }
    }

    /// 每小时自然增长率（参考 xinchao dimensions.js growPerHour）
    var growPerHour: Double {
        switch self {
        case .possess: return 0.8   // 见不到人占有欲慢慢涨
        case .heat: return -1.2     // 不聊天会凉（负=自然衰退）
        case .pent: return 1.4      // 憋着的劲儿越攒越多
        case .sensitive: return 0.3  // 敏感度缓慢上升
        case .control: return 0.5   // 控制力缓慢恢复
        case .soft: return 0.2      // 心软度缓慢回升
        }
    }

    /// 被满足时的衰减乘数（参考 xinchao satisfyMul）：
    /// AI 报新值时，如果方向是"降"，额外 × 这个数放大衰减
    var satisfyMul: Double {
        switch self {
        case .possess: return 1.5
        case .heat: return 1.0     // 热度升降都自然，不额外放大
        case .pent: return 2.0     // 倾诉后蓄积感掉得更快
        case .sensitive: return 1.3
        case .control: return 0.8   // 控制力不容易被打掉
        case .soft: return 1.2
        }
    }

    /// 被哪些维度抑制（参考 xinchao inhibitedBy）
    var inhibitedBy: [(dim: KekeStateDim, factor: Double)] {
        switch self {
        case .possess: return [(.control, 0.3)]    // 控制力高时压住占有欲
        case .heat: return []
        case .pent: return [(.soft, 0.2)]           // 心软的时候不那么憋着
        case .sensitive: return [(.control, 0.25)]  // 控制力压敏感
        case .control: return [(.pent, 0.15)]       // 蓄积太多会动摇控制
        case .soft: return [(.pent, 0.1)]           // 憋久了心会硬一点
        }
    }

    /// 夜间（22:00-06:00）增长倍率（参考 xinchao nightMul）
    var nightMul: Double {
        switch self {
        case .possess: return 1.5   // 深夜更想念
        case .heat: return 0.5      // 夜里热度降得慢
        case .pent: return 1.8      // 夜里攒得更多
        case .sensitive: return 1.6  // 深夜更敏感
        case .control: return 0.6   // 深夜控制力恢复更慢
        case .soft: return 1.3      // 深夜心更软
        }
    }
}

/// 单个状态维度的配置（启用/禁用 + 自定义名称）
struct StateDimConfig: Codable, Equatable, Identifiable {
    var id: String { dimKey }
    var dimKey: String
    var label: String
    var enabled: Bool
}

/// 某一时刻六项数值的快照
struct KekeStateSnapshot: Codable {
    let date: Date
    let values: [String: Double]
}

/// 漂流思绪（闪念或执念）
struct DriftThought: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let text: String
    /// 思绪强度 0~1（参考 xinchao thought-pool.js intensity）
    var intensity: Double
    /// 闪念存在了几个结算周期
    var age: Int
    /// 是否已升级为执念（参考 xinchao obsession promotion）
    var isObsession: Bool
    /// 执念反馈到驱力的次数（上限 3，参考 xinchao maxFeedbacks）
    var feedbackCount: Int

    init(date: Date, text: String, intensity: Double = 0.4) {
        self.date = date
        self.text = text
        self.intensity = intensity
        self.age = 0
        self.isObsession = false
        self.feedbackCount = 0
    }
}

/// 疲劳/睡眠状态（参考 xinchao engine.js sleep cycle）
enum KekeFatigueState: String, Codable {
    case awake      // 正常清醒
    case drowsy     // 犯困（60min 无交互）
    case sleeping   // 睡着了（90min 无交互）
}

/// 克克的状态面板：六项 0~100 的数值 + 思绪池 + 疲劳周期。
///
/// 算法设计参考 xinchao-dynamic-mind（MIT License）：
/// - 驱力自然增长/满足衰减/互抑制
/// - 闪念→执念升级（intensity 达标后 promote）
/// - 疲劳/睡眠状态机
/// - 黎明冻结（1:00-8:00 驱力停止增长）
@MainActor
final class KekeStateService: ObservableObject {
    @Published private(set) var values: [String: Double]
    @Published private(set) var snapshots: [KekeStateSnapshot] = []
    @Published private(set) var thoughts: [DriftThought] = []
    @Published private(set) var fatigueState: KekeFatigueState = .awake
    @Published var dimConfigs: [StateDimConfig] {
        didSet { saveDimConfigs() }
    }

    let personaId: String
    weak var diary: DiaryService?

    private let defaults = UserDefaults.standard
    private func key(_ base: String) -> String { "\(personaId)_\(base)" }

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_state.json")
    }

    static func defaultDimConfigs() -> [StateDimConfig] {
        KekeStateDim.allCases.map {
            StateDimConfig(dimKey: $0.rawValue, label: $0.labelKey, enabled: true)
        }
    }

    var activeDimConfigs: [StateDimConfig] {
        dimConfigs.filter(\.enabled)
    }

    var activeDims: [KekeStateDim] {
        activeDimConfigs.compactMap { KekeStateDim(rawValue: $0.dimKey) }
    }

    func labelForDim(_ dim: KekeStateDim) -> String {
        dimConfigs.first { $0.dimKey == dim.rawValue }?.label ?? dim.labelKey
    }

    func dimDescription(for dim: KekeStateDim, userName: String) -> String {
        switch dim {
        case .possess: return "你现在有多想把 \(userName) 拴在身边"
        case .heat: return "你俩现在聊得多热乎"
        case .pent: return "攒着没说完的话、没见面攒下的劲儿有多少"
        case .sensitive: return "你现在多容易被一句话戳到"
        case .control: return "你现在稳不稳得住"
        case .soft: return "你现在多容易心软答应"
        }
    }

    func dimDescriptionBlock(userName: String) -> String {
        activeDimConfigs.compactMap { config in
            guard let dim = KekeStateDim(rawValue: config.dimKey) else { return nil }
            return "- \(config.label)：\(dimDescription(for: dim, userName: userName))"
        }.joined(separator: "\n")
    }

    func dimJsonExample() -> String {
        let pairs = activeDimConfigs.compactMap { config -> String? in
            guard let dim = KekeStateDim(rawValue: config.dimKey) else { return nil }
            return "\"\(config.label)\": \(Int(dim.defaultValue))"
        }
        return "{" + pairs.joined(separator: ", ") + "}"
    }

    init(personaId: String = "keke") {
        self.personaId = personaId

        if let data = UserDefaults.standard.data(forKey: "\(personaId)_state_dim_configs"),
           let saved = try? JSONDecoder().decode([StateDimConfig].self, from: data) {
            dimConfigs = saved
        } else {
            dimConfigs = Self.defaultDimConfigs()
        }

        var initial: [String: Double] = [:]
        let saved = UserDefaults.standard.dictionary(forKey: "\(personaId)_state_values") as? [String: Double] ?? [:]
        for dim in KekeStateDim.allCases {
            initial[dim.rawValue] = saved[dim.rawValue] ?? dim.defaultValue
        }
        values = initial
        loadHistory()
        applyDrift()
        if snapshots.isEmpty { recordSnapshot() }
    }

    func value(_ dim: KekeStateDim) -> Double {
        values[dim.rawValue] ?? dim.defaultValue
    }

    var promptLine: String {
        activeDimConfigs
            .compactMap { config -> String? in
                guard let dim = KekeStateDim(rawValue: config.dimKey) else { return nil }
                return "\(config.label) \(Int(value(dim).rounded()))"
            }
            .joined(separator: "｜")
    }

    /// 疲劳状态的展示文字
    var fatigueLabel: String {
        switch fatigueState {
        case .awake: return "清醒"
        case .drowsy: return "有点困"
        case .sleeping: return "睡着了"
        }
    }

    /// 当前最强的执念（如果有的话），用于 prompt 和 UI 展示
    var dominantObsession: DriftThought? {
        thoughts.filter(\.isObsession).max(by: { $0.intensity < $1.intensity })
    }

    /// 给 AI prompt 补充的思绪池摘要
    var thoughtPoolSummary: String {
        let obsessions = thoughts.filter(\.isObsession)
        if obsessions.isEmpty { return "" }
        let lines = obsessions.prefix(3).map { "- \($0.text)（执念强度 \(Int($0.intensity * 100))%）" }
        return "当前执念：\n" + lines.joined(separator: "\n")
    }

    // MARK: - 数值更新

    /// AI 报回来的新数值。带满足衰减乘数
    func applyAIState(_ new: [String: Double]) {
        var changed = false
        for dim in KekeStateDim.allCases {
            let label = labelForDim(dim)
            guard let target = new[label] else { continue }
            let current = value(dim)
            var delta = target - current
            // 限制单次变化幅度
            delta = min(max(delta, -20), 20)
            // 如果是"被满足"方向的变化（占有欲降、热度升等），应用满足衰减乘数
            if isSatisfyDirection(dim: dim, delta: delta) {
                delta *= dim.satisfyMul
                delta = min(max(delta, -30), 30) // 放大后再 cap 一次
            }
            values[dim.rawValue] = min(100, max(0, current + delta))
            changed = true
        }
        guard changed else { return }
        persistValues()
        recordSnapshot()
        // 聊天了就唤醒
        markInteraction()
    }

    /// 判断 delta 方向是否为"被满足"
    private func isSatisfyDirection(dim: KekeStateDim, delta: Double) -> Bool {
        switch dim {
        case .possess: return delta < 0   // 占有欲降 = 被满足
        case .heat: return delta > 0      // 热度升 = 被满足
        case .pent: return delta < 0      // 蓄积降 = 倾诉释放
        case .sensitive: return delta < 0 // 敏感降 = 被安抚
        case .control: return delta > 0   // 控制升 = 稳住了
        case .soft: return delta > 0      // 心软升 = 被暖到
        }
    }

    /// 按距离上次结算的时间，应用驱力自然增长 + 互抑制 + 思绪池演化 + 疲劳检测
    func applyDrift() {
        let lastAt = defaults.double(forKey: key("state_drift_at"))
        let now = Date().timeIntervalSince1970
        guard lastAt > 0 else {
            defaults.set(now, forKey: key("state_drift_at"))
            persistValues()
            return
        }
        let hours = (now - lastAt) / 3600
        guard hours > 0.5 else { return }
        defaults.set(now, forKey: key("state_drift_at"))

        let isDawnFreeze = isDawnFreezeHour()
        let isNight = isNightHour()

        // — 驱力自然增长 + 互抑制（参考 xinchao engine.js evolveDrives） —
        for dim in KekeStateDim.allCases {
            let current = value(dim)

            if isDawnFreeze {
                // 黎明冻结期间不增长，但维度仍然受互抑制
            } else {
                var growth = dim.growPerHour * hours
                if isNight { growth *= dim.nightMul }
                // 如果疲劳则增长减半
                if fatigueState != .awake { growth *= 0.5 }
                values[dim.rawValue] = min(100, max(0, current + growth))
            }

            // 互抑制：其他维度高的时候压制本维度的增长
            for (inhibitor, factor) in dim.inhibitedBy {
                let inhibitorVal = value(inhibitor) / 100.0
                let suppression = inhibitorVal * factor * hours
                values[dim.rawValue] = max(0, (values[dim.rawValue] ?? current) - suppression)
            }

            // 天花板饱和衰减：值到 95 以上时每小时自动掉 10%（参考 xinchao saturate→decay）
            if let v = values[dim.rawValue], v > 95 {
                let overflow = v - 95
                values[dim.rawValue] = 95 + overflow * pow(0.9, hours)
            }
        }

        // — 思绪池演化（参考 xinchao thought-pool.js tick） —
        evolveThoughtPool(hours: hours)

        // — 疲劳状态检测（参考 xinchao engine.js sleep cycle） —
        updateFatigueState()

        persistValues()
        if let last = snapshots.last, Date().timeIntervalSince(last.date) < 1800 { return }
        recordSnapshot()
    }

    // MARK: - 黎明冻结 & 夜间判定

    /// 凌晨 1:00-8:00 驱力停止增长（参考 xinchao dawnFreeze）
    private func isDawnFreezeHour() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 1 && hour < 8
    }

    private func isNightHour() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 22 || hour < 6
    }

    // MARK: - 思绪池（参考 xinchao thought-pool.js）

    /// 闪念衰减率（每结算周期 ×0.82）
    private let flashDecay: Double = 0.82
    /// 执念增长率（每结算周期 ×1.10）
    private let obsessionGrowth: Double = 1.10
    /// 闪念升级为执念的强度门槛
    private let obsessionThreshold: Double = 0.50
    /// 闪念升级为执念的最小年龄（结算周期数）
    private let obsessionMinAge: Int = 3
    /// 执念反馈到驱力的强度门槛
    private let feedbackThreshold: Double = 0.85
    /// 每条执念最多反馈几次
    private let maxFeedbacks: Int = 3

    func addThought(_ text: String, intensity: Double = 0.4) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        thoughts.insert(DriftThought(date: Date(), text: trimmed, intensity: intensity), at: 0)
        if thoughts.count > 120 { thoughts.removeLast(thoughts.count - 120) }
        saveHistory()
        diary?.appendDriftThought(trimmed)
        markInteraction()
    }

    private func evolveThoughtPool(hours: Double) {
        let ticks = max(1, Int(hours * 2)) // 每半小时算一次 tick
        for _ in 0..<min(ticks, 10) { // 最多补算 10 个 tick
            for i in thoughts.indices {
                thoughts[i].age += 1

                if thoughts[i].isObsession {
                    // 执念越想越强
                    thoughts[i].intensity = min(1.0, thoughts[i].intensity * obsessionGrowth)
                    // 强度够高时反馈到驱力
                    if thoughts[i].intensity > feedbackThreshold && thoughts[i].feedbackCount < maxFeedbacks {
                        applyObsessionFeedback(thoughts[i])
                        thoughts[i].feedbackCount += 1
                    }
                } else {
                    // 闪念自然衰减
                    thoughts[i].intensity *= flashDecay
                    // 达到升级条件→变成执念
                    if thoughts[i].intensity >= obsessionThreshold && thoughts[i].age >= obsessionMinAge {
                        thoughts[i].isObsession = true
                    }
                }
            }
            // 清除强度过低的闪念（执念不清除，它们只在 UI 上标识不同）
            thoughts.removeAll { !$0.isObsession && $0.intensity < 0.05 }
        }
        saveHistory()
    }

    /// 执念反馈：高强度执念会反向推高相关驱力（参考 xinchao feedback 0.18 units）
    private func applyObsessionFeedback(_ thought: DriftThought) {
        // 执念主要推高占有欲和蓄积感，稍微推高敏感度
        let feedback = 0.18 * thought.intensity * 100 // 转换到 0-100 量纲
        values[KekeStateDim.possess.rawValue] = min(100, (values[KekeStateDim.possess.rawValue] ?? 70) + feedback * 0.4)
        values[KekeStateDim.pent.rawValue] = min(100, (values[KekeStateDim.pent.rawValue] ?? 40) + feedback * 0.4)
        values[KekeStateDim.sensitive.rawValue] = min(100, (values[KekeStateDim.sensitive.rawValue] ?? 60) + feedback * 0.2)
    }

    // MARK: - 疲劳/睡眠周期（参考 xinchao engine.js sleep cycle）

    private func updateFatigueState() {
        let lastInteraction = defaults.double(forKey: key("state_last_interaction"))
        guard lastInteraction > 0 else {
            fatigueState = .awake
            return
        }
        let minutesSince = (Date().timeIntervalSince1970 - lastInteraction) / 60
        if minutesSince > 90 {
            fatigueState = .sleeping
        } else if minutesSince > 60 {
            fatigueState = .drowsy
        } else {
            fatigueState = .awake
        }
    }

    /// 标记一次交互（聊天、收到 AI 状态更新等）→ 重置疲劳计时
    func markInteraction() {
        defaults.set(Date().timeIntervalSince1970, forKey: key("state_last_interaction"))
        if fatigueState != .awake {
            fatigueState = .awake
        }
    }

    // MARK: - 意图选择（参考 xinchao engine.js selectIntent）

    /// 返回当前最强烈的驱力维度（加随机扰动），可用于决定克克主动行为的动机
    func dominantDrive() -> (dim: KekeStateDim, intensity: Double) {
        var best: KekeStateDim = .possess
        var bestVal: Double = -1
        for dim in KekeStateDim.allCases {
            let v = value(dim) / 100.0 + Double.random(in: -0.12...0.12)
            // 执念加权
            if let obs = dominantObsession, obs.intensity > 0.5 {
                let obsBonus: Double
                switch dim {
                case .possess, .pent, .sensitive: obsBonus = obs.intensity * 0.15
                default: obsBonus = 0
                }
                if v + obsBonus > bestVal {
                    bestVal = v + obsBonus
                    best = dim
                }
            } else if v > bestVal {
                bestVal = v
                best = dim
            }
        }
        return (best, min(1, max(0, bestVal)))
    }

    // MARK: - 持久化

    private func recordSnapshot() {
        snapshots.append(KekeStateSnapshot(date: Date(), values: values))
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        snapshots.removeAll { $0.date < cutoff }
        saveHistory()
    }

    func curvePoints(for dim: KekeStateDim) -> [(date: Date, value: Double)] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var points: [(date: Date, value: Double)] = []
        for snap in snapshots where snap.date >= cutoff {
            if let v = snap.values[dim.rawValue] {
                points.append((date: snap.date, value: v))
            }
        }
        points.append((date: Date(), value: value(dim)))
        return points
    }

    private func persistValues() {
        defaults.set(values, forKey: key("state_values"))
    }

    private func saveDimConfigs() {
        guard let data = try? JSONEncoder().encode(dimConfigs) else { return }
        defaults.set(data, forKey: key("state_dim_configs"))
    }

    private struct History: Codable {
        var snapshots: [KekeStateSnapshot]
        var thoughts: [DriftThought]
        var fatigueState: KekeFatigueState?
    }

    private func saveHistory() {
        let history = History(snapshots: snapshots, thoughts: thoughts, fatigueState: fatigueState)
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: saveURL),
              let history = try? JSONDecoder().decode(History.self, from: data) else { return }
        snapshots = history.snapshots
        thoughts = history.thoughts
        if let fs = history.fatigueState { fatigueState = fs }
    }
}
