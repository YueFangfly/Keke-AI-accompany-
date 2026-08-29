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
}
