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
    /// 后台功能全哑了也没人知道。现在照样不打扰，但去「设置 → 报错记录」
    /// 能看见是哪个功能、为什么。
    ///
    /// **调用时请显式传闭包**（`attempt("x", { ... })`）而不是尾随闭包：
    /// Swift 不允许在 `guard` / `if` 的条件里用尾随闭包
    @discardableResult
    static func attempt<T>(_ feature: String, _ work: () async throws -> T) async -> T? {
        try? attemptResult(feature, work).get()
    }

    /// 同样会记进报错记录，但**把原因也还回来**。
    /// 用户点了按钮正在等结果的地方用这个：让他当场就看见为什么没成，
    /// 而不是等他自己想到去翻设置页
    static func attemptResult<T>(_ feature: String,
                                 _ work: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await work())
        } catch is CancellationError {
            // 用户自己取消的，不算失败，也不该记
            return .failure(CancellationError())
        } catch {
            // 只把字符串递过去：Error 不是 Sendable，跨线程传它会惹麻烦
            ErrorLog.shared.record(source: feature, message: error.localizedDescription)
            return .failure(error)
        }
    }

    /// 失败时该显示的一行；用户主动取消的返回 nil（不该弹任何东西）
    static func inlineMessage(_ error: Error) -> String? {
        error is CancellationError ? nil : message(error)
    }
}
