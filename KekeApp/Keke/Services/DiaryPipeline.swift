import Foundation

/// 一件排着队要做的事。
///
/// 「读图」和「整理成卡片」串起来是几十秒，而 iOS 随时可能把 App 挂起。
/// 之前这两件事各自 `Task { }` 一发就不管了——App 一被杀，做了一半的活
/// 无声无息地没了，而且**丢得没有规律**，事后根本查不出来。
///
/// 所以要落盘。落盘之后才谈得上依赖顺序、重试上限和「放弃时说一声」。
struct PipelineTask: Identifiable, Codable, Equatable {
    enum Job: String, Codable {
        case analyze   // 读图：EXIF + 标签 + 图里的文字
        case card      // 整理成卡片

        var displayName: String {
            switch self {
            case .analyze: return "读图"
            case .card: return "整理卡片"
            }
        }
    }

    var id = UUID()
    var job: Job
    var fragmentID: UUID
    /// 要等哪个任务做完。读图没做完就整理卡片，模型只能看着一个文件名瞎猜
    var dependsOn: UUID? = nil
    var attempts: Int = 0
    var lastError: String? = nil
    /// 最早什么时候可以再试。退避靠它，不靠 sleep
    var nextAttemptAt: Date = Date()
    var createdAt: Date = Date()
}

/// 排班表。**纯函数**：不碰网络、不碰磁盘、不看时钟（`now` 是传进来的）。
///
/// 这样它就能被单独验证——而流水线这种东西，出错的方式往往是
/// 「某个任务永远轮不到」或者「某个任务永远重试」，靠肉眼看代码看不出来。
enum PipelinePlanner {

    /// 试几次就放弃。放弃时要说一声，不能就这么消失
    static let maxAttempts = 3

    /// 第 n 次失败之后等多久再试（秒）。指数退避、有上限。
    ///
    /// 单位取得比较大是因为**排班是用户触发的**（打开日记页、App 回到前台），
    /// 不是后台轮询——秒级重试在这里没有意义，只会在同一次打开里连撞三次。
    static func retryDelay(afterAttempts attempts: Int) -> TimeInterval {
        let steps: [TimeInterval] = [30, 120, 480]
        guard attempts >= 1 else { return steps[0] }
        return steps[min(attempts, steps.count) - 1]
    }

    enum Drop: Equatable {
        /// 碎片被删了，这活没有意义了
        case orphaned
        /// 已经有卡片了，不用再整理
        case alreadyDone
        /// 试到头了
        case gaveUp(String?)
    }

    struct Plan: Equatable {
        /// 这一轮可以跑的，已经排好顺序
        var runnable: [PipelineTask] = []
        /// 这一轮该扔掉的，附上原因
        var drops: [(task: PipelineTask, reason: Drop)] = []

        static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.runnable == rhs.runnable
                && lhs.drops.count == rhs.drops.count
                && zip(lhs.drops, rhs.drops).allSatisfy { $0.task == $1.task && $0.reason == $1.reason }
        }
    }

    /// 排这一轮。
    ///
    /// 四条规则，顺序有意义：
    /// 1. 碎片没了 → 扔掉（否则它会永远重试一个不存在的东西）
    /// 2. 卡片已经有了 → 扔掉整理任务
    /// 3. 试满了 → 扔掉，并且**带上最后一次的错误**，好让上层能记进 ErrorLog
    /// 4. 依赖还在队列里 → 这轮不跑，但也不扔；等下一轮
    static func plan(queue: [PipelineTask],
                     now: Date,
                     liveFragmentIDs: Set<UUID>,
                     organizedFragmentIDs: Set<UUID>) -> Plan {
        var plan = Plan()
        // 还留在队列里的任务 id：依赖判断看的是这个，不是「跑没跑过」
        let pending = Set(queue.map(\.id))

        for task in queue {
            if !liveFragmentIDs.contains(task.fragmentID) {
                plan.drops.append((task, .orphaned))
                continue
            }
            if task.job == .card, organizedFragmentIDs.contains(task.fragmentID) {
                plan.drops.append((task, .alreadyDone))
                continue
            }
            if task.attempts >= maxAttempts {
                plan.drops.append((task, .gaveUp(task.lastError)))
                continue
            }
            if let dependency = task.dependsOn, pending.contains(dependency) {
                continue   // 前置还没做完，这轮跳过
            }
            guard task.nextAttemptAt <= now else { continue }   // 还在退避里
            plan.runnable.append(task)
        }

        // 先来的先跑；同一时刻入队的，读图排在整理前面
        plan.runnable.sort { left, right in
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            return left.job == .analyze && right.job == .card
        }
        return plan
    }
}

// MARK: - 跑班的

/// 把排班表真的跑起来。
///
/// 触发时机学朋友圈那套**惰性时序**：打开日记页、App 回到前台的时候排一轮，
/// 不开后台任务。iOS 对后台执行的限制摆在那儿，跟系统对着干只会两头落空。
@MainActor
final class DiaryPipeline: ObservableObject {
    let personaId: String
    @Published private(set) var queue: [PipelineTask] = []
    /// 正在跑这一轮吗。防止打开页面和回到前台同时触发，把同一批活跑两遍
    @Published private(set) var draining = false

    /// 弱引用，都是 App 生命周期里的单例。强引用会绕成环
    weak var fragments: FragmentStore?
    weak var cards: CardStore?
    weak var chat: ChatStore?

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_pipeline.json")
    }

    init(personaId: String = "keke") {
        self.personaId = personaId
        load()
    }

    // MARK: - 入队

    /// 一条新照片进来：先读图，读完再整理。**整理依赖读图**
    func enqueuePhoto(_ fragmentID: UUID) {
        let analyze = PipelineTask(job: .analyze, fragmentID: fragmentID)
        var card = PipelineTask(job: .card, fragmentID: fragmentID)
        card.dependsOn = analyze.id
        queue.append(analyze)
        queue.append(card)
        save()
    }

    /// 纯文字 / 语音碎片：没有图可读，直接排整理
    func enqueueCard(_ fragmentID: UUID) {
        guard !queue.contains(where: { $0.fragmentID == fragmentID && $0.job == .card }) else { return }
        queue.append(PipelineTask(job: .card, fragmentID: fragmentID))
        save()
    }

    func cancelAll(for fragmentID: UUID) {
        queue.removeAll { $0.fragmentID == fragmentID }
        save()
    }

    /// 排一轮，能跑就跑
    func kick() {
        guard !draining else { return }
        Task { await drain() }
    }

    // MARK: - 跑

    func drain(now: Date = Date()) async {
        guard !draining else { return }
        guard let fragments, let cards, let chat else { return }
        draining = true
        defer { draining = false }

        let plan = PipelinePlanner.plan(
            queue: queue, now: now,
            liveFragmentIDs: Set(fragments.fragments.map(\.id)),
            organizedFragmentIDs: cards.organizedFragmentIDs)

        // 先清掉不用跑的。放弃的那些**必须留痕**——
        // 静默消失正是当初 `Task { }` 一发就不管的毛病
        for (task, reason) in plan.drops {
            if case .gaveUp(let last) = reason {
                ErrorLog.shared.record(
                    source: "碎片流水线",
                    message: "\(task.job.displayName)试了 \(PipelinePlanner.maxAttempts) 次还是不行，放弃了"
                             + (last.map { "：\($0)" } ?? ""))
            }
            remove(task.id)
        }

        // 一条一条跑。并发跑几十条要么撞限速，要么把便宜模型的额度打爆
        for task in plan.runnable {
            // 每次都重新取：上一个任务（读图）刚刚把 analysis 填上，
            // 拿旧的那份去整理，等于白读了一次图
            guard let fragment = fragments.fragments.first(where: { $0.id == task.fragmentID }) else {
                remove(task.id)
                continue
            }

            // **最后一次机会才允许兜底**。前面几次不兜底，一次断网才不会被
            // 永久地固化成一张朴素的规则卡片；到了最后一次就必须给出东西
            let lastChance = task.attempts >= PipelinePlanner.maxAttempts - 1

            let done: Bool
            switch task.job {
            case .analyze:
                // 读图失败不拦着后面：图读不懂，卡片照样该整理，
                // 只是模型少了一点线索。拦下来等于因为读不懂图就丢掉整条碎片
                done = await fragments.analyzeNow(fragment) || lastChance
            case .card:
                done = await CardGenerator.organize(fragment, into: cards, store: chat,
                                                    allowFallback: lastChance)
            }

            if done {
                remove(task.id)
            } else {
                fail(task.id, reason: lastFailure(for: task, fragment: fragment), now: now)
            }
        }
    }

    /// 这次为什么没成。尽量说具体点——`ErrorLog` 里出现「失败了」三个字，
    /// 对排查毫无帮助
    private func lastFailure(for task: PipelineTask, fragment: Fragment) -> String {
        switch task.job {
        case .analyze:
            return fragment.analysis?.failure ?? "这张图没读出东西"
        case .card:
            return "模型没给出能用的卡片"
        }
    }

    /// 失败一次：记次数、算退避、留下最后的错误。**任务不删**
    func fail(_ id: UUID, reason: String, now: Date = Date()) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].attempts += 1
        queue[index].lastError = reason
        queue[index].nextAttemptAt = now.addingTimeInterval(
            PipelinePlanner.retryDelay(afterAttempts: queue[index].attempts))
        save()
    }

    private func remove(_ id: UUID) {
        queue.removeAll { $0.id == id }
        save()
    }

    // MARK: - 持久化

    private func save() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([PipelineTask].self, from: data) else { return }
        queue = saved
    }
}
