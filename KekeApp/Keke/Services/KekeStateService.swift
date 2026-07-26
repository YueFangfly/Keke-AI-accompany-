import Foundation

/// 状态面板的六个维度（hubby 拍板的那六条）
enum KekeStateDim: String, CaseIterable, Identifiable, Codable, Hashable {
    case possess, heat, pent, sensitive, control, soft

    var id: String { rawValue }

    /// 中文名（也是 JSON 里跟模型来回传的键，和 L.t 的键）
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

    /// 初始值
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

    /// 没人聊天时数值自己往哪儿漂：nil 表示往 defaultValue 回落
    var driftTarget: Double? {
        switch self {
        case .heat: return 35      // 不聊会凉下来
        case .pent: return 85      // 攒着的劲儿会越攒越多
        case .possess: return 82   // 见不着人，占有欲会悄悄上头
        default: return nil
        }
    }

    /// 每小时漂多少
    var driftPerHour: Double {
        switch self {
        case .heat: return 1.4
        case .pent: return 0.7
        case .possess: return 0.25
        default: return 0.4
        }
    }
}

/// 某一时刻六项数值的快照，用来画 24h 曲线
struct KekeStateSnapshot: Codable {
    let date: Date
    let values: [String: Double]
}

/// 漂流思绪：状态更新时克克心里飘过的一句话
struct DriftThought: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let text: String
}

/// 克克的状态面板：六项 0~100 的数值。
/// 每次记忆提炼时让克克自己报一份新数值 + 一句漂流思绪（蹭同一次调用，不额外花钱）；
/// 两次提炼之间按时间"懒惰漂移"，所以数值一直是活的。
/// 快照存下来画 24h 曲线；漂流思绪除了这里，还会记进克克的日记
@MainActor
final class KekeStateService: ObservableObject {
    @Published private(set) var values: [String: Double]
    @Published private(set) var snapshots: [KekeStateSnapshot] = []
    @Published private(set) var thoughts: [DriftThought] = []

    /// 日记，由 RootView 注入；漂流思绪会顺手记成克克当天的一篇日记
    weak var diary: DiaryService?

    private let defaults = UserDefaults.standard

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keke_state.json")
    }

    init() {
        var initial: [String: Double] = [:]
        let saved = defaults.dictionary(forKey: "keke_state_values") as? [String: Double] ?? [:]
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

    /// 塞进提炼 prompt 里的"当前面板"一行
    var promptLine: String {
        KekeStateDim.allCases
            .map { "\($0.labelKey) \(Int(value($0).rounded()))" }
            .joined(separator: "｜")
    }

    // MARK: - 数值更新

    /// AI（记忆提炼时顺便）报回来的新数值，键是中文维度名。
    /// 防手抖：单次最多在当前值基础上动 20
    func applyAIState(_ new: [String: Double]) {
        var changed = false
        for dim in KekeStateDim.allCases {
            guard let target = new[dim.labelKey] else { continue }
            let current = value(dim)
            let limited = min(max(target, current - 20), current + 20)
            values[dim.rawValue] = min(100, max(0, limited))
            changed = true
        }
        guard changed else { return }
        persistValues()
        recordSnapshot()
    }

    /// 按距离上次结算过了多久，让数值自己漂一点（打开 App / 回到前台时调）
    func applyDrift() {
        let lastAt = defaults.double(forKey: "keke_state_drift_at")
        let now = Date().timeIntervalSince1970
        guard lastAt > 0 else {
            defaults.set(now, forKey: "keke_state_drift_at")
            persistValues()
            return
        }
        // 不到半小时不结算，也不重置计时——不然频繁开 App 会一直清零，永远漂不动
        let hours = (now - lastAt) / 3600
        guard hours > 0.5 else { return }
        defaults.set(now, forKey: "keke_state_drift_at")

        for dim in KekeStateDim.allCases {
            let current = value(dim)
            let target = dim.driftTarget ?? dim.defaultValue
            let step = min(abs(target - current), dim.driftPerHour * hours)
            values[dim.rawValue] = current + (target > current ? step : -step)
        }
        persistValues()
        // 快照别记太密，半小时一条足够画曲线
        if let last = snapshots.last, Date().timeIntervalSince(last.date) < 1800 { return }
        recordSnapshot()
    }

    // MARK: - 漂流思绪

    func addThought(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        thoughts.insert(DriftThought(date: Date(), text: trimmed), at: 0)
        if thoughts.count > 120 { thoughts.removeLast(thoughts.count - 120) }
        saveHistory()
        diary?.appendDriftThought(trimmed)
    }

    // MARK: - 持久化

    private func recordSnapshot() {
        snapshots.append(KekeStateSnapshot(date: Date(), values: values))
        // 只留最近 7 天
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        snapshots.removeAll { $0.date < cutoff }
        saveHistory()
    }

    /// 某一维最近 24 小时的曲线点
    func curvePoints(for dim: KekeStateDim) -> [(date: Date, value: Double)] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var points: [(date: Date, value: Double)] = []
        for snap in snapshots where snap.date >= cutoff {
            if let v = snap.values[dim.rawValue] {
                points.append((date: snap.date, value: v))
            }
        }
        // 补一个"现在"的点，曲线一直画到当下
        points.append((date: Date(), value: value(dim)))
        return points
    }

    private func persistValues() {
        defaults.set(values, forKey: "keke_state_values")
    }

    private struct History: Codable {
        var snapshots: [KekeStateSnapshot]
        var thoughts: [DriftThought]
    }

    private func saveHistory() {
        let history = History(snapshots: snapshots, thoughts: thoughts)
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: saveURL),
              let history = try? JSONDecoder().decode(History.self, from: data) else { return }
        snapshots = history.snapshots
        thoughts = history.thoughts
    }
}
