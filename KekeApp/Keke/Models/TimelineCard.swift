import Foundation

/// 一张时间线卡片：一条或几条碎片被整理成的**结构化**的一件事。
///
/// 类型只有 7 种，是**主动做的减法**。参考项目分了 17 种，但类型越多，
/// 模型越容易选错、越容易生成一堆空字段——这条是它自己在风险清单里写的。
///
/// `fragmentIDs` 是证据链，不是可选装饰：任何一张卡片都要能点回到
/// 它是从哪几条碎片来的。后面做洞察时，「凭什么这么说」全靠这条链。
struct TimelineCard: Identifiable, Codable, Equatable {

    enum Kind: String, Codable, CaseIterable {
        case event      // 发生过的一件事
        case todo       // 要做还没做的
        case routine    // 反复做的：习惯、打卡
        case quote      // 摘录、别人说的话、看到的一句
        case place      // 人与地点
        case metric     // 数值：体重、花销、评分
        case gallery    // 照片本身就是内容

        var displayName: String {
            switch self {
            case .event: return "事件"
            case .todo: return "待办"
            case .routine: return "打卡"
            case .quote: return "摘录"
            case .place: return "人与地点"
            case .metric: return "数值"
            case .gallery: return "相册"
            }
        }

        var icon: String {
            switch self {
            case .event: return "calendar"
            case .todo: return "checkmark.circle"
            case .routine: return "repeat"
            case .quote: return "quote.opening"
            case .place: return "mappin.and.ellipse"
            case .metric: return "number"
            case .gallery: return "photo.on.rectangle"
            }
        }

        /// 给模型看的「什么时候该选这个」。写得越具体，选错得越少
        var hint: String {
            switch self {
            case .event: return "发生过的一件具体的事。拿不准用哪个类型时选它"
            case .todo: return "还没做、打算做的事。只有明确是待办才用"
            case .routine: return "反复发生的：吃药、跑步、早睡这类打卡"
            case .quote: return "摘抄、听到看到的一句话、书里的段落"
            case .place: return "重点是某个人或某个地方"
            case .metric: return "有明确数字的：体重、花了多少钱、打几分"
            case .gallery: return "照片本身就是内容，没什么可说的"
            }
        }

        /// 这个类型额外要填的字段。**全都是可选的**——
        /// 强制要求填字段，换来的只会是模型编一个出来
        var fields: [FieldSpec] {
            switch self {
            case .event: return [FieldSpec("place", "地点")]
            case .todo: return [FieldSpec("due", "什么时候之前")]
            case .routine: return [FieldSpec("habit", "这是在坚持什么")]
            case .quote: return [FieldSpec("source", "出处")]
            case .place: return [FieldSpec("who", "人"), FieldSpec("where", "地方")]
            case .metric: return [FieldSpec("value", "数值"), FieldSpec("unit", "单位")]
            case .gallery: return []
            }
        }
    }

    struct FieldSpec: Equatable {
        let key: String
        let label: String
        init(_ key: String, _ label: String) {
            self.key = key
            self.label = label
        }
    }

    var id = UUID()
    /// 从哪几条碎片来的。**空数组是不允许的**——没有来源的卡片是凭空捏的
    var fragmentIDs: [UUID]
    var kind: Kind
    var title: String
    var detail: String = ""
    /// 这件事发生的时间，跟着碎片的 occurredAt 走
    var occurredAt: Date
    var createdAt: Date = Date()
    var tags: [String] = []
    /// 类型自己那几个字段。没填的就不放进来，不放空字符串占位
    var fields: [String: String] = [:]
    var imagePaths: [String] = []
    /// 规则兜底出来的，不是模型整理的。界面上要标出来——
    /// 用户有权知道这张卡是「没调通模型时凑合出来的」
    var byRule: Bool = false
    /// 待办打没打勾
    var done: Bool = false

    /// 有值的字段，按类型声明的顺序排好，界面直接用
    var orderedFields: [(label: String, value: String)] {
        kind.fields.compactMap { spec in
            guard let value = fields[spec.key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return (spec.label, value)
        }
    }
}
