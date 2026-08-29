import Foundation

/// 路由层给出的判断：这一轮要不要动工具、要不要带记忆。
///
/// 这个结构是**端上模型和降级路径共用**的形状。端上模型不可用、超时、
/// 或者解析失败时，一律退回 `.passthrough`，上层不用关心是哪种情况。
struct RouteDecision: Equatable {
    /// 这轮需不需要工具。false = 日常闲聊，直接一跳到主模型
    var needsTool: Bool
    /// 需不需要把长期记忆块塞进上下文
    var needsMemory: Bool
    /// 端上模型觉得多半会用到哪个工具。只是提示，主模型仍然自己决定
    var suggestedTool: String?
    /// 端上模型有没有真的参与
    var routedOnDevice: Bool
    /// 路由花了多少毫秒
    var routeMs: Int

    /// 降级默认值：当直连用。
    ///
    /// needsTool 给 false 是故意的——端上模型没跑成的时候，宁可少挂工具直接聊，
    /// 也不要为了"保险"每轮都挂上全量工具让模型乱调。
    /// needsMemory 给 true 也是故意的：记忆是人格的一部分，宁可多花点 token 也不能丢。
    static func passthrough(routeMs: Int = 0) -> RouteDecision {
        RouteDecision(needsTool: false, needsMemory: true,
                      suggestedTool: nil, routedOnDevice: false, routeMs: routeMs)
    }

    var trace: RouteTrace {
        RouteTrace(routedOnDevice: routedOnDevice, needsTool: needsTool,
                   needsMemory: needsMemory, suggestedTool: suggestedTool,
                   toolsRun: [], routeMs: routeMs)
    }
}

/// 路由层的配置
enum RouteConfig {
    /// 路由的硬超时。端上模型再快也不是 0，超了直接走直连——
    /// 「日常闲聊零额外延迟」靠的是这个上限，不是赌它一定快
    static let timeoutMs = 150

    /// 给端上模型的指令。写得越短判断越快
    static let instructions = """
    你是一个分流器，不是聊天助手。看用户这句话，只判断两件事：

    1. needsTool：要不要查外部信息才能答（天气、汇率、新闻、翻译、\
    设闹钟、放音乐这类）。纯闲聊、情绪表达、回忆过去的事 → false。
    2. needsMemory：要不要翻长期记忆才能答（提到过去的事、人名、\
    约定、习惯）→ true；纯粹当下的一句话 → false。

    不要回答用户的问题，只给判断。
    """
}
