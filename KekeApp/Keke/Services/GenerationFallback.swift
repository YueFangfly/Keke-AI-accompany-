import Foundation

/// 生成失败时显示什么。
///
/// **规矩：App 不替角色说话。**
///
/// 以前每个生成点都写死了一句兜底话——「*叉腰*」「*摸摸头*」「效率小猫奖励你一个 *蹭蹭*」。
/// 三个问题：
/// 1. 人设由用户自己写，App 编的句子多半跟人设对不上，角色会突然变成另一个人
/// 2. 这些话会被存进游戏记录、签文、闹钟、甚至聊天记录里，看起来像角色真说过
/// 3. 最要命的是它把失败**藏起来了**：Key 填错、断网、额度用完，用户看到的
///    都是一句正常的俏皮话，根本不知道功能已经坏了
///
/// 现在：正文一律由用户自己的人设 prompt 生成；生成不出来就直说，并且带上原因。
enum GenerationFallback {

    /// 跑一次生成。空结果也算失败——模型回了个空字符串跟没回是一回事
    static func run(_ work: () async throws -> String) async -> Result<String, Error> {
        do {
            let text = try await work().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .failure(AIError.badResponse("这次没生成出内容")) }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    /// 失败时给用户看的一行。原因照抄不加工——
    /// `APIFailure` 那边已经把「Key 不对」「断网」「限流」写成人话了
    static func message(_ error: Error) -> String {
        "（没生成出来：\(error.localizedDescription)）"
    }

    /// 成功用正文、失败用说明。适合**只是显示一下、不会被存起来**的地方；
    /// 会落库的（签文、闹钟、游戏记录）请用 `run` 自己分情况处理，
    /// 别把一句错误说明当正文存进去
    static func resolve(_ work: () async throws -> String) async -> String {
        switch await run(work) {
        case .success(let text): return text
        case .failure(let error): return message(error)
        }
    }

    /// `try?` 的替代品：**行为一样**（失败返回 nil），但会把失败记下来。
    ///
    /// 后台自动跑的那些（提炼记忆、自动发朋友圈、日记回应、主动冒泡…）没人在等，
    /// 弹报错只会烦人；可它们原来用 `try?` 一声不吭地失败，Key 填错了整个
    /// 后台功能全哑了也没人知道。现在照样不打扰，但去「设置 → 最近的生成失败」
    /// 能看见是哪个功能、为什么。
    ///
    /// **调用时请显式传闭包**（`attempt("x", { ... })`）而不是尾随闭包：
    /// Swift 不允许在 `guard` / `if` 的条件里用尾随闭包
    @discardableResult
    static func attempt<T>(_ feature: String, _ work: () async throws -> T) async -> T? {
        do {
            return try await work()
        } catch is CancellationError {
            return nil          // 用户自己取消的，不算失败
        } catch {
            // 只把字符串递过去：Error 不是 Sendable，跨线程传它会惹麻烦
            GenerationDiagnostics.shared.record(feature: feature,
                                                reason: error.localizedDescription)
            return nil
        }
    }
}

/// 最近一批「悄悄失败了」的生成，给设置页看。
///
/// 只留在内存里、只留最近几条：它是排查用的，不是日志系统。
/// App 一关就没了——真正该长期记的是用量统计那份
///
/// 类本身不标 `@MainActor`：后台任务从任意线程调 `record`，
/// 而 `shared` 要能在任意上下文里取到。改动统一在 `record` 里跳回主线程做，
/// `recent` 因此始终只在主线程上被读写
final class GenerationDiagnostics: ObservableObject {
    static let shared = GenerationDiagnostics()

    struct Entry: Identifiable {
        let id = UUID()
        let at: Date
        let feature: String
        let reason: String
    }

    /// 最近的在前
    @Published private(set) var recent: [Entry] = []
    private let limit = 20

    private init() {}

    func record(feature: String, reason: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 同一个功能连着报同一个错就不重复堆——后台任务可能几分钟触发一次，
            // 一个配置错误能瞬间把列表刷满
            if let first = self.recent.first,
               first.feature == feature, first.reason == reason { return }
            self.recent.insert(Entry(at: Date(), feature: feature, reason: reason), at: 0)
            if self.recent.count > self.limit {
                self.recent.removeLast(self.recent.count - self.limit)
            }
        }
    }

    @MainActor
    func clear() { recent.removeAll() }
}
