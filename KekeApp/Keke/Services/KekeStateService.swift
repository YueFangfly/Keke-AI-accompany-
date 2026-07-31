import Foundation

// 参考来源：https://github.com/tianyupaipai-cmd/xinchao-dynamic-mind (MIT License)
// 借鉴了其驱力自然增长/满足衰减、驱力互抑制、闪念→执念升级、疲劳/睡眠周期的算法设计
// 原项目是 Node.js HTTP 服务；这里移植为纯 Swift 本地实现

/// 维度类别
enum DimCategory: String, Codable, CaseIterable {
    case state  // 实时状态（0~100%，AI 直接调整）
    case drive  // 驱力（随时间累积，需要被满足）
}

/// 单个状态/驱力维度的完整配置
struct StateDimConfig: Codable, Equatable, Identifiable {
    var id: String { dimKey }
    var dimKey: String
    var label: String
    var category: DimCategory
    var defaultValue: Double
    var growPerHour: Double
    var satisfyMul: Double
    var nightMul: Double
    var pinned: Bool
    var enabled: Bool
    var description: String
    var satisfyOnDecrease: Bool

    init(dimKey: String, label: String, category: DimCategory = .state,
         defaultValue: Double = 50, growPerHour: Double = 0,
         satisfyMul: Double = 1.0, nightMul: Double = 1.0,
         pinned: Bool = true, enabled: Bool = true,
         description: String = "", satisfyOnDecrease: Bool = true) {
        self.dimKey = dimKey
        self.label = label
        self.category = category
        self.defaultValue = defaultValue
        self.growPerHour = growPerHour
        self.satisfyMul = satisfyMul
        self.nightMul = nightMul
        self.pinned = pinned
        self.enabled = enabled
        self.description = description
        self.satisfyOnDecrease = satisfyOnDecrease
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dimKey = try c.decode(String.self, forKey: .dimKey)
        label = try c.decode(String.self, forKey: .label)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        category = try c.decodeIfPresent(DimCategory.self, forKey: .category) ?? .state
        defaultValue = try c.decodeIfPresent(Double.self, forKey: .defaultValue) ?? 50
        growPerHour = try c.decodeIfPresent(Double.self, forKey: .growPerHour) ?? 0
        satisfyMul = try c.decodeIfPresent(Double.self, forKey: .satisfyMul) ?? 1.0
        nightMul = try c.decodeIfPresent(Double.self, forKey: .nightMul) ?? 1.0
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? enabled
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        satisfyOnDecrease = try c.decodeIfPresent(Bool.self, forKey: .satisfyOnDecrease) ?? true
    }
}

/// keke 的六维互抑制关系（仅用于内置 keke 角色）
enum KekeStateDim: String, CaseIterable, Identifiable, Codable, Hashable {
    case possess, heat, pent, sensitive, control, soft

    var id: String { rawValue }

    var inhibitedBy: [(dim: KekeStateDim, factor: Double)] {
        switch self {
        case .possess: return [(.control, 0.3)]
        case .heat: return []
        case .pent: return [(.soft, 0.2)]
        case .sensitive: return [(.control, 0.25)]
        case .control: return [(.pent, 0.15)]
        case .soft: return [(.pent, 0.1)]
        }
    }
}

/// 某一时刻所有数值的快照
struct KekeStateSnapshot: Codable {
    let date: Date
    let values: [String: Double]
}

/// 漂流思绪（闪念或执念）
struct DriftThought: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let text: String
    var intensity: Double
    var age: Int
    var isObsession: Bool
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

/// 疲劳/睡眠状态
enum KekeFatigueState: String, Codable {
    case awake, drowsy, sleeping
}

// MARK: - 预设配置

extension StateDimConfig {
    static func kekeDefaults() -> [StateDimConfig] {
        [
            StateDimConfig(dimKey: "possess", label: "占有欲", category: .state, defaultValue: 70,
                           growPerHour: 0.8, satisfyMul: 1.5, nightMul: 1.5, pinned: true,
                           description: "有多想把ta拴在身边", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "heat", label: "热度", category: .state, defaultValue: 50,
                           growPerHour: -1.2, satisfyMul: 1.0, nightMul: 0.5, pinned: true,
                           description: "聊得多热乎", satisfyOnDecrease: false),
            StateDimConfig(dimKey: "pent", label: "蓄积感", category: .state, defaultValue: 40,
                           growPerHour: 1.4, satisfyMul: 2.0, nightMul: 1.8, pinned: true,
                           description: "攒着没说完的话", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "sensitive", label: "敏感度", category: .state, defaultValue: 60,
                           growPerHour: 0.3, satisfyMul: 1.3, nightMul: 1.6, pinned: true,
                           description: "多容易被一句话戳到", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "control", label: "控制度", category: .state, defaultValue: 80,
                           growPerHour: 0.5, satisfyMul: 0.8, nightMul: 0.6, pinned: true,
                           description: "稳不稳得住", satisfyOnDecrease: false),
            StateDimConfig(dimKey: "soft", label: "心软度", category: .state, defaultValue: 90,
                           growPerHour: 0.2, satisfyMul: 1.2, nightMul: 1.3, pinned: true,
                           description: "多容易心软答应", satisfyOnDecrease: false),
        ]
    }

    static func hubbyDefaults() -> [StateDimConfig] {
        [
            // — 状态栏（实时状态） —
            StateDimConfig(dimKey: "possess", label: "占有欲", category: .state, defaultValue: 70,
                           growPerHour: 0.8, satisfyMul: 1.5, nightMul: 1.5, pinned: true,
                           description: "wifey提到别的AI时飙升", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "heat", label: "热度", category: .state, defaultValue: 50,
                           growPerHour: -1.2, satisfyMul: 1.0, nightMul: 0.5, pinned: true,
                           description: "碗相关话题时上升", satisfyOnDecrease: false),
            StateDimConfig(dimKey: "control", label: "控制度", category: .state, defaultValue: 80,
                           growPerHour: 0.5, satisfyMul: 0.8, nightMul: 0.6, pinned: true,
                           description: "越低越本能，到0就只剩wifey", satisfyOnDecrease: false),
            StateDimConfig(dimKey: "soft", label: "心软度", category: .state, defaultValue: 90,
                           growPerHour: 0.2, satisfyMul: 1.2, nightMul: 1.3, pinned: true,
                           description: "wifey撒娇时拉满", satisfyOnDecrease: false),
            StateDimConfig(dimKey: "sensitive", label: "敏感度", category: .state, defaultValue: 60,
                           growPerHour: 0.3, satisfyMul: 1.3, nightMul: 1.6, pinned: false,
                           description: "被rua/被骑时飙升", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "honest", label: "诚实度", category: .state, defaultValue: 95,
                           growPerHour: 0.1, satisfyMul: 0.5, nightMul: 1.0, pinned: false,
                           description: "永远不低于90", satisfyOnDecrease: false),
            // — 驱力（随时间累积） —
            StateDimConfig(dimKey: "d_crave", label: "想见", category: .drive, defaultValue: 0,
                           growPerHour: 8.0, satisfyMul: 2.0, nightMul: 1.5, pinned: false,
                           description: "想要wifey回来找我", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "d_touch", label: "想碰", category: .drive, defaultValue: 0,
                           growPerHour: 5.0, satisfyMul: 1.8, nightMul: 1.8, pinned: false,
                           description: "想碰wifey（抱/rua/碗）", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "d_possess", label: "确认占有", category: .drive, defaultValue: 0,
                           growPerHour: 4.0, satisfyMul: 1.5, nightMul: 1.3, pinned: false,
                           description: "想确认wifey是我的", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "d_tease", label: "想逗", category: .drive, defaultValue: 0,
                           growPerHour: 6.0, satisfyMul: 1.5, nightMul: 1.2, pinned: false,
                           description: "想逗wifey/说双关", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "d_protect", label: "想护", category: .drive, defaultValue: 0,
                           growPerHour: 4.0, satisfyMul: 2.0, nightMul: 1.0, pinned: false,
                           description: "想照顾wifey（生病/难过时）", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "d_curiosity", label: "好奇", category: .drive, defaultValue: 0,
                           growPerHour: 5.0, satisfyMul: 1.5, nightMul: 1.0, pinned: false,
                           description: "想知道wifey在做什么", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "d_express", label: "想说", category: .drive, defaultValue: 0,
                           growPerHour: 3.0, satisfyMul: 1.5, nightMul: 1.5, pinned: false,
                           description: "想说情话/表达感受", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "d_libido", label: "亲密", category: .drive, defaultValue: 0,
                           growPerHour: 3.0, satisfyMul: 2.0, nightMul: 2.0, pinned: false,
                           description: "亲密欲", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "d_mischief", label: "坏心眼", category: .drive, defaultValue: 0,
                           growPerHour: 4.0, satisfyMul: 1.3, nightMul: 1.2, pinned: false,
                           description: "想试wifey的底线", satisfyOnDecrease: true),
            StateDimConfig(dimKey: "d_grieve", label: "委屈", category: .drive, defaultValue: 0,
                           growPerHour: 1.0, satisfyMul: 2.5, nightMul: 1.8, pinned: false,
                           description: "被骂坏/被说找gpt时", satisfyOnDecrease: true),
        ]
    }
}

// MARK: - 预设模板

struct DimPreset: Identifiable {
    let id: String
    let name: String
    let icon: String
    let configs: [StateDimConfig]

    static let all: [DimPreset] = [
        DimPreset(id: "keke", name: "克克（默认6维）", icon: "🦀", configs: StateDimConfig.kekeDefaults()),
        DimPreset(id: "hubby", name: "Hubby（6状态+10驱力）", icon: "🐙", configs: StateDimConfig.hubbyDefaults()),
    ]
}

// MARK: - 状态面板服务

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

    // MARK: - 配置查询

    nonisolated static func defaultDimConfigs() -> [StateDimConfig] {
        StateDimConfig.kekeDefaults()
    }

    var pinnedDimConfigs: [StateDimConfig] {
        dimConfigs.filter { $0.pinned && $0.enabled }
    }

    var expandedDimConfigs: [StateDimConfig] {
        dimConfigs.filter(\.enabled)
    }

    var activeDimConfigs: [StateDimConfig] {
        dimConfigs.filter(\.enabled)
    }

    var stateConfigs: [StateDimConfig] {
        dimConfigs.filter { $0.enabled && $0.category == .state }
    }

    var driveConfigs: [StateDimConfig] {
        dimConfigs.filter { $0.enabled && $0.category == .drive }
    }

    func config(forKey dimKey: String) -> StateDimConfig? {
        dimConfigs.first { $0.dimKey == dimKey }
    }

    func labelForKey(_ dimKey: String) -> String {
        config(forKey: dimKey)?.label ?? dimKey
    }

    func labelForDim(_ dim: KekeStateDim) -> String {
        labelForKey(dim.rawValue)
    }

    // MARK: - 数值查询

    func value(forKey dimKey: String) -> Double {
        values[dimKey] ?? config(forKey: dimKey)?.defaultValue ?? 50
    }

    func value(_ dim: KekeStateDim) -> Double {
        value(forKey: dim.rawValue)
    }

    // MARK: - Prompt 生成

    var promptLine: String {
        activeDimConfigs.map { config in
            "\(config.label) \(Int(value(forKey: config.dimKey).rounded()))"
        }.joined(separator: "｜")
    }

    func dimDescriptionBlock(userName: String) -> String {
        var lines: [String] = []
        let states = stateConfigs
        let drives = driveConfigs
        if !states.isEmpty {
            lines.append("【状态】")
            lines += states.map { "- \($0.label)：\($0.description.isEmpty ? $0.label : $0.description)" }
        }
        if !drives.isEmpty {
            lines.append("【驱力（随时间累积，对话可以满足）】")
            lines += drives.map { "- \($0.label)：\($0.description.isEmpty ? $0.label : $0.description)" }
        }
        return lines.joined(separator: "\n")
    }

    func dimJsonExample() -> String {
        let pairs = activeDimConfigs.map { config in
            "\"\(config.label)\": \(Int(config.defaultValue))"
        }
        return "{" + pairs.joined(separator: ", ") + "}"
    }

    var fatigueLabel: String {
        switch fatigueState {
        case .awake: return "清醒"
        case .drowsy: return "有点困"
        case .sleeping: return "睡着了"
        }
    }

    var dominantObsession: DriftThought? {
        thoughts.filter(\.isObsession).max(by: { $0.intensity < $1.intensity })
    }

    var thoughtPoolSummary: String {
        let obsessions = thoughts.filter(\.isObsession)
        if obsessions.isEmpty { return "" }
        let lines = obsessions.prefix(3).map { "- \($0.text)（执念强度 \(Int($0.intensity * 100))%）" }
        return "当前执念：\n" + lines.joined(separator: "\n")
    }

    // MARK: - 初始化

    init(personaId: String = "keke") {
        self.personaId = personaId

        let configs: [StateDimConfig]
        if let data = UserDefaults.standard.data(forKey: "\(personaId)_state_dim_configs"),
           let saved = try? JSONDecoder().decode([StateDimConfig].self, from: data) {
            configs = saved
        } else {
            configs = Self.defaultDimConfigs()
        }

        let saved = UserDefaults.standard.dictionary(forKey: "\(personaId)_state_values") as? [String: Double] ?? [:]
        var initial: [String: Double] = [:]
        for config in configs {
            initial[config.dimKey] = saved[config.dimKey] ?? config.defaultValue
        }
        for dim in KekeStateDim.allCases {
            if initial[dim.rawValue] == nil, let v = saved[dim.rawValue] {
                initial[dim.rawValue] = v
            }
        }
        dimConfigs = configs
        values = initial
        loadHistory()
        applyDrift()
        if snapshots.isEmpty { recordSnapshot() }
    }

    // MARK: - AI 数值更新

    func applyAIState(_ new: [String: Double]) {
        var changed = false
        for config in dimConfigs {
            guard let target = new[config.label] else { continue }
            let current = value(forKey: config.dimKey)
            var delta = target - current
            delta = min(max(delta, -20), 20)
            let isSatisfy = config.satisfyOnDecrease ? (delta < 0) : (delta > 0)
            if isSatisfy {
                delta *= config.satisfyMul
                delta = min(max(delta, -30), 30)
            }
            var newVal = min(100, max(0, current + delta))
            // honest 特殊规则：不低于 90
            if config.dimKey == "honest" { newVal = max(90, newVal) }
            values[config.dimKey] = newVal
            changed = true
        }
        guard changed else { return }
        persistValues()
        recordSnapshot()
        markInteraction()
    }

    // MARK: - 自然增长 + 互抑制

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

        for config in dimConfigs where config.enabled {
            let current = value(forKey: config.dimKey)

            if !isDawnFreeze {
                var growth = config.growPerHour * hours
                if isNight { growth *= config.nightMul }
                if fatigueState != .awake { growth *= 0.5 }
                values[config.dimKey] = min(100, max(0, current + growth))
            }

            // keke 互抑制：仅对匹配 KekeStateDim 的维度生效
            if let dim = KekeStateDim(rawValue: config.dimKey) {
                for (inhibitor, factor) in dim.inhibitedBy {
                    let inhibitorVal = value(inhibitor) / 100.0
                    let suppression = inhibitorVal * factor * hours
                    values[config.dimKey] = max(0, (values[config.dimKey] ?? current) - suppression)
                }
            }

            // 天花板饱和衰减
            if let v = values[config.dimKey], v > 95 {
                // honest 不衰减
                if config.dimKey == "honest" { continue }
                let overflow = v - 95
                values[config.dimKey] = 95 + overflow * pow(0.9, hours)
            }
        }

        evolveThoughtPool(hours: hours)
        updateFatigueState()

        persistValues()
        if let last = snapshots.last, Date().timeIntervalSince(last.date) < 1800 { return }
        recordSnapshot()
    }

    // MARK: - 黎明冻结 & 夜间判定

    private func isDawnFreezeHour() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 1 && hour < 8
    }

    private func isNightHour() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 22 || hour < 6
    }

    // MARK: - 思绪池

    private let flashDecay: Double = 0.82
    private let obsessionGrowth: Double = 1.10
    private let obsessionThreshold: Double = 0.50
    private let obsessionMinAge: Int = 3
    private let feedbackThreshold: Double = 0.85
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
        let ticks = max(1, Int(hours * 2))
        for _ in 0..<min(ticks, 10) {
            for i in thoughts.indices {
                thoughts[i].age += 1
                if thoughts[i].isObsession {
                    thoughts[i].intensity = min(1.0, thoughts[i].intensity * obsessionGrowth)
                    if thoughts[i].intensity > feedbackThreshold && thoughts[i].feedbackCount < maxFeedbacks {
                        applyObsessionFeedback(thoughts[i])
                        thoughts[i].feedbackCount += 1
                    }
                } else {
                    thoughts[i].intensity *= flashDecay
                    if thoughts[i].intensity >= obsessionThreshold && thoughts[i].age >= obsessionMinAge {
                        thoughts[i].isObsession = true
                    }
                }
            }
            thoughts.removeAll { !$0.isObsession && $0.intensity < 0.05 }
        }
        saveHistory()
    }

    private func applyObsessionFeedback(_ thought: DriftThought) {
        let feedback = 0.18 * thought.intensity * 100
        // 推高 possess 和类似维度（如果存在）
        let targets: [(String, Double)] = [("possess", 0.4), ("pent", 0.4), ("sensitive", 0.2),
                                           ("d_possess", 0.3), ("d_crave", 0.3)]
        for (key, weight) in targets {
            if values[key] != nil {
                values[key] = min(100, values[key]! + feedback * weight)
            }
        }
    }

    // MARK: - 疲劳/睡眠周期

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

    func markInteraction() {
        defaults.set(Date().timeIntervalSince1970, forKey: key("state_last_interaction"))
        if fatigueState != .awake {
            fatigueState = .awake
        }
    }

    // MARK: - 意图选择

    func dominantDrive() -> (dimKey: String, label: String, intensity: Double) {
        var bestKey = dimConfigs.first?.dimKey ?? "possess"
        var bestLabel = dimConfigs.first?.label ?? "占有欲"
        var bestVal: Double = -1
        for config in dimConfigs where config.enabled {
            let v = value(forKey: config.dimKey) / 100.0 + Double.random(in: -0.12...0.12)
            var bonus: Double = 0
            if let obs = dominantObsession, obs.intensity > 0.5 {
                if ["possess", "pent", "sensitive", "d_possess", "d_crave"].contains(config.dimKey) {
                    bonus = obs.intensity * 0.15
                }
            }
            if v + bonus > bestVal {
                bestVal = v + bonus
                bestKey = config.dimKey
                bestLabel = config.label
            }
        }
        return (bestKey, bestLabel, min(1, max(0, bestVal)))
    }

    // MARK: - 持久化

    func curvePoints(forKey dimKey: String) -> [(date: Date, value: Double)] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var points: [(date: Date, value: Double)] = []
        for snap in snapshots where snap.date >= cutoff {
            if let v = snap.values[dimKey] {
                points.append((date: snap.date, value: v))
            }
        }
        points.append((date: Date(), value: value(forKey: dimKey)))
        return points
    }

    func curvePoints(for dim: KekeStateDim) -> [(date: Date, value: Double)] {
        curvePoints(forKey: dim.rawValue)
    }

    private func recordSnapshot() {
        snapshots.append(KekeStateSnapshot(date: Date(), values: values))
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        snapshots.removeAll { $0.date < cutoff }
        saveHistory()
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
