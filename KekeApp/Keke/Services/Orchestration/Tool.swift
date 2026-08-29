import Foundation

// 统一的工具协议。
//
// 原则：确定性的活（天气、日历、时间、本地查询）用纯 Swift 直接调 API，
// 不绕道 LLM——绕一圈只会更慢、更贵、更容易编。
// 只有长文压缩、多步筛选这类脏活才交给便宜模型，而且必须给字数上限。
//
// 克克里本来就有一套 MCPModule（天气、翻译、汇率、音乐、闹钟、新闻），
// 全是纯 Swift 直连。这里不推倒重来，下面有适配器把它们接过来，
// 新代码只看见 Tool。

// MARK: - 结果

/// 工具跑完的结果。
///
/// 包成结构体而不是裸 String，是为了让「打标签」和「截断」在
/// ToolResultEnvelope 一个地方强制执行，而不是指望每个工具自觉。
struct ToolOutput {
    let text: String
    /// 工具自己失败了（参数不对、网络挂了）。模型该知道，但别当成数据
    var isError: Bool = false
    /// 内容是从外部拿回来的（网页、搜索结果、第三方 API 的自由文本）。
    /// 这种要更强的隔离——它可能夹带试图指挥模型的文字
    var isExternalData: Bool = false

    static func error(_ message: String) -> ToolOutput {
        ToolOutput(text: message, isError: true)
    }
}

// MARK: - 协议

protocol Tool {
    /// 给模型看的函数名，也是工具调用时的标识
    var name: String { get }
    var descriptionForModel: String { get }
    /// JSON Schema 的 properties 部分。跟 ClaudeService.toolSchema 的形状对齐：
    /// 每个参数名映射到它自己那份 schema 字典
    var parameters: [String: [String: Any]] { get }
    var required: [String] { get }

    /// 这个工具最多能往上下文里塞多少字符。
    /// 不是建议值——超了由 ToolResultEnvelope 直接截断
    var maxOutputChars: Int { get }

    /// 这活要不要交给便宜模型。确定性的活一律 false
    var needsSubModel: Bool { get }

    func run(_ input: [String: Any]) async -> ToolOutput
}

extension Tool {
    var maxOutputChars: Int { 4000 }
    var needsSubModel: Bool { false }

    /// 转成 Claude 的工具定义
    var schema: [String: Any] {
        ClaudeService.toolSchema(name: name, description: descriptionForModel,
                                 properties: parameters, required: required)
    }
}

// MARK: - 注册表

/// 当前可用的工具。
///
/// 注意工具集合要**保持稳定**：Claude 的 prompt caching 是前缀匹配，
/// 渲染顺序是 tools → system → messages，tools 一变整个缓存前缀就作废。
/// 所以这里按固定顺序返回全量工具，路由的结果不用来增删 tools，
/// 只用来决定「要不要注入记忆」和「要不要跑工具循环」
struct ToolRegistry {
    let tools: [Tool]

    init(tools: [Tool]) {
        // 排序固定下来，免得字典遍历顺序变化把缓存前缀搞失效
        self.tools = tools.sorted { $0.name < $1.name }
    }

    func tool(named name: String) -> Tool? {
        tools.first { $0.name == name }
    }

    var schemas: [[String: Any]] { tools.map(\.schema) }

    /// 跑一个工具，结果统一过封装。
    /// 找不到的工具也返回封装过的错误，不返回裸字符串
    func run(name: String, input: [String: Any]) async -> String {
        guard let tool = tool(named: name) else {
            return ToolResultEnvelope.wrap(.error("没有这个工具"), toolName: name, maxChars: 200)
        }
        let output = await tool.run(input)
        return ToolResultEnvelope.wrap(output, toolName: name, maxChars: tool.maxOutputChars)
    }
}

// MARK: - 老模块适配

/// 把现有的 MCPModule 接进 Tool。
///
/// MCPModule 一个模块可能带好几个工具，所以一个模块会拆成好几个 Adapter，
/// 每个只认自己那一个 name
struct MCPToolAdapter: Tool {
    let name: String
    let descriptionForModel: String
    let parameters: [String: [String: Any]]
    let required: [String]
    private let module: any MCPModule

    /// 这些模块拿回来的都是第三方 API 的自由文本（天气服务、新闻源、汇率站），
    /// 一律按外部数据处理
    var isExternalData: Bool { true }

    func run(_ input: [String: Any]) async -> ToolOutput {
        let text = await module.execute(toolName: name, input: input)
        return ToolOutput(text: text, isExternalData: isExternalData)
    }

    /// 从一个模块的某个 schema 建适配器。schema 形状对不上就返回 nil
    init?(module: any MCPModule, schema: [String: Any]) {
        guard let name = schema["name"] as? String else { return nil }
        self.module = module
        self.name = name
        self.descriptionForModel = schema["description"] as? String ?? ""
        let inputSchema = schema["input_schema"] as? [String: Any]
        self.parameters = inputSchema?["properties"] as? [String: [String: Any]] ?? [:]
        self.required = inputSchema?["required"] as? [String] ?? []
    }
}

extension MCPRegistry {
    /// 已启用的模块摊平成工具列表
    func enabledTools() -> [Tool] {
        modules
            .filter { isEnabled($0.id) }
            .flatMap { module in
                module.toolSchemas.compactMap { MCPToolAdapter(module: module, schema: $0) }
            }
    }
}
