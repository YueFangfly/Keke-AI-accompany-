import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// 端上模型路由。
///
/// 整块用 `#if canImport(FoundationModels)` 包起来：Xcode 16 的 SDK 里没有这个框架，
/// 编译时整段被剔掉，iOS 16.1 的部署目标照常构建。Xcode 26 上才会真的编进去，
/// 运行时再用 `@available(iOS 26, *)` 和可用性检查过一道。
///
/// **项目现在的部署目标是 iOS 16.1，所以绝大多数设备上走的都是降级直连。**
/// 这一层是为将来准备的，不是今天的主路径。
///
/// 三种情况一律降级成 `RouteDecision.passthrough`，上层不用分辨是哪种：
/// 框架不存在、系统版本不够 / 模型没就绪、超时或抛错。
enum OnDeviceRouter {

    /// 判断这一轮要怎么走。**这个函数不会抛错，也不会卡住** ——
    /// 最坏情况是等 RouteConfig.timeoutMs 然后返回 passthrough
    static func decide(userText: String) async -> RouteDecision {
        let startedAt = Date()
        func elapsedMs() -> Int { Int(Date().timeIntervalSince(startedAt) * 1000) }

        #if canImport(FoundationModels)
        if #available(iOS 26, *), isAvailable {
            if let decision = await withTimeout(ms: RouteConfig.timeoutMs, work: {
                await classify(userText: userText)
            }) ?? nil {
                return RouteDecision(needsTool: decision.needsTool,
                                     needsMemory: decision.needsMemory,
                                     suggestedTool: decision.suggestedTool,
                                     routedOnDevice: true,
                                     routeMs: elapsedMs())
            }
        }
        #endif
        return .passthrough(routeMs: elapsedMs())
    }

    /// 端上模型现在能不能用。系统版本、设备支持、用户有没有开智能功能，
    /// 任何一项不满足都算不可用
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// 给 work 一个时限。超时返回 nil（外层再摊平成 passthrough）。
    ///
    /// 超时之后那个任务会被取消，但即使它后来才结束也没人接结果了——
    /// 这里要的是「用户不用等」，不是「一定拿到答案」
    private static func withTimeout<T: Sendable>(
        ms: Int, work: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

#if canImport(FoundationModels)

/// 端上模型要填的结构。@Generable 让它按这个形状产出，不用自己解析自由文本
@available(iOS 26, *)
@Generable
struct OnDeviceRoute {
    @Guide(description: "要不要查外部信息（天气、汇率、新闻、翻译、闹钟、音乐）才能回答。纯闲聊和情绪表达填 false")
    var needsTool: Bool

    @Guide(description: "要不要翻长期记忆才能回答。提到过去的事、人名、约定、习惯就填 true")
    var needsMemory: Bool

    @Guide(description: "如果需要工具，猜一个最可能用到的工具名；不确定就留空")
    var suggestedTool: String
}

@available(iOS 26, *)
extension OnDeviceRouter {
    /// 真正问端上模型。任何异常都吞掉返回 nil，由外层降级
    static func classify(userText: String) async -> (needsTool: Bool, needsMemory: Bool, suggestedTool: String?)? {
        do {
            let session = LanguageModelSession(instructions: RouteConfig.instructions)
            let response = try await session.respond(to: userText, generating: OnDeviceRoute.self)
            let route = response.content
            let suggested = route.suggestedTool.trimmingCharacters(in: .whitespacesAndNewlines)
            return (route.needsTool, route.needsMemory, suggested.isEmpty ? nil : suggested)
        } catch {
            return nil
        }
    }
}

#endif
