import Foundation
import UserNotifications

/// 陪伴时段里她要说的一句话，以及该在第几分钟说。
struct CompanionLine: Codable, Equatable {
    /// 从按下开始那一刻算起的第几分钟。0 就是刚开始的时候
    var atMinute: Int
    var text: String
}

/// 一次陪伴时段的整张台词表。
struct CompanionPlan: Codable, Equatable {
    /// 按 `atMinute` 升序，含第 0 分钟那句
    var lines: [CompanionLine]
    /// 时间走完那一句。nil = 这次没生成出来，结束时再单独补一次
    var endingLine: String?

    var isEmpty: Bool { lines.isEmpty && endingLine == nil }

    /// 已经过去 `elapsedMinutes` 分钟时，她最近说的那句
    func current(elapsedMinutes: Int) -> String? {
        lines.last { $0.atMinute <= elapsedMinutes }?.text
    }
}

/// 陪伴时段的台词编排。
///
/// 参考 `woaini521-beta/woaini`（专注陪伴 PWA）的一个判断：
/// **陪伴的重量在过程里，不在结束那一下。** 克克原来只在时间到了才出声，
/// 中间那二十几分钟是哑的——可人正在干活的时候，恰恰就是 App 在后台、
/// 你压根不会盯着计时页面看的时候。
///
/// 于是台词**在按下开始的时候就一次性全部生成**，再排成本地通知。
/// 这不是为了省 token（虽然确实只花一次），是 iOS 上没有别的办法：
/// App 切到后台之后不会再有机会调 API，中途那几句必须提前排好队。
enum CompanionSession {

    /// 中途最多插几次话
    static let maxCheckpoints = 2

    // MARK: - 什么时候开口

    /// 中途插话的时间点（分钟，不含第 0 分钟和结束那一下）。
    ///
    /// 通知是会打断人的东西，**宁可少不可多**：
    /// 不到 12 分钟一次都不插（煮个泡面被喊两回只会让人想删 App），
    /// 12–40 分钟在正中间插一次，超过 40 分钟按 1/3、2/3 插两次。
    /// 再长也就两次——一小时里被喊三回已经不叫陪伴了
    static func checkpoints(totalMinutes: Int) -> [Int] {
        guard totalMinutes >= 12 else { return [] }
        if totalMinutes <= 40 { return [totalMinutes / 2] }
        return [totalMinutes / 3, totalMinutes * 2 / 3]
    }

    // MARK: - 解析

    /// 把模型回的那坨东西解析成台词表。
    ///
    /// **少几句是可以接受的**（她就少开口几回），但凡是留下来的必须是完整句子；
    /// 一句都没捞到就整个算失败，绝不把半截 JSON 当台词贴到界面上
    static func parse(_ raw: String, checkpoints: [Int]) -> CompanionPlan? {
        guard let json = CardParsing.extractJSONObject(raw),
              let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        var lines: [CompanionLine] = []
        if let start = cleaned(object["start"]) {
            lines.append(CompanionLine(atMinute: 0, text: start))
        }
        // 逐行取：中间有一句是空的不该把后面几句一起丢掉，
        // 所以先把整列按原顺序取出来再跟时间点对齐
        let middle = (object["middle"] as? [Any] ?? []).map { cleaned($0) }
        for (index, minute) in checkpoints.enumerated() where index < middle.count {
            if let text = middle[index] {
                lines.append(CompanionLine(atMinute: minute, text: text))
            }
        }

        let plan = CompanionPlan(lines: lines, endingLine: cleaned(object["end"]))
        return plan.isEmpty ? nil : plan
    }

    /// 模型偶尔会回 `null`、空串、或者一句只有引号的废话。三种都当没给
    private static func cleaned(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - 排通知

    /// 一组通知 id。
    ///
    /// 两个页面（陪伴计时器、番茄钟）各用各的前缀：共用一套 id 的话，
    /// 在其中一边按「先不计了」会把另一边排好的通知一起撤掉
    struct IDs {
        let prefix: String
        var end: String { prefix + "_done" }
        /// 番茄钟专用：休息结束。计时器那边没有休息这一段，留着不用也不碍事
        var rest: String { prefix + "_rest" }
        func mid(_ index: Int) -> String { prefix + "_mid_\(index)" }
        /// 取消时要一起撤掉的全部 id。少撤一个，人都退出了后台还会突然弹一句出来
        var all: [String] { [end, rest] + (0..<CompanionSession.maxCheckpoints).map(mid) }
    }

    static let timer = IDs(prefix: "keke_timer")
    static let pomodoro = IDs(prefix: "keke_pomodoro")

    /// 把台词排进系统通知。
    ///
    /// - 中途那几句各排各的时间点；台词回来得太慢、时间点已经过去了的就跳过
    ///   （`UNTimeIntervalNotificationTrigger` 不收 <= 0 的间隔，排了也是白排）
    /// - 结束那句**替换掉**开始时排的那条中性通知：按下开始的时候还不知道
    ///   她要说什么，只能先拿「「专注」25 分钟到了」占位，台词到了就换成她的话
    static func schedule(_ plan: CompanionPlan, startedAt: Date, totalMinutes: Int,
                         title: String, ids: IDs, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        var index = 0
        for line in plan.lines where line.atMinute > 0 {
            guard index < maxCheckpoints else { break }
            let delay = startedAt.addingTimeInterval(TimeInterval(line.atMinute * 60))
                .timeIntervalSince(now)
            index += 1
            guard delay > 0 else { continue }
            center.add(request(id: ids.mid(index - 1), title: title,
                               body: line.text, delay: delay))
        }
        if let ending = plan.endingLine {
            let delay = startedAt.addingTimeInterval(TimeInterval(totalMinutes * 60))
                .timeIntervalSince(now)
            guard delay > 0 else { return }
            // 同一个 id 再 add 一次就是覆盖，不用先 remove
            center.add(request(id: ids.end, title: title, body: ending, delay: delay))
        }
    }

    private static func request(id: String, title: String, body: String,
                                delay: TimeInterval) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        return UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
    }
}
