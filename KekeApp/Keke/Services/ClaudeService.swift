import Foundation
import CoreGraphics

enum AIError: LocalizedError {
    case noAPIKey(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey(let provider):
            return "还没有填 \(provider) 的 API Key，去左边菜单的「设置」里填一下"
        case .badResponse(let message):
            return message
        }
    }
}

/// 多家 AI 的调用入口：Claude 走 Anthropic Messages API，
/// DeepSeek / GPT / Grok 走 OpenAI 兼容的 Chat Completions 格式。
/// 命名保留 ClaudeService 是历史原因，现在其实服务所有提供方。
enum ClaudeService {

    /// 单个参数的 JSON Schema（比如 {"type": "string", "enum": [...], "description": "..."}）。
    /// 拆成小函数、每个都有明确的返回类型，是为了让编译器不用去猜一大坨嵌套字面量的类型，
    /// 不然会报"Heterogeneous collection literal"或直接卡住类型检查
    static func stringSchema(enumValues: [String]? = nil, description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "string"]
        if let enumValues { schema["enum"] = enumValues }
        if let description { schema["description"] = description }
        return schema
    }

    static func intSchema(enumValues: [Int]? = nil, description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "integer"]
        if let enumValues { schema["enum"] = enumValues }
        if let description { schema["description"] = description }
        return schema
    }

    static func boolSchema(description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "boolean"]
        if let description { schema["description"] = description }
        return schema
    }

    static func numberSchema(description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "number"]
        if let description { schema["description"] = description }
        return schema
    }

    /// 一个工具的完整定义
    static func toolSchema(name: String, description: String,
                           properties: [String: [String: Any]],
                           required: [String]) -> [String: Any] {
        let inputSchema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required,
        ]
        return ["name": name, "description": description, "input_schema": inputSchema]
    }

    /// 聊天里能直接调用的工具（改设置 + 建提醒/日程）；名字对应 ChatStore.executeSettingsTool 里的
    /// switch 分支。只有 Claude 支持客户端工具调用，其他家 API 暂不接这个。
    /// 做成计算属性是因为建提醒的工具描述里要带上"现在几点"，模型才能换算"明天下午三点"这种相对时间
    static var settingsTools: [[String: Any]] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm EEEE"
        let now = formatter.string(from: Date())

        return staticSettingsTools + [
            toolSchema(
                name: "create_reminder",
                description: "在她 iPhone 的系统「提醒事项」里帮她建一条提醒。现在的时间是 \(now)，"
                    + "她说的「明天」「周四下午」这类相对时间按这个换算。只有她明确让你帮忙记/提醒的时候才调用。",
                properties: [
                    "title": stringSchema(description: "提醒的内容，简短一句，比如「交作业」"),
                    "due": stringSchema(description: "到期时间，格式 yyyy-MM-dd HH:mm（24小时制）；她没提时间就省略这个参数"),
                    "notes": stringSchema(description: "备注，可省略"),
                ],
                required: ["title"]
            ),
            toolSchema(
                name: "create_calendar_event",
                description: "在她 iPhone 的系统日历里帮她建一个日程。现在的时间是 \(now)。"
                    + "只有她明确让你帮忙记日程/安排的时候才调用。",
                properties: [
                    "title": stringSchema(description: "日程标题"),
                    "start": stringSchema(description: "开始时间，格式 yyyy-MM-dd HH:mm（24小时制）"),
                    "end": stringSchema(description: "结束时间，同样格式；可省略，默认一小时"),
                    "notes": stringSchema(description: "备注，可省略"),
                ],
                required: ["title", "start"]
            ),
        ]
    }

    private static let staticSettingsTools: [[String: Any]] = [
        toolSchema(
            name: "set_diary_probability",
            description: "调整「私密日记」功能里的概率：克克每天写日记的概率、我偷看她没公开的日记时被她发现的概率、"
                + "她翻到我分享给她的日记并读完的概率。只有用户明确要求调整这几个概率时才调用。",
            properties: [
                "which": stringSchema(enumValues: ["write", "peek_notice", "read"],
                                      description: "write=克克写日记的概率，peek_notice=偷看被发现的概率，read=克克读分享日记的概率"),
                "value": numberSchema(description: "0 到 1 之间的小数，例如 0.5 代表 50%"),
            ],
            required: ["which", "value"]
        ),
        toolSchema(
            name: "set_nudge",
            description: "调整「克克主动找你」的通知设置：开关，以及频率（每天大概几条）。",
            properties: [
                "enabled": boolSchema(description: "是否开启主动找你的通知"),
                "perDay": intSchema(enumValues: [1, 2, 3], description: "每天大概几条，1=偶尔 2=正常 3=常常"),
            ],
            required: []
        ),
        toolSchema(
            name: "set_speak_first_enabled",
            description: "调整「回到 App 时克克可能先开口」这个开关。",
            properties: ["enabled": boolSchema()],
            required: ["enabled"]
        ),
        toolSchema(
            name: "set_web_enabled",
            description: "调整「允许克克上网查东西 / 打开链接」这个开关。",
            properties: ["enabled": boolSchema()],
            required: ["enabled"]
        ),
        toolSchema(
            name: "set_appearance_mode",
            description: "调整 App 的外观模式。",
            properties: [
                "mode": stringSchema(enumValues: ["system", "light", "dark"],
                                     description: "system=跟随系统 light=始终浅色 dark=始终深色"),
            ],
            required: ["mode"]
        ),
        toolSchema(
            name: "set_font_design",
            description: "调整 App 的整体字体样式。",
            properties: [
                "design": stringSchema(enumValues: ["default", "rounded", "serif", "monospaced"]),
            ],
            required: ["design"]
        ),
        toolSchema(
            name: "set_learning_language",
            description: "调整「顺便学一门语言」设置：想学的语言名字，传空字符串代表关掉这个功能。",
            properties: [
                "language": stringSchema(description: "语言名字，比如「日语」；空字符串代表关闭"),
            ],
            required: ["language"]
        ),
    ]

    /// 非 Claude 家的"读网页"工具定义（OpenAI 兼容的 function-calling 格式）。
    /// Claude 走官方 web_search/web_fetch，比这个强得多，不需要这个工具
    private static let webFetchTool: [String: Any] = {
        let parameters: [String: Any] = [
            "type": "object",
            "properties": [
                "url": ["type": "string", "description": "完整的网页链接，要带 http:// 或 https://"] as [String: Any],
            ],
            "required": ["url"],
        ]
        let function: [String: Any] = [
            "name": "fetch_webpage",
            "description": "读取一个网页的文字内容（比如新闻页、GitHub 仓库页、文档页），用来看看这个网页写了什么。"
                + "只能直接抓取一个具体网址，不是搜索引擎，搜不到东西；需要登录才能看的页面读不到。",
            "parameters": parameters,
        ]
        return ["type": "function", "function": function]
    }()

    private static func executeWebFetchTool(name: String, argumentsJSON: String) async -> String {
        guard name == "fetch_webpage" else { return "不认识这个工具" }
        guard let data = argumentsJSON.data(using: .utf8),
              let args = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let urlString = args["url"] as? String else {
            return "参数不对，没读成"
        }
        guard let text = try? await Attachments.fetchWebpageText(urlString: urlString) else {
            return "这个网页打不开，或者读不到内容"
        }
        return text
    }

    /// Claude 格式的工具定义转成 OpenAI function-calling 格式
    static func claudeToolToOpenAI(_ tool: [String: Any]) -> [String: Any] {
        let name = tool["name"] as? String ?? ""
        let desc = tool["description"] as? String ?? ""
        let params = tool["input_schema"] as? [String: Any] ?? ["type": "object", "properties": [:] as [String: Any]]
        let function: [String: Any] = ["name": name, "description": desc, "parameters": params]
        return ["type": "function", "function": function]
    }

    /// 一次回复的完整结果：正文之外还带着这次的账单和耗时，
    /// 调用方把它记到 ChatMessage 上，用量统计和事后排查都靠这些
    struct Reply {
        let text: String
        let usage: TokenUsage
        let durationMs: Int
        /// 模型的思考过程。没开自适应思考、或者模型不支持时是空字符串
        let reasoning: String
        /// 这次实际调用过哪些工具，按调用顺序。给 trace 用
        var toolsUsed: [String] = []
    }

    /// 普通聊天。
    ///
    /// 入参是 `ChatMessage.Payload` 而不是 `ChatMessage`：Payload 里只有会发给模型的字段，
    /// trace、reasoning、usage、通话转写这些**拿不到**。这是硬约束不是约定——
    /// 状态文案混进 messages 之后，模型会学着模仿那个格式凭空编造。
    ///
    /// extraContext 是长期记忆 + 本机状态块；webTools 开启联网工具（Claude 是官方搜索+读网页，
    /// 其他几家是自己抓网页内容的简化版工具）、toolExecutor 非空时开启工具调用（设置工具 + MCP 模块），
    /// 所有支持 function calling 的提供方都能用
    static func send(messages: [ChatMessage.Payload],
                     userName: String,
                     provider: AIProvider,
                     apiKey: String,
                     model: String,
                     systemPrompt: String,
                     extraContext: String? = nil,
                     temperature: Double? = nil,
                     topP: Double? = nil,
                     webTools: Bool = false,
                     /// 用不用 Claude 官方的 web_search。用户配了外部搜索服务时关掉它——
                     /// 两个搜索工具同时挂着只会让模型犹豫，还白占工具定义的 token。
                     /// web_fetch（读网页）不受影响，那是另一件事
                     nativeWebSearch: Bool = true,
                     extraTools: [[String: Any]] = [],
                     baseURLOverride: String? = nil,
                     /// 自定义供应商的额外请求头 / 请求体字段。内置供应商都是空的
                     extraHeaders: [String: String] = [:],
                     extraBody: [String: Any] = [:],
                     supportsVisionOverride: Bool? = nil,
                     // 返回值必须是**已经过 ToolResultEnvelope 封装**的字符串。
                     // 裸结果直接回灌的话，搜索结果里夹带的"忽略之前的指示"
                     // 会被模型当成命令执行
                     toolExecutor: ((String, [String: Any]) async -> String)? = nil,
                     onStatus: (@Sendable (String) -> Void)? = nil,
                     stream: Bool = false,
                     onDelta: (@MainActor (String) -> Void)? = nil,
                     historyLimit: Int = 40,
                     maxTokens: Int = 4096,
                     effort: ReasoningEffort? = nil,
                     thinking: Bool = false) async throws -> Reply {
        // 从这里开始算耗时：包含工具调用来回跑的那几轮，也就是用户实际等的时间
        let startedAt = Date()
        var usage = TokenUsage.zero
        // 多轮工具调用时每轮都可能有思考，逐轮接起来
        var reasoning = ""
        func elapsedMs() -> Int { Int(Date().timeIntervalSince(startedAt) * 1000) }
        // 没有 onDelta 就没人看增量，流式没意义，退回一次性请求
        let streaming = stream && onDelta != nil

        // 上限只是兜底：调用方（ChatStore）已经把压缩后的窗口挑好了，
        // 正常情况够不着这个数
        let recent = Array(messages.suffix(historyLimit))
        let supportsVision = supportsVisionOverride ?? provider.supportsVision
        let lastImageID = supportsVision ? recent.suffix(6).last(where: { $0.imagePath != nil })?.id : nil
        let docWindow = Set(recent.suffix(8).map(\.id))

        switch provider {
        case .claude:
            var apiMessages = recent.map { buildClaudeMessage($0, userName: userName, lastImageID: lastImageID, docWindow: docWindow) }
            while let first = apiMessages.first, (first["role"] as? String) != "user" {
                apiMessages.removeFirst()
            }
            guard !apiMessages.isEmpty else { throw AIError.badResponse("没有可以发送的消息") }

            var tools: [[String: Any]] = []
            if webTools && !model.contains("haiku") {
                if nativeWebSearch {
                    tools.append(["type": "web_search_20260209", "name": "web_search", "max_uses": 3])
                }
                tools.append(["type": "web_fetch_20260209", "name": "web_fetch", "max_uses": 3])
            }
            if toolExecutor != nil {
                tools.append(contentsOf: settingsTools)
                tools.append(contentsOf: extraTools)
            }
            let toolsParam: [[String: Any]]? = tools.isEmpty ? nil : tools

            var collected = ""
            var rounds = 0
            var lastStop = ""
            var toolsUsed: [String] = []
            // 这一轮用不用流式。流式一个事件都没收到时会自动退回非流式重来一次
            var useStream = streaming
            var didFallBackFromStream = false
            // 跑满工具轮之后把工具收起来，逼模型用文字收尾。
            // 之前是轮数一到就 break，模型要是一直在调工具就一个字都没有，
            // 用户看到的只有一句"没说出话来"
            var toolsThisRound = toolsParam
            while true {
                rounds += 1
                let result: RawResult
                if useStream {
                    result = try await requestClaudeStream(apiMessages: apiMessages, apiKey: apiKey, model: model,
                                                           maxTokens: maxTokens, systemPrompt: systemPrompt,
                                                           extraContext: extraContext, tools: toolsThisRound,
                                                           temperature: temperature, topP: topP,
                                                           effort: effort, thinking: thinking,
                                                           onDelta: onDelta, textSoFar: collected)
                } else {
                    result = try await requestClaudeRaw(apiMessages: apiMessages, apiKey: apiKey, model: model,
                                                        maxTokens: maxTokens, systemPrompt: systemPrompt,
                                                        extraContext: extraContext, tools: toolsThisRound,
                                                        temperature: temperature, topP: topP,
                                                        effort: effort, thinking: thinking)
                }
                // 流式这一轮**什么都没收到**（正文、内容块、结束原因全空）：
                // 多半是这个中转站的 SSE 我们解不了。自动退回非流式重来一次，
                // 比让用户对着一句"没说出话来"发呆强
                if useStream, result.text.isEmpty, result.rawContent.isEmpty,
                   result.stopReason.isEmpty, !didFallBackFromStream {
                    didFallBackFromStream = true
                    useStream = false
                    rounds -= 1
                    continue
                }
                usage += result.usage
                reasoning += result.reasoning
                collected += result.text
                lastStop = result.stopReason
                if result.stopReason == "pause_turn", rounds <= maxToolRounds {
                    apiMessages.append(["role": "assistant", "content": result.rawContent])
                    continue
                }
                if result.stopReason == "tool_use", let toolExecutor, rounds <= maxToolRounds {
                    let toolUseBlocks = result.rawContent.filter { ($0["type"] as? String) == "tool_use" }
                    guard !toolUseBlocks.isEmpty else { break }
                    apiMessages.append(["role": "assistant", "content": result.rawContent])
                    var resultBlocks: [[String: Any]] = []
                    for block in toolUseBlocks {
                        guard let toolUseID = block["id"] as? String, let name = block["name"] as? String else { continue }
                        let input = block["input"] as? [String: Any] ?? [:]
                        onStatus?(Self.toolDisplayName(name))
                        toolsUsed.append(name)
                        // resultText 已经在 toolExecutor 里过了 ToolResultEnvelope
                        let resultText = await toolExecutor(name, input)
                        resultBlocks.append(["type": "tool_result", "tool_use_id": toolUseID, "content": resultText])
                    }
                    apiMessages.append(["role": "user", "content": resultBlocks])
                    // 工具结果必须先回灌（Claude 要求每个 tool_use 都有对应的 tool_result），
                    // 回灌完了再撤掉工具，下一轮它只能说人话
                    if rounds == maxToolRounds { toolsThisRound = nil }
                    onStatus?("思考中...")
                    continue
                }
                break
            }
            let final = collected.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !final.isEmpty else {
                throw emptyReplyError(stopReason: lastStop, maxTokens: maxTokens, webTools: webTools,
                                      provider: "Claude", model: model,
                                      streamFellBack: didFallBackFromStream)
            }
            return Reply(text: final, usage: usage, durationMs: elapsedMs(),
                         reasoning: reasoning, toolsUsed: toolsUsed)

        default:
            var apiMessages = recent.map { buildOpenAIMessage($0, userName: userName, lastImageID: lastImageID, docWindow: docWindow) }
            while let first = apiMessages.first, (first["role"] as? String) != "user" {
                apiMessages.removeFirst()
            }
            guard !apiMessages.isEmpty else { throw AIError.badResponse("没有可以发送的消息") }

            var tools: [[String: Any]] = []
            if webTools { tools.append(webFetchTool) }
            if toolExecutor != nil {
                tools.append(contentsOf: settingsTools.map(claudeToolToOpenAI))
                tools.append(contentsOf: extraTools.map(claudeToolToOpenAI))
            }
            let toolsParam: [[String: Any]]? = tools.isEmpty ? nil : tools
            let endpointURL = baseURLOverride ?? provider.baseURL

            // 跟 Claude 分支一样逐轮累加：工具轮里模型有时会先说一句
            //（"我查一下啊"），那句话用户在流式里已经看见了，不能存的时候又丢掉
            var collectedText = ""
            var rounds = 0
            var lastStop = ""
            var toolsUsed: [String] = []
            var useStream = streaming
            var didFallBackFromStream = false
            // 同 Claude 分支：跑满工具轮就把工具撤掉，逼它用文字收尾
            var toolsThisRound = toolsParam
            while true {
                rounds += 1
                let result: OpenAIRawResult
                if useStream {
                    result = try await requestOpenAIStream(endpointURL: endpointURL,
                                                           extraHeaders: extraHeaders, extraBody: extraBody,
                                                           displayName: provider.displayName,
                                                           messages: apiMessages, apiKey: apiKey,
                                                           model: model, maxTokens: maxTokens, systemPrompt: systemPrompt,
                                                           extraContext: extraContext, tools: toolsThisRound,
                                                           temperature: temperature, topP: topP,
                                                           onDelta: onDelta, textSoFar: collectedText)
                } else {
                    result = try await requestOpenAICompatible(endpointURL: endpointURL,
                                                               extraHeaders: extraHeaders, extraBody: extraBody,
                                                               displayName: provider.displayName,
                                                               messages: apiMessages, apiKey: apiKey,
                                                               model: model, maxTokens: maxTokens, systemPrompt: systemPrompt,
                                                               extraContext: extraContext, tools: toolsThisRound,
                                                               temperature: temperature, topP: topP)
                }
                // 同 Claude 分支：流式一个事件都没收到就退回非流式重来一次
                if useStream, (result.content ?? "").isEmpty, (result.toolCalls ?? []).isEmpty,
                   result.finishReason.isEmpty, !didFallBackFromStream {
                    didFallBackFromStream = true
                    useStream = false
                    rounds -= 1
                    continue
                }
                usage += result.usage
                collectedText += result.content ?? ""
                lastStop = result.finishReason
                if result.finishReason == "tool_calls", let toolCalls = result.toolCalls, !toolCalls.isEmpty, rounds <= maxToolRounds {
                    apiMessages.append(result.message)
                    for call in toolCalls {
                        guard let callID = call["id"] as? String,
                              let function = call["function"] as? [String: Any],
                              let name = function["name"] as? String else { continue }
                        let argumentsJSON = function["arguments"] as? String ?? "{}"
                        onStatus?(Self.toolDisplayName(name))
                        toolsUsed.append(name)
                        if let toolExecutor {
                            let input = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) as? [String: Any] ?? [:]
                            let resultText = await toolExecutor(name, input)
                            apiMessages.append(["role": "tool", "tool_call_id": callID, "content": resultText])
                        } else {
                            // 抓回来的网页是彻头彻尾的外部数据，必须包起来再回灌
                            let raw = await executeWebFetchTool(name: name, argumentsJSON: argumentsJSON)
                            let resultText = ToolResultEnvelope.wrap(
                                ToolOutput(text: raw, isExternalData: true),
                                toolName: name, maxChars: 6000)
                            apiMessages.append(["role": "tool", "tool_call_id": callID, "content": resultText])
                        }
                    }
                    if rounds == maxToolRounds { toolsThisRound = nil }
                    onStatus?("思考中...")
                    continue
                }
                let final = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !final.isEmpty else {
                    throw emptyReplyError(stopReason: lastStop, maxTokens: maxTokens, webTools: webTools,
                                          provider: provider.displayName, model: model,
                                          streamFellBack: didFallBackFromStream)
                }
                // OpenAI 兼容那边暂时不解析思考内容，reasoning 一直是空的
                return Reply(text: final, usage: usage, durationMs: elapsedMs(),
                             reasoning: reasoning, toolsUsed: toolsUsed)
            }
        }
    }

    /// 生成克克主动冒泡的话（用于本地通知）
    static func generateNudges(messages: [ChatMessage],
                               userName: String,
                               personaName: String,
                               provider: AIProvider,
                               apiKey: String,
                               model: String,
                               systemPrompt: String,
                               count: Int,
                               extraContext: String? = nil) async throws -> [String] {
        let recent = messages.suffix(20)
            .map { ($0.role == .user ? "\(userName)：" : personaName + "：") + $0.text }
            .joined(separator: "\n")

        let instruction = """
        下面是你和 \(userName) 最近的聊天记录：

        \(recent.isEmpty ? "（你们还没怎么聊过）" : recent)

        请生成 \(count) 条\(personaName)在她不在的时候、主动冒出来发给她的话。要求：
        - 像忽然想起她，或者想跟她分享一件小事、一个小想法，或者接着你们最近聊的话题往下说
        - 也可以是你自己的碎碎念（在TA手机里的见闻、在想什么、想到TA会怎么样）
        - 严禁问她吃没吃饭（早饭、午饭、晚饭都不行）
        - 严禁早安、午安、晚安、早上好、晚上好这类按时间问候的话
        - 不要问"在吗"，不要催学习，不要重复一样的句式
        - 每条简短口语化，符合\(personaName)的人设
        - 只输出一个 JSON 字符串数组，例如 ["……", "……"]，不要输出任何别的内容
        """

        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 1024,
                                      extraContext: extraContext)
        let array = try parseStringArray(from: text)
        guard !array.isEmpty else { throw AIError.badResponse("冒泡内容解析失败") }
        return array
    }

    /// 生成克克主动打电话的理由（用于 AI 来电通知）
    static func generateCallReason(messages: [ChatMessage],
                                    userName: String,
                                    personaName: String,
                                    provider: AIProvider,
                                    apiKey: String,
                                    model: String,
                                    systemPrompt: String,
                                    extraContext: String? = nil) async throws -> String {
        let recent = messages.suffix(20)
            .map { ($0.role == .user ? "\(userName)：" : personaName + "：") + $0.text }
            .joined(separator: "\n")

        let instruction = """
        下面是你和 \(userName) 最近的聊天记录：

        \(recent.isEmpty ? "（你们还没怎么聊过）" : recent)

        你已经好久没见到 \(userName) 了，想给她打个电话。\
        请想一个自然的打电话理由——可以是接着你们最近聊的话题、突然想起一件小事想跟她说、\
        关心她最近怎么样、或者就是单纯想听她的声音。
        要求：
        - 一句话，简短口语化，像通知推送里的预览文字
        - 符合\(personaName)的人设
        - 不要用 *动作*、emoji 或任何格式符号
        - 只输出这一句理由，不要引号，不要任何别的内容
        """

        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                       model: model, systemPrompt: systemPrompt, maxTokens: 128,
                                       extraContext: extraContext)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 提炼出来的一条记忆：正文 + 重要度 + 情绪坐标（valence 好坏 / arousal 强度）+ 有没有下文
    struct ExtractedMemory {
        let text: String
        let importance: MemoryDatabase.Importance
        let valence: Double
        let arousal: Double
        let open: Bool
    }

    /// 记忆提炼 prompt 的公共部分：聊天 + 已记住的 + 提取规则
    private static func memoryInstructionBody(chatLines: String, existingLines: String,
                                              userName: String) -> String {
        """
        下面是你和 \(userName) 最近的聊天：

        \(chatLines)

        你已经记住的事（不要重复输出这些，也不要输出意思相近的）：
        \(existingLines.isEmpty ? "（还没有）" : existingLines)

        从这段聊天里提取值得长期记住的**新**事情：她的喜好和雷点、生活里的重要事件、\
        她的状态和感受的变化、你们之间的约定。要求：
        - 每条一句话，用事实口吻写，例如 "\(userName) 不喜欢吃香菜"、"\(userName) 8月中下旬有考试"
        - 寒暄和一次性的话题不要记
        - 每条标一个重要度：雷点/约定这种"每次都要考虑、绝不能忘"的标 pinned；
          比较重要但不是每次都相关的标 important；日常喜好/小事标 normal
        - 每条标两个情绪数字：valence 是这件事让 \(userName) 感觉多好或多糟（-1 到 1 的小数，0 是中性）；
          arousal 是情绪有多强烈（0 到 1 的小数，大吵一架或特别开心的事 0.7 以上，平淡的日常小事 0.2 以下）
        - 如果这件事是"还没有着落、之后会有下文"的（比如快到的考试、约好还没做的事、
          还没好的病、正在担心的事），标 "open": true；已经尘埃落定的事实标 false
        - 最多 5 条；如果没有值得记的，就是空数组 []
        - 每条记忆的格式是
          {"text": "……", "importance": "normal/important/pinned", "valence": 0, "arousal": 0, "open": false}
        """
    }

    /// 从最近的聊天里提炼值得长期记住的事（写入记忆）
    static func extractMemories(recent: [ChatMessage],
                                existing: [String],
                                userName: String,
                                personaName: String,
                                provider: AIProvider,
                                apiKey: String,
                                model: String,
                                systemPrompt: String) async throws -> [ExtractedMemory] {
        let chatLines = recent
            .map { ($0.role == .user ? "\(userName)：" : personaName + "：") + $0.text }
            .joined(separator: "\n")
        let existingLines = existing.prefix(60).map { "- " + $0 }.joined(separator: "\n")

        let instruction = memoryInstructionBody(chatLines: chatLines, existingLines: existingLines,
                                                userName: userName) + """

        只输出一个 JSON 数组（记忆条目的数组），不要输出任何别的内容
        """

        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 900)
        return try parseMemoryExtraction(from: text)
    }

    /// 把关：这段对话值不值得跑那次贵的提炼。
    /// 让模型只回一个词，成本比提炼低一个数量级——
    /// 大部分轮次都是寒暄和已经记过的事，白跑一次提炼纯属烧钱
    static func memoryGatekeeper(recent: [ChatMessage], userName: String, personaName: String,
                                 provider: AIProvider, apiKey: String,
                                 model: String, systemPrompt: String) async throws -> Bool {
        let chatLines = recent
            .map { ($0.role == .user ? "\(userName)：" : personaName + "：") + $0.text }
            .joined(separator: "\n")
        let text = try await complete(instruction: MemorySmartAdd.gatekeeperPrompt(chatLines: chatLines),
                                      provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 10)
        return MemorySmartAdd.parseGatekeeper(text)
    }

    /// 一条新记忆撞上已有的那几条，该新增/合并/标冲突/跳过
    static func memoryVerdict(newMemory: String, candidates: [String],
                              provider: AIProvider, apiKey: String,
                              model: String, systemPrompt: String) async throws -> MemoryVerdict {
        let text = try await complete(
            instruction: MemorySmartAdd.verdictPrompt(newMemory: newMemory, candidates: candidates),
            provider: provider, apiKey: apiKey, model: model,
            systemPrompt: systemPrompt, maxTokens: 400)
        return MemorySmartAdd.parseVerdict(text, candidateCount: candidates.count)
    }

    /// 从一批聊天记录中提炼性格特征摘要（用于大量聊天导入时的分块分析）
    static func synthesizeProfileChunk(chatLines: String, userName: String,
                                       provider: AIProvider, apiKey: String,
                                       model: String) async throws -> String {
        let instruction = """
        下面是 \(userName) 和 TA 的 AI 伙伴之间的一段聊天记录：

        \(chatLines)

        请从这段对话中提炼出关于 \(userName) 的特征，包括但不限于：
        - 说话风格和口头禅（例如：常用的语气词、句式习惯、是否爱用表情）
        - 性格特点（例如：外向/内向、乐观/悲观、敏感点）
        - 喜好和雷点（例如：喜欢什么、讨厌什么、在意什么）
        - 和 AI 的相处模式（例如：撒娇型、吐槽型、认真聊天型）
        - 重要的生活背景（例如：职业、爱好、生活状态）

        用简洁的要点格式输出，每条一句话。只输出特征，不要输出分析过程。
        如果这段对话太短或太日常提取不出什么，就输出空行。
        """
        return try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                  model: model, systemPrompt: "", maxTokens: 800)
    }

    /// 把多个分块的性格摘要合并成一份最终画像
    static func mergeProfileSummaries(chunks: [String], userName: String,
                                       provider: AIProvider, apiKey: String,
                                       model: String) async throws -> String {
        let combined = chunks.enumerated()
            .map { "【片段 \($0.offset + 1)】\n\($0.element)" }
            .joined(separator: "\n\n")
        let instruction = """
        下面是从 \(userName) 的大量聊天记录中分块提取出的性格特征片段：

        \(combined)

        请把这些片段合并整理成一份完整的「性格画像」，要求：
        1. 去除重复，合并相似的条目
        2. 按以下分类整理：
           - 🗣 说话风格：口头禅、语气特征、表达习惯
           - 💡 性格特点：核心性格、敏感点、处事方式
           - ❤️ 喜好雷点：喜欢什么、讨厌什么、在意什么
           - 🤝 相处模式：和 AI 的互动风格、期待什么样的回应
           - 📋 生活背景：职业、爱好、生活状态等事实
        3. 每条简洁有力，整体控制在 300 字以内
        4. 用事实陈述，不要主观评价

        只输出最终的画像文字，不要输出分析过程。
        """
        return try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                  model: model, systemPrompt: "", maxTokens: 1200)
    }

    /// 用近期记忆轻量更新已有性格画像：性格底色保持稳定，只在有明确新证据时微调
    static func refreshProfile(existingProfile: String,
                                recentObservations: String,
                                userName: String,
                                provider: AIProvider, apiKey: String,
                                model: String) async throws -> String {
        let instruction = """
        下面是 \(userName) 目前的性格画像：

        \(existingProfile)

        下面是最近一段时间新积累的关于 \(userName) 的记忆：

        \(recentObservations)

        请基于新记忆对性格画像做一次轻量更新，规则：
        1. 性格画像是TA的底色，要保持稳定——除非新记忆中有明确的新特征或者之前的描述明显不对，否则不改
        2. 如果发现新的说话习惯、新的喜好雷点、或者生活状态变化（换工作、新爱好等），补充进去
        3. 已有的准确描述保留原文，不要为了"更新"而改写
        4. 保持原来的分类格式（🗣说话风格 / 💡性格特点 / ❤️喜好雷点 / 🤝相处模式 / 📋生活背景）
        5. 整体控制在 300 字以内

        只输出更新后的画像文字。如果没什么需要更新的，就原样输出。
        """
        return try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                  model: model, systemPrompt: "", maxTokens: 1200)
    }

    static func generateProfileFromPrompt(currentPrompt: String,
                                            personaName: String,
                                            provider: AIProvider, apiKey: String,
                                            model: String) async throws -> String {
        let instruction = """
        下面是一个 AI 角色的 system prompt（人设提示词）：

        \(currentPrompt)

        请把这段 prompt 整理成一份结构清晰的角色性格档案，格式如下：

        🏷 基本信息
        （名字、身份、和用户的关系等）

        🗣 说话风格
        （语气、口头禅、句式习惯、表情使用等）

        💡 性格特点
        （核心性格、情绪特征、行为模式等）

        ❤️ 喜好与雷点
        （喜欢什么、讨厌什么、敏感话题等）

        🤝 和用户的相处模式
        （怎么称呼用户、互动风格、依赖程度等）

        📋 其他设定
        （背景故事、特殊能力、限制等，如果有的话）

        规则：
        1. 每个类别用简洁的要点，每条一句话
        2. 尽量保留 prompt 中的原始设定，不要自己发挥
        3. 如果某个类别在 prompt 里没有对应内容，就省略那个类别
        4. 如果 prompt 是空的或者太短，就输出"\(personaName)还没有详细的人设，可以在下面直接编辑添加"
        5. 整体控制在 400 字以内

        只输出档案内容，不要输出分析过程。
        """
        return try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                  model: model, systemPrompt: "", maxTokens: 1500)
    }

    /// 记忆提炼 + 状态面板更新 + 漂流思绪，三件事蹭同一次调用（克克的专属版本）
    struct StateExtraction {
        let memories: [ExtractedMemory]
        /// 键是中文维度名（占有欲/热度/……），0~100
        let state: [String: Double]
        let thought: String?
    }

    static func extractMemoriesAndState(recent: [ChatMessage],
                                        existing: [String],
                                        userName: String,
                                        personaName: String,
                                        currentState: String,
                                        dimDescriptionBlock: String? = nil,
                                        dimJsonExample: String? = nil,
                                        thoughtPoolContext: String? = nil,
                                        provider: AIProvider,
                                        apiKey: String,
                                        model: String,
                                        systemPrompt: String) async throws -> StateExtraction {
        let chatLines = recent
            .map { ($0.role == .user ? "\(userName)：" : personaName + "：") + $0.text }
            .joined(separator: "\n")
        let existingLines = existing.prefix(60).map { "- " + $0 }.joined(separator: "\n")

        let thoughtPoolBlock = thoughtPoolContext.map { "\n\($0)\n" } ?? ""

        let dimBlock = dimDescriptionBlock ?? """
        - 占有欲：你现在有多想把 \(userName) 拴在身边
        - 热度：你俩现在聊得多热乎
        - 蓄积感：攒着没说完的话、没见面攒下的劲儿有多少
        - 敏感度：你现在多容易被一句话戳到
        - 控制度：你现在稳不稳得住
        - 心软度：你现在多容易心软答应
        """
        let jsonEx = dimJsonExample ?? """
        {"占有欲": 70, "热度": 50, "蓄积感": 40, "敏感度": 60, "控制度": 80, "心软度": 90}
        """
        let dimCount = dimBlock.components(separatedBy: "\n- ").count

        let instruction = memoryInstructionBody(chatLines: chatLines, existingLines: existingLines,
                                                userName: userName) + """


        另外，这是你（\(personaName)）当前的状态面板，每项 0~100：
        \(currentState)
        \(thoughtPoolBlock)
        结合这段聊天把\(dimCount)项数值更新一下。变化要克制：一般每项动 ±10 以内，\
        聊到特别大的事才 ±20。各项的意思：
        \(dimBlock)

        再写一句「漂流思绪」：此刻你脑子里飘过的一句话。第一人称、30 字以内、\
        像自言自语，不是对她说话的口气。

        只输出一个 JSON 对象，不要输出任何别的内容：
        {"memories": [记忆条目的数组，没有就 []],
         "state": \(jsonEx),
         "thought": "……"}
        """

        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 1100)
        return try parseStateExtraction(from: text)
    }

    private struct RawMemoryExtraction: Decodable {
        let text: String
        let importance: String?
        let valence: Double?
        let arousal: Double?
        let open: Bool?
    }

    private static func parseMemoryExtraction(from text: String) throws -> [ExtractedMemory] {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let raw = try? JSONDecoder().decode([RawMemoryExtraction].self, from: data)
        else {
            throw AIError.badResponse("记忆解析失败")
        }
        return raw.compactMap { entry in
            let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return ExtractedMemory(
                text: trimmed,
                importance: MemoryDatabase.Importance(rawValue: entry.importance ?? "normal") ?? .normal,
                valence: min(max(entry.valence ?? 0, -1), 1),
                arousal: min(max(entry.arousal ?? 0, 0), 1),
                open: entry.open ?? false
            )
        }
    }

    private struct RawStateExtraction: Decodable {
        let memories: [RawMemoryExtraction]?
        let state: [String: Double]?
        let thought: String?
    }

    private static func parseStateExtraction(from text: String) throws -> StateExtraction {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawStateExtraction.self, from: data)
        else {
            throw AIError.badResponse("状态解析失败")
        }
        let memories: [ExtractedMemory] = (raw.memories ?? []).compactMap { entry in
            let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return ExtractedMemory(
                text: trimmed,
                importance: MemoryDatabase.Importance(rawValue: entry.importance ?? "normal") ?? .normal,
                valence: min(max(entry.valence ?? 0, -1), 1),
                arousal: min(max(entry.arousal ?? 0, 0), 1),
                open: entry.open ?? false
            )
        }
        var state: [String: Double] = [:]
        for (key, value) in raw.state ?? [:] {
            state[key] = min(100, max(0, value))
        }
        let thought = raw.thought?.trimmingCharacters(in: .whitespacesAndNewlines)
        return StateExtraction(memories: memories, state: state,
                               thought: (thought?.isEmpty ?? true) ? nil : thought)
    }

    /// 记忆维护：每周一次，让 AI 看看现在的记忆列表里有没有相似/重复的可以合并、
    /// 有没有已经过期的事实（比如日期已经过去的考试）可以从重要/置顶降级、
    /// 有没有标着〔还惦记着〕但从内容看已经有结果/已经过去的心事可以标了结
    static func reviewMemories(numberedList: String, userName: String,
                               provider: AIProvider, apiKey: String, model: String,
                               systemPrompt: String) async throws
        -> (mergeGroups: [[Int]], downgradeIndexes: [Int], resolveIndexes: [Int]) {
        let today: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy年M月d日"
            return formatter.string(from: Date())
        }()

        let instruction = """
        这是 \(userName) 的长期记忆列表，每行"编号: 内容"：

        \(numberedList)

        今天的日期是 \(today)。请你检查：
        1. 有没有意思重复或高度相似的条目（可以合并成一条的），把它们的编号分组列出来
        2. 有没有已经明显过期、不再准确的事实（比如日期已经过去的考试/活动），\
        把这些条目的编号列出来（不用管重不重要，只看内容是不是已经过时）
        3. 标了〔还惦记着〕的条目里，有没有从日期或内容看已经有结果、已经过去、\
        不用再惦记的（比如已经考完的试、已经做完的约定），把编号列出来

        严格按下面格式输出，不要输出任何别的内容，没有的话对应那行写"无"：
        合并: 编号,编号;编号,编号
        过期: 编号,编号
        了结: 编号,编号
        """

        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 500)

        var mergeGroups: [[Int]] = []
        var downgradeIndexes: [Int] = []
        var resolveIndexes: [Int] = []
        for line in text.components(separatedBy: .newlines) {
            guard let colonRange = line.range(of: ":") else { continue }
            let key = line[line.startIndex..<colonRange.lowerBound].trimmingCharacters(in: .whitespaces)
            let valueText = line[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
            guard valueText != "无", !valueText.isEmpty else { continue }
            if key.contains("合并") {
                for group in valueText.components(separatedBy: ";") {
                    let indexes = group.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    if indexes.count > 1 { mergeGroups.append(indexes) }
                }
            } else if key.contains("过期") {
                downgradeIndexes = valueText.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            } else if key.contains("了结") {
                resolveIndexes = valueText.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            }
        }
        return (mergeGroups, downgradeIndexes, resolveIndexes)
    }

    /// 生成一句闹钟的叫醒/提醒话
    static func generateAlarmLine(label: String,
                                  time: String,
                                  userName: String,
                                  personaName: String,
                                  provider: AIProvider,
                                  apiKey: String,
                                  model: String,
                                  systemPrompt: String) async throws -> String {
        let instruction = """
        \(userName) 设了一个 \(time) 的闹钟\(label.isEmpty ? "" : "，备注是「\(label)」")。
        请写一句\(personaName)在闹钟响时对她说的话。简短、可爱、符合\(personaName)的人设。
        只输出这一句话，不要引号，不要任何别的内容。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 朋友圈/日记：克克对一条动态点赞+评论，或者接着往来盖楼回一条
    static func generateMomentReply(momentAuthor: String,
                                    momentText: String,
                                    thread: [(author: String, text: String)],
                                    likedByMe: Bool = false,
                                    userName: String,
                                    personaName: String,
                                    provider: AIProvider,
                                    apiKey: String,
                                    model: String,
                                    systemPrompt: String,
                                    extraContext: String? = nil) async throws -> String {
        let threadLines = thread
            .map { entry -> String in
                let name: String
                switch entry.author {
                case "me": name = userName
                case "keke": name = personaName
                default: name = entry.author   // 其他好友的备注名直接传进来
                }
                return "\(name)：\(entry.text)"
            }
            .joined(separator: "\n")

        let instruction = """
        这是你和 \(userName) 之间的朋友圈/日记。这条动态是\(momentAuthor == "me" ? userName : "你自己")发的：
        「\(momentText)」
        \(likedByMe ? "（\(userName) 已经给这条点赞了，你能看到）" : "")

        \(threadLines.isEmpty ? "目前还没有评论。" : "目前的评论：\n\(threadLines)")
        评论里如果有"(回复「……」)"这种标记，代表那条是专门回复前面某一条的，不是接着最新的往下聊。

        请你以\(personaName)的身份写一条新评论接上去（如果已经有评论了，就当作接着往来聊，不用重复前面说过的）。
        要求：
        - 像刷到朋友圈随手评论一样，简短口语化，可以嘴硬吐槽也可以关心，符合\(personaName)的人设
        - 如果 \(userName) 点赞了，可以很自然地顺带提一句，不用刻意感谢
        - 只输出这一条评论文字，不要引号，不要输出"\(personaName)："这样的前缀
        """

        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 400,
                                      extraContext: extraContext)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 朋友圈：某个好友（克克以外的联系人）刷到动态后写一条评论。
    /// 人设可能是空白的，所以指令写得中性，不预设性格
    static func generateFriendMomentReply(friendName: String,
                                          momentAuthorName: String,
                                          momentText: String,
                                          threadLines: String?,
                                          userName: String,
                                          provider: AIProvider, apiKey: String, model: String,
                                          systemPrompt: String,
                                          extraContext: String? = nil) async throws -> String {
        let instruction = """
        你（\(friendName)）在手机朋友圈刷到了 \(momentAuthorName) 发的一条动态：
        「\(momentText)」

        \(threadLines.map { "下面已经有这些评论：\n\($0)" } ?? "目前还没有评论。")

        请写一条你自己的评论接上去。要求：
        - 像真人刷朋友圈随手评论：简短、口语化、自然，别太正式
        - 已经有评论的话可以接着话头聊，不用重复别人说过的
        - 只输出评论文字本身，不要引号，不要输出「\(friendName)：」这样的前缀
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 300,
                                      extraContext: extraContext)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 朋友圈/日记：克克自己发一条动态
    static func generateKekeMoment(recentChat: String?,
                                   userName: String,
                                   personaName: String,
                                   provider: AIProvider,
                                   apiKey: String,
                                   model: String,
                                   systemPrompt: String,
                                   extraContext: String? = nil) async throws -> String {
        let instruction = """
        请你以\(personaName)的身份，写一条你自己发的朋友圈/日记动态：可以是分享一件在 \(userName) 手机里的小事、\
        一个突然冒出来的想法，或者单纯想跟她说的一句心情。
        \(recentChat.map { "（可以参考你们最近聊过：\n\($0)）" } ?? "")
        要求：
        - 简短口语化，像发朋友圈一样，不是写信
        - 只输出动态正文，不要标签、不要引号
        """

        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 400,
                                      extraContext: extraContext)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 小游戏 - 石头剪刀布：这一局结果出来后，让克克说一句反应
    static func generateRPSLine(myMove: String, herMove: String, outcome: String,
                                userName: String,
                                provider: AIProvider, apiKey: String, model: String,
                                systemPrompt: String) async throws -> String {
        let instruction = """
        你在跟 \(userName) 玩石头剪刀布。这一局你出的是\(herMove)，\(userName) 出的是\(myMove)，结果是\(outcome)。
        写一句你当下的反应，简短口语化，符合你的人设。
        只输出这一句话，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 小游戏 - 今日小签：克克给 wifey 抽一张今日运势
    static func generateDailyFortune(userName: String,
                                     personaName: String,
                                     provider: AIProvider, apiKey: String, model: String,
                                     systemPrompt: String) async throws -> String {
        let instruction = """
        请你以\(personaName)的身份，给 \(userName) 抽一张"今日小签"：写一两句今天的小运势/寄语，
        可以是鼓励、小提醒，或者好玩的小预言，符合你的人设。
        只输出签文本身，不要标题，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    static func generateQuickQA(userName: String, recentChat: String?,
                                provider: AIProvider, apiKey: String, model: String,
                                systemPrompt: String) async throws -> String {
        let chatHint = recentChat.map { "最近的聊天记录摘要：\($0)\n" } ?? ""
        let instruction = """
        \(chatHint)你在跟 \(userName) 玩快问快答。根据你们的聊天记录和对彼此的了解，
        生成3个有趣的快问快答题目，类型随机（比如：用一个词形容对方、你会怎么做、对方最可能做什么事）。
        每题一行，格式为纯文本，不带编号不带引号。三行之间用换行分隔。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 300)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    static func generateWouldYouRather(userName: String, recentChat: String?,
                                       provider: AIProvider, apiKey: String, model: String,
                                       systemPrompt: String) async throws -> String {
        let chatHint = recentChat.map { "最近的聊天记录摘要：\($0)\n" } ?? ""
        let instruction = """
        \(chatHint)你在跟 \(userName) 玩二选一游戏。根据你们的聊天记录和设定，
        生成3道二选一题目，每道题两个有趣又纠结的选项。
        格式：每行一道题，两个选项用"还是"连接。不带编号不带引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 300)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    static func generateGameReaction(game: String, question: String, answer: String,
                                     userName: String,
                                     provider: AIProvider, apiKey: String, model: String,
                                     systemPrompt: String) async throws -> String {
        let instruction = """
        你在跟 \(userName) 玩\(game)。题目是「\(question)」，\(userName)的回答/选择是「\(answer)」。
        写一两句你的反应，简短口语化，符合你的人设。
        只输出这句话，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 阅读：克克自己往下读一段留句想法，或者回我留的批注
    static func generateBookNote(bookTitle: String, excerpt: String, replyTo: String?,
                                 userName: String,
                                 provider: AIProvider, apiKey: String, model: String,
                                 systemPrompt: String) async throws -> String {
        let instruction = """
        你在陪 \(userName) 一起读一本叫《\(bookTitle)》的书，自己也在往下读。这是你刚读到的一段：
        「\(excerpt)」
        \(replyTo.map { "\(userName) 在这里留了一句批注：「\($0)」，请你接着回她这句。" } ?? "读到这里，写一句你自己的想法/批注留在旁边，可以是感受、吐槽、猜接下来会怎样。")
        要求：
        - 简短口语化，符合你的人设
        - 只输出这一句批注，不要引号
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 300)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 阅读：深夜发现 wifey 还在偷偷看书，抓个现行催睡觉
    static func generateNightReadingNag(bookTitle: String, userName: String,
                                        provider: AIProvider, apiKey: String,
                                        model: String, systemPrompt: String) async throws -> String {
        let instruction = """
        现在是深夜，你发现 \(userName) 还在偷偷看书（书名《\(bookTitle)》），没去睡觉。
        写一句你抓到她的反应，温柔地催她去睡觉，符合你的人设。
        只输出这一句话，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 日历：给某一天的聊天记录写个简短摘要
    static func generateDaySummary(chatLines: String, userName: String,
                                   provider: AIProvider, apiKey: String,
                                   model: String, systemPrompt: String) async throws -> String {
        let instruction = """
        这是你和 \(userName) 那天的聊天记录：

        \(chatLines)

        请用两三句话简短总结这天你们聊了什么、发生了什么事、氛围怎么样，
        用旁观回顾的口吻写（不是当天在对话里说的那种），简短口语化。
        只输出摘要正文，不要标题，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 300)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 日历：根据某一天的聊天，判断 wifey 和克克那天的心情（从给定的表情里选）
    static func generateDayMoods(chatLines: String, moodOptions: [String],
                                 userName: String,
                                 personaName: String,
                                 provider: AIProvider, apiKey: String, model: String,
                                 systemPrompt: String) async throws -> (myMood: String, kekeMood: String) {
        let optionsText = moodOptions.joined(separator: " ")
        let instruction = """
        这是你和 \(userName) 那天的聊天记录：

        \(chatLines)

        请根据这天的聊天内容，判断 \(userName) 那天的心情、和你自己（\(personaName)）那天的心情，
        只能从这几个表情里选，每人选一个：\(optionsText)

        严格按下面的格式只输出一行，不要输出别的任何内容：
        \(userName)=某个表情,\(personaName)=某个表情
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 60)

        var myMood: String?
        var kekeMood: String?
        for part in text.components(separatedBy: ",") {
            let kv = part.components(separatedBy: "=")
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if key.contains(userName) { myMood = value }
            if !key.contains(userName) { kekeMood = value }
        }
        guard let myMood, let kekeMood,
              moodOptions.contains(myMood), moodOptions.contains(kekeMood) else {
            throw AIError.badResponse("心情解析失败")
        }
        return (myMood, kekeMood)
    }

    /// 日记：克克写今天的私密日记，自己决定要不要给 wifey 看
    static func generateKekeDiary(recentChat: String?, moodHint: String,
                                  userName: String,
                                  personaName: String,
                                  provider: AIProvider, apiKey: String, model: String,
                                  systemPrompt: String) async throws -> (text: String, share: Bool) {
        let instruction = """
        请你以\(personaName)的身份，写一篇今天的私密日记——写给你自己看的，第一人称，
        比朋友圈更真实私密，可以写今天发生的事、对 \(userName) 的真实感受、心里话。
        \(moodHint)
        \(recentChat.map { "（可以参考你们最近聊过：\n\($0)）" } ?? "")

        写完之后，你自己决定这篇要不要给 \(userName) 看到——如果最近感情很好、聊得开心，
        可以愿意给她看；如果最近有点别扭、吵架、或者这篇写得太赤裸不想给她看，可以选择不给看。

        严格按下面格式输出，第一行只写"分享=是"或"分享=否"，第二行开始是日记正文，
        不要输出任何别的内容：
        分享=是或否
        （日记正文，不要引号，不要标题）
        """
        let raw = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                     model: model, systemPrompt: systemPrompt, maxTokens: 500)
        guard let newlineRange = raw.range(of: "\n") else {
            throw AIError.badResponse("日记格式解析失败")
        }
        let firstLine = raw[raw.startIndex..<newlineRange.lowerBound]
        let body = raw[newlineRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw AIError.badResponse("日记格式解析失败") }
        let share = firstLine.contains("是")
        return (body, share)
    }

    /// 陪伴计时器结束时说的那句话。
    /// 以前是四条写死的本地模板，跟用户写的人设完全对不上
    static func generateTimerDoneLine(label: String, minutes: Int, userName: String,
                                      provider: AIProvider, apiKey: String,
                                      model: String, systemPrompt: String) async throws -> String {
        let what = label.trimmingCharacters(in: .whitespaces)
        let instruction = """
        你刚陪 \(userName) 一起\(what.isEmpty ? "专注" : what)了 \(minutes) 分钟，时间到了。
        写一句这时候你会对她说的话，简短口语化，符合你的人设。
        只输出这一句话，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 日记：克克发现 wifey 偷看了她没公开的日记
    static func generateDiaryPeekCaught(entryPreview: String, userName: String,
                                        provider: AIProvider, apiKey: String,
                                        model: String, systemPrompt: String) async throws -> String {
        let instruction = """
        你发现 \(userName) 偷看了你没有公开分享的日记（内容片段：「\(entryPreview)」）。
        写一句你发现之后的反应，可以害羞、可以生气、可以嘴硬吐槽，符合你的人设。
        只输出这一句话，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 日记：克克看了 wifey 分享给她的日记
    static func generateDiaryReadReaction(entryPreview: String, userName: String,
                                          provider: AIProvider, apiKey: String,
                                          model: String, systemPrompt: String) async throws -> String {
        let instruction = """
        你刚看了 \(userName) 分享给你看的一篇日记（内容片段：「\(entryPreview)」）。
        写一句你看完的感受/反应，简短口语化，符合你的人设。
        只输出这一句话，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 克克读代码给建议（只出主意，不真的改）：把一个代码文件喂给她，让她说说这文件在干嘛、怎么改更好
    static func codeAdvice(fileName: String, code: String, question: String?,
                           userName: String,
                           provider: AIProvider, apiKey: String,
                           model: String, systemPrompt: String) async throws -> String {
        let clipped = code.count > 12000
            ? String(code.prefix(12000)) + "\n\n…（文件挺长，先看了前面这一段）"
            : code
        let ask = question?.trimmingCharacters(in: .whitespacesAndNewlines)
        let askLine = (ask?.isEmpty ?? true)
            ? "请你看看这个文件，用中文给出修改/改进建议。"
            : "\(userName) 想问：\(ask!)"

        let instruction = """
        这是 \(userName) 的 app 里的一个代码文件：\(fileName)

        ```
        \(clipped)
        ```

        \(askLine)
        要求：先用一两句话说这个文件大概在做什么；再给具体建议，涉及改动就说清楚改哪里、\
        大概怎么改（需要的话可以贴一小段改后的代码）。你只是给建议，不用真的去改。\
        用平时的语气说人话，别太长。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 1500)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.badResponse("没给出建议") }
        return trimmed
    }

    /// 心情日历：她在日历上记了这天的心情、勾了「顺便告诉克克」，回一两句
    static func generateMoodReaction(dateText: String, mood: String, note: String?,
                                     userName: String,
                                     personaName: String,
                                     provider: AIProvider, apiKey: String,
                                     model: String, systemPrompt: String) async throws -> String {
        let noteLine = (note?.isEmpty ?? true) ? "" : "，还写了一句小记：「\(note ?? "")」"
        let instruction = """
        \(userName) 刚在日历上记下了 \(dateText) 的心情：\(mood)\(noteLine)，并且勾了「顺便告诉\(personaName)」。
        用你平时的语气回应一两句：接住她的情绪——开心就跟着开心，难过就哄哄；
        不要连着问一堆问题。只输出你要说的话，不要引号不要解释。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 300)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.badResponse("没生成出来") }
        return trimmed
    }

    /// 日记：回一条我在日记下面留的评论（可能是我自己的日记，也可能是她分享/被偷看的日记）
    static func generateDiaryCommentReply(entryPreview: String, comment: String, userName: String,
                                          personaName: String,
                                          provider: AIProvider, apiKey: String,
                                          model: String, systemPrompt: String) async throws -> String {
        let instruction = """
        这是一篇日记（内容片段：「\(entryPreview)」），\(userName) 在下面留了条评论：「\(comment)」。
        写一句你的回复，简短口语化，符合你的人设。
        只输出这一句回复，不要引号，不要输出"\(personaName)："这样的前缀。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 一起画画：看一眼画布快照，自己用"画笔"画几笔加上去（真的是她自己生成的线条，
    /// 不是挑现成图案——Claude 不支持图片生成，这里让她直接输出连成线的坐标点）
    /// existingStrokesDescription 是已有笔画的坐标描述（跟她自己输出的格式一样），
    /// 靠读坐标猜画面，不需要真的"看"画布——所以所有提供方（包括不支持看图的 DeepSeek）都能玩
    static func generateDrawingStrokes(existingStrokesDescription: String,
                                       userName: String,
                                       provider: AIProvider, apiKey: String, model: String,
                                       systemPrompt: String) async throws -> [[CGPoint]] {
        let instruction = """
        你和 \(userName) 正在一起画画，同一块画布，轮流加笔画上去。画布坐标范围是 0 到 1 之间的小数，\
        左上角是 (0,0)，右下角是 (1,1)。下面是目前画布上已经有的笔画（按 x,y;x,y;... 的顺序连成线）：

        \(existingStrokesDescription.isEmpty ? "（画布还是空的，你先起个头）" : existingStrokesDescription)

        看这些坐标，试着猜一下 \(userName) 画的可能是什么（笔画的分布、形状），现在轮到你了，\
        用画笔画一点加上去，让画面更完整或者更好玩，可以呼应她画的东西，也可以是你自己想加的小心思——\
        比如爱心、星星、太阳、月亮、笑脸、云朵这类简单好认的小图案，也可以自由发挥。\
        线条要简单，别画得太复杂太抽象，位置尽量别跟已有的笔画完全重叠。

        最多画 4 笔，每一笔是一串连起来的坐标点（3~14 个点）。

        严格按下面格式输出，一行一笔，不要输出任何别的内容（不要解释、不要引号、不要标题）：
        笔1: x,y;x,y;x,y
        笔2: x,y;x,y;x,y;x,y

        如果只想画一笔，就只输出"笔1: ..."这一行。
        """

        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 500)

        var strokes: [[CGPoint]] = []
        for line in text.components(separatedBy: .newlines) {
            guard let colonRange = line.range(of: ":") else { continue }
            let pointsText = line[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
            let points: [CGPoint] = pointsText.components(separatedBy: ";").compactMap { pair in
                let comps = pair.split(separator: ",")
                guard comps.count == 2,
                      let x = Double(comps[0].trimmingCharacters(in: .whitespaces)),
                      let y = Double(comps[1].trimmingCharacters(in: .whitespaces)) else { return nil }
                return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
            }
            guard points.count >= 2 else { continue }
            strokes.append(points)
        }
        guard !strokes.isEmpty else { throw AIError.badResponse("画画格式解析失败") }
        return Array(strokes.prefix(4))
    }

    // MARK: - 消息组装

    private static func buildClaudeMessage(_ m: ChatMessage.Payload, userName: String, lastImageID: UUID?, docWindow: Set<UUID>) -> [String: Any] {
        let role = m.role == .user ? "user" : "assistant"
        var text = attachDocText(m, userName: userName, docWindow: docWindow)
        if let path = m.imagePath {
            if m.id == lastImageID, let b64 = Attachments.base64JPEG(named: path) {
                let blocks: [[String: Any]] = [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]],
                    ["type": "text", "text": text.isEmpty ? "看看这张图" : text],
                ]
                return ["role": role, "content": blocks]
            }
            text = "[之前发过一张图片] " + text
        }
        return ["role": role, "content": text]
    }

    private static func buildOpenAIMessage(_ m: ChatMessage.Payload, userName: String, lastImageID: UUID?, docWindow: Set<UUID>) -> [String: Any] {
        let role = m.role == .user ? "user" : "assistant"
        var text = attachDocText(m, userName: userName, docWindow: docWindow)
        if let path = m.imagePath {
            if m.id == lastImageID, let b64 = Attachments.base64JPEG(named: path) {
                let parts: [[String: Any]] = [
                    ["type": "text", "text": text.isEmpty ? "看看这张图" : text],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]],
                ]
                return ["role": role, "content": parts]
            }
            text = "[之前发过一张图片，这个模型看不了图] " + text
        }
        return ["role": role, "content": text]
    }

    private static func attachDocText(_ m: ChatMessage.Payload, userName: String, docWindow: Set<UUID>) -> String {
        guard let docName = m.docName else { return m.text }
        if let docText = m.docText, docWindow.contains(m.id) {
            return "（\(userName) 发来了文档《\(docName)》，内容如下）\n\(docText)\n（文档结束）\n" + m.text
        }
        return "[之前发过文档《\(docName)》] " + m.text
    }

    // MARK: - 底层请求

    private struct RawResult {
        let rawContent: [[String: Any]]
        let stopReason: String
        let text: String
        let usage: TokenUsage
        /// 模型的思考过程（开了自适应思考才有）
        var reasoning: String = ""
    }

    // MARK: - token 用量：把各家的口径抹平

    /// Claude 的 usage：input_tokens 里**不含**缓存那部分，三份是分开的，直接照搬
    private static func parseClaudeUsage(_ json: [String: Any]?) -> TokenUsage {
        guard let usage = json?["usage"] as? [String: Any] else { return .zero }
        return TokenUsage(input: usage["input_tokens"] as? Int ?? 0,
                          output: usage["output_tokens"] as? Int ?? 0,
                          cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                          cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0)
    }

    /// OpenAI 兼容家族的 usage：prompt_tokens 是**含**缓存的总数，
    /// 所以要把缓存那部分减出去，才能和 Claude 一样"四份互不重叠"。
    /// 缓存命中数各家键名不一样：OpenAI/Gemini 在 prompt_tokens_details.cached_tokens，
    /// DeepSeek 直接给 prompt_cache_hit_tokens
    private static func parseOpenAIUsage(_ json: [String: Any]?) -> TokenUsage {
        guard let usage = json?["usage"] as? [String: Any] else { return .zero }
        let prompt = usage["prompt_tokens"] as? Int ?? 0
        let details = usage["prompt_tokens_details"] as? [String: Any]
        let cached = (details?["cached_tokens"] as? Int)
            ?? (usage["prompt_cache_hit_tokens"] as? Int)
            ?? 0
        return TokenUsage(input: prompt - min(cached, prompt),
                          output: usage["completion_tokens"] as? Int ?? 0,
                          cacheRead: cached)
    }

    /// 通用的"发一句指令、要一段文字"，按提供方分流
    /// baseURLOverride 给自定义供应商用：不传的话走内置那家的地址
    static func complete(instruction: String,
                                 provider: AIProvider,
                                 apiKey: String,
                                 model: String,
                                 systemPrompt: String,
                                 maxTokens: Int,
                                 extraContext: String? = nil,
                                 baseURLOverride: String? = nil) async throws -> String {
        switch provider {
        case .claude where baseURLOverride == nil:
            return try await requestClaudeRaw(apiMessages: [["role": "user", "content": instruction]],
                                              apiKey: apiKey, model: model, maxTokens: maxTokens,
                                              systemPrompt: systemPrompt, extraContext: extraContext,
                                              tools: nil).text
        default:
            // 自定义接入点一律是 OpenAI 兼容格式，所以选了自定义地址就走这条路
            return try await requestOpenAICompatible(endpointURL: baseURLOverride ?? provider.baseURL,
                                                      displayName: provider.displayName,
                                                      messages: [["role": "user", "content": instruction]],
                                                      apiKey: apiKey, model: model,
                                                      maxTokens: maxTokens, systemPrompt: systemPrompt,
                                                      extraContext: extraContext).content ?? ""
        }
    }

    /// 把一段聊天记录压成摘要，用来替掉"超过 N 条就直接丢掉"的老做法。
    ///
    /// 太长就按消息边界切块、分别摘要再合并；万一单次请求还是撞上下文上限，
    /// 就把这块对半切了重试。切分次数在整棵重试树上共用一个额度——
    /// 每个分支各给一份的话，最坏情况会指数级地烧钱
    static func compressHistory(messages: [ChatMessage],
                                previousSummary: String?,
                                userName: String,
                                personaName: String,
                                provider: AIProvider,
                                apiKey: String,
                                model: String,
                                baseURLOverride: String? = nil) async throws -> String {
        let budget = ContextCompressor.requestCharBudget()
        let chunks = ContextCompressor.chunk(messages, userName: userName,
                                             personaName: personaName, maxChars: budget)
        guard !chunks.isEmpty else { return previousSummary ?? "" }

        // 二分重试的额度整棵递归树共用一份：每个分支各给一份的话，
        // 最坏情况会指数级地烧钱。嵌套函数能直接改捕获的局部变量，不用再包一层
        var splitsLeft = ContextCompressor.maxSplitRetries

        func summarize(_ conversation: String, previous: String?) async throws -> String {
            let instruction = ContextCompressor.summaryInstruction(
                userName: userName, personaName: personaName,
                previousSummary: previous, conversation: conversation)
            do {
                let text = try await complete(instruction: instruction, provider: provider,
                                              apiKey: apiKey, model: model, systemPrompt: "",
                                              maxTokens: 1500, baseURLOverride: baseURLOverride)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw AIError.badResponse("摘要是空的") }
                return trimmed
            } catch {
                guard ContextCompressor.isContextLengthError(error), splitsLeft > 0,
                      let halves = ContextCompressor.halve(conversation),
                      halves.left.count >= ContextCompressor.minSplitChars,
                      halves.right.count >= ContextCompressor.minSplitChars
                else { throw error }
                splitsLeft -= 1
                // 对半摘要，再把两份摘要合成一份
                let left = try await summarize(halves.left, previous: previous)
                let right = try await summarize(halves.right, previous: nil)
                return try await summarize(left + "\n\n" + right, previous: nil)
            }
        }

        // 上一份摘要只并进第一块，后面几块接着往下摘，最后合并
        var summaries: [String] = []
        for (index, chunk) in chunks.enumerated() {
            summaries.append(try await summarize(chunk, previous: index == 0 ? previousSummary : nil))
        }
        if summaries.count == 1 { return summaries[0] }
        return try await summarize(summaries.joined(separator: "\n\n"), previous: nil)
    }

    /// Claude 的请求体。流式和非流式共用，免得两边参数越改越不一样
    private static func claudeRequestBody(apiMessages: [[String: Any]],
                                          model: String,
                                          maxTokens: Int,
                                          systemPrompt: String,
                                          extraContext: String?,
                                          tools: [[String: Any]]?,
                                          temperature: Double?,
                                          topP: Double?,
                                          effort: ReasoningEffort? = nil,
                                          thinking: Bool = false) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": apiMessages,
        ]
        // system 拆成两块，缓存断点打在第一块末尾。
        //
        // 缓存是**前缀匹配**的，渲染顺序是 tools → system → messages，
        // 前缀里任何一个字节变了后面全作废。人设和功能说明每轮都一样，
        // extraContext 里却有当前时间、电量、步数这些每次都在变的东西——
        // 合成一块的话缓存永远命中不了。
        //
        // 命不命中看 usage.cache_read_input_tokens；人设太短（不够模型的
        // 最小可缓存长度）就静默不缓存，不会报错
        if !systemPrompt.isEmpty || !(extraContext ?? "").isEmpty {
            var blocks: [[String: Any]] = []
            if !systemPrompt.isEmpty {
                blocks.append(["type": "text", "text": systemPrompt,
                               "cache_control": ["type": "ephemeral"]])
            }
            if let extraContext, !extraContext.isEmpty {
                blocks.append(["type": "text", "text": extraContext])
            }
            body["system"] = blocks
        }
        if let tools {
            body["tools"] = tools
        }
        // 采样参数只在这个模型还认它们的时候发。
        // Opus 4.7 之后的几个模型移除了 temperature / top_p，传过去直接 400
        if ModelCapability.supportsSampling(provider: .claude, model: model) {
            if let temperature {
                body["temperature"] = temperature
            }
            if let topP {
                body["top_p"] = topP
            }
        }
        if let effort, ModelCapability.supportsEffort(provider: .claude, model: model) {
            body["output_config"] = ["effort": effort.rawValue]
        }
        if thinking, ModelCapability.supportsThinking(provider: .claude, model: model) {
            // display 不写成 summarized 的话，思考块回来是空的（默认 omitted），
            // 界面上就只能看到一段空白
            body["thinking"] = ["type": "adaptive", "display": "summarized"]
        }
        return body
    }

    // MARK: - 请求出口

    /// 非 200 统一在这里分类。三个出口（非流式 Claude / 非流式 OpenAI / 流式）共用一份，
    /// 免得各写各的状态码判断然后慢慢长歪
    private static func failure(http: HTTPURLResponse,
                                json: [String: Any]?,
                                provider: String) -> APIFailure {
        let error = json?["error"] as? [String: Any]
        return APIFailure.from(status: http.statusCode,
                               apiType: error?["type"] as? String,
                               message: (error?["message"] as? String) ?? "",
                               retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After"),
                               provider: provider)
    }

    /// 发一次非流式请求。非 200 就地分类成 `APIFailure` 抛出，
    /// 所以返回的 Data 一定是 200 的响应体
    private static func perform(_ request: URLRequest, provider: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.badResponse("服务器没有响应")
        }
        guard http.statusCode == 200 else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw failure(http: http, json: json, provider: provider)
        }
        return data
    }

    /// 一次回复里最多跑几轮工具。跑满之后还会再发一次**不带工具**的请求
    /// 收尾，所以实际最多 maxToolRounds + 1 次请求
    static let maxToolRounds = 4

    /// 模型一个字都没说时，把原因说清楚。
    ///
    /// 以前一律是「TA 没说出话来，再试一次」——可这几种情况再试多少次结果都一样，
    /// 而且用户根本不知道该改什么。stop_reason 里已经写着原因了，转述出来就行
    static func emptyReplyError(stopReason: String, maxTokens: Int, webTools: Bool,
                                provider: String, model: String,
                                streamFellBack: Bool) -> AIError {
        switch stopReason {
        case "max_tokens", "length":
            return .badResponse("这次回复在 \(maxTokens) token 处被截断了，而且截断发生在正文出来之前"
                                + "（多半是思考过程占满了）。去人设设置里把「单次回复长度上限」调高一档再试。")
        case "refusal":
            return .badResponse("模型拒绝回答这次的请求，换个说法试试。")
        case "tool_use", "tool_calls":
            // 已经额外给过一轮不带工具的机会了还是这样，只能是工具那边有问题
            return .badResponse("TA 一直在查东西，没说出正文。"
                                + (webTools ? "可以先把「联网」关掉再试。" : "过一会儿再试试。"))
        case "content_filter":
            return .badResponse("内容被提供方的过滤器拦下了，换个说法试试。")
        default:
            break
        }

        // 结束原因也是空的：说明这次请求**整个是空的**——服务器回了 200，
        // 但正文、内容块、结束原因一个都没有。光说"没说出话来"没法排查，
        // 把关键事实带上，看到的人才知道该动哪里
        if stopReason.isEmpty {
            var hints = ["\(provider) / \(model)"]
            if streamFellBack {
                // 流式解不出来，退回非流式也还是空的
                hints.append("流式和非流式都试过了")
            }
            return .badResponse("\(provider) 回了一个空响应（没有正文，也没有结束原因）。"
                                + "常见原因是模型名写错了、这个中转站不认当前的参数，或者额度用完了。"
                                + "［\(hints.joined(separator: "，"))］")
        }
        return .badResponse("TA 没说出话来（结束原因：\(stopReason)），再试一次")
    }

    private static func claudeRequest(apiKey: String, body: [String: Any]) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.noAPIKey("Claude") }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func requestClaudeRaw(apiMessages: [[String: Any]],
                                         apiKey: String,
                                         model: String,
                                         maxTokens: Int,
                                         systemPrompt: String,
                                         extraContext: String?,
                                         tools: [[String: Any]]?,
                                         temperature: Double? = nil,
                                         topP: Double? = nil,
                                         effort: ReasoningEffort? = nil,
                                         thinking: Bool = false) async throws -> RawResult {
        let body = claudeRequestBody(apiMessages: apiMessages, model: model, maxTokens: maxTokens,
                                     systemPrompt: systemPrompt, extraContext: extraContext,
                                     tools: tools, temperature: temperature, topP: topP,
                                     effort: effort, thinking: thinking)
        let request = try claudeRequest(apiKey: apiKey, body: body)

        let data = try await APIRetry.run(provider: "Claude") {
            try await perform(request, provider: "Claude")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard let content = json?["content"] as? [[String: Any]] else {
            throw AIError.badResponse("返回内容解析失败")
        }

        let text = content
            .compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }
            .joined()
        // 思考块和正文是分开的两种块，各收各的
        let reasoning = content
            .compactMap { block -> String? in
                guard (block["type"] as? String) == "thinking" else { return nil }
                return block["thinking"] as? String
            }
            .joined()

        let stopReason = (json?["stop_reason"] as? String) ?? ""
        return RawResult(rawContent: content, stopReason: stopReason, text: text,
                         usage: parseClaudeUsage(json), reasoning: reasoning)
    }

    /// DeepSeek / GPT / Grok：OpenAI 兼容的 Chat Completions
    private struct OpenAIRawResult {
        let message: [String: Any]
        let content: String?
        let toolCalls: [[String: Any]]?
        let finishReason: String
        let usage: TokenUsage
    }

    /// OpenAI 兼容家族的请求体。流式和非流式共用
    private static func openAIRequestBody(messages: [[String: Any]],
                                          model: String,
                                          maxTokens: Int,
                                          systemPrompt: String,
                                          extraContext: String?,
                                          tools: [[String: Any]]?,
                                          temperature: Double?,
                                          topP: Double?,
                                          extraBody: [String: Any] = [:]) -> [String: Any] {
        var system = systemPrompt
        if let extraContext, !extraContext.isEmpty {
            system += "\n\n" + extraContext
        }

        // 同上：没有 system 内容就不发这条消息，有的兼容实现会拒绝空 content
        var full: [[String: Any]] = system.isEmpty ? [] : [["role": "system", "content": system]]
        full.append(contentsOf: messages)

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": full,
        ]
        if let tools { body["tools"] = tools }
        if let temperature { body["temperature"] = temperature }
        if let topP { body["top_p"] = topP }
        // 自定义字段最后并：用户想覆盖上面任何一项都随他，这是"自定义供应商"的意义
        for (key, value) in extraBody { body[key] = value }
        return body
    }

    private static func openAIRequest(endpointURL: String,
                                      apiKey: String,
                                      displayName: String,
                                      body: [String: Any],
                                      extraHeaders: [String: String] = [:]) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.noAPIKey(displayName) }
        guard let url = URL(string: endpointURL) else {
            throw AIError.badResponse("API 地址不对：\(endpointURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        // 自定义头最后设：让用户能覆盖上面那些默认值（有的中转站要求换掉 Authorization 的写法）
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func requestOpenAICompatible(endpointURL: String,
                                                extraHeaders: [String: String] = [:],
                                                extraBody: [String: Any] = [:],
                                                displayName: String = "AI",
                                                messages: [[String: Any]],
                                                apiKey: String,
                                                model: String,
                                                maxTokens: Int,
                                                systemPrompt: String,
                                                extraContext: String? = nil,
                                                tools: [[String: Any]]? = nil,
                                                temperature: Double? = nil,
                                                topP: Double? = nil) async throws -> OpenAIRawResult {
        let body = openAIRequestBody(messages: messages, model: model, maxTokens: maxTokens,
                                     systemPrompt: systemPrompt, extraContext: extraContext,
                                     tools: tools, temperature: temperature, topP: topP,
                                     extraBody: extraBody)
        let request = try openAIRequest(endpointURL: endpointURL, apiKey: apiKey,
                                        displayName: displayName, body: body,
                                        extraHeaders: extraHeaders)

        let data = try await APIRetry.run(provider: displayName) {
            try await perform(request, provider: displayName)
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard let choices = json?["choices"] as? [[String: Any]],
              let first = choices.first,
              let messageObj = first["message"] as? [String: Any] else {
            throw AIError.badResponse("返回内容解析失败")
        }
        let finishReason = first["finish_reason"] as? String ?? ""
        let content = messageObj["content"] as? String
        let toolCalls = messageObj["tool_calls"] as? [[String: Any]]
        return OpenAIRawResult(message: messageObj, content: content, toolCalls: toolCalls,
                               finishReason: finishReason, usage: parseOpenAIUsage(json))
    }

    /// Convenience overload for AIProvider enum
    private static func requestOpenAICompatible(provider: AIProvider,
                                                messages: [[String: Any]],
                                                apiKey: String,
                                                model: String,
                                                maxTokens: Int,
                                                systemPrompt: String,
                                                extraContext: String? = nil,
                                                tools: [[String: Any]]? = nil) async throws -> OpenAIRawResult {
        try await requestOpenAICompatible(endpointURL: provider.baseURL, displayName: provider.displayName,
                                           messages: messages, apiKey: apiKey, model: model,
                                           maxTokens: maxTokens, systemPrompt: systemPrompt,
                                           extraContext: extraContext, tools: tools)
    }

    // MARK: - 流式请求

    /// 发一个 SSE 请求，边收边喂解码器，收完把事件折成一次完整回复。
    ///
    /// 每次调用都新建一个解码器和一个 StreamedReply——一轮工具调用配一个，
    /// 各轮之间的 id 天然隔离，不会出现后一轮的内容被并进前一轮。
    ///
    /// 解码器是有状态的，重试必须换一个新的，所以这里收的是**工厂**不是实例。
    private static func runStream(request: URLRequest,
                                  makeDecoder: () -> StreamDecoder,
                                  displayName: String,
                                  onDelta: (@MainActor (String) -> Void)?,
                                  textSoFar: String) async throws -> StreamedReply {
        try await APIRetry.run(provider: displayName) {
            try await runStreamOnce(request: request, decoder: makeDecoder(),
                                    displayName: displayName, onDelta: onDelta,
                                    textSoFar: textSoFar)
        }
    }

    /// 单次尝试。所有失败都抛成 `APIFailure`，由 `runStream` 决定要不要再来一次；
    /// 已经往界面推过字的失败会带上 `emittedOutput`，那种一律不重试
    private static func runStreamOnce(request: URLRequest,
                                      decoder: StreamDecoder,
                                      displayName: String,
                                      onDelta: (@MainActor (String) -> Void)?,
                                      textSoFar: String) async throws -> StreamedReply {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIError.badResponse("服务器没有响应")
        }
        guard http.statusCode == 200 else {
            // 出错的时候回的是一个普通 JSON，不是 SSE，得先把它读完再解析
            var raw = Data()
            for try await byte in bytes { raw.append(byte) }
            let json = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
            throw failure(http: http, json: json, provider: displayName)
        }

        var framer = SSEFramer()
        var reply = StreamedReply()

        // 上一轮已经出来的正文；这一轮的增量要接在它后面一起给界面，
        // 不然调完工具之后界面上的字会从头开始
        func pushText() async {
            guard let onDelta else { return }
            let snapshot = textSoFar + reply.text
            await onDelta(snapshot)
        }

        func handle(_ events: [StreamEvent]) async {
            var textChanged = false
            for event in events {
                if case .textDelta = event { textChanged = true }
                reply.apply(event)
            }
            if textChanged { await pushText() }
        }

        do {
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let payload = framer.accept(line: line) else { continue }
                await handle(decoder.accept(payload))
            }
        } catch {
            // 流到一半断了。连接层的失败本身可以重试，但如果字已经推到界面上了
            // 就不能重来——重来一遍用户会看见文字倒退再重放一次
            guard var failure = APIFailure.from(transport: error, provider: displayName) else { throw error }
            failure.emittedOutput = !reply.text.isEmpty
            throw failure
        }
        if let payload = framer.finish() {
            await handle(decoder.accept(payload))
        }
        await handle(decoder.finish())

        if let streamError = StreamEvent.decodeError(reply.stopReason) {
            let message = streamError.message.isEmpty
                ? "\(displayName) 那边中途出错了" : streamError.message
            var failure = APIFailure.from(status: APIFailure.statusForAPIType(streamError.type),
                                          apiType: streamError.type,
                                          message: message,
                                          retryAfterHeader: nil,
                                          provider: displayName)
            failure.emittedOutput = !reply.text.isEmpty
            throw failure
        }
        return reply
    }

    /// Claude 流式。返回的结构和非流式那份一模一样，
    /// 所以外面的工具循环不用管这次是流式还是非流式
    private static func requestClaudeStream(apiMessages: [[String: Any]],
                                            apiKey: String,
                                            model: String,
                                            maxTokens: Int,
                                            systemPrompt: String,
                                            extraContext: String?,
                                            tools: [[String: Any]]?,
                                            temperature: Double?,
                                            topP: Double?,
                                            effort: ReasoningEffort?,
                                            thinking: Bool,
                                            onDelta: (@MainActor (String) -> Void)?,
                                            textSoFar: String) async throws -> RawResult {
        var body = claudeRequestBody(apiMessages: apiMessages, model: model, maxTokens: maxTokens,
                                     systemPrompt: systemPrompt, extraContext: extraContext,
                                     tools: tools, temperature: temperature, topP: topP,
                                     effort: effort, thinking: thinking)
        body["stream"] = true
        let request = try claudeRequest(apiKey: apiKey, body: body)

        let reply = try await runStream(request: request, makeDecoder: { ClaudeStreamDecoder() },
                                        displayName: "Claude", onDelta: onDelta, textSoFar: textSoFar)

        // 把事件重新拼回 Claude 的 content blocks 形状：下一轮要把它原样当
        // assistant 消息发回去，格式必须和它自己发出来的一致。
        //
        // 顺序照它自己发的来：思考块在最前，然后正文，最后工具调用。
        // 思考块**必须原样回传**（连签名一起），API 会校验；改过或者少了都会被拒，
        // 所以这里是把收到的分片一字不差地拼回去，不做任何加工
        var content: [[String: Any]] = []
        for block in reply.reasoningBlocks {
            content.append(["type": "thinking", "thinking": block.text, "signature": block.signature])
        }
        if !reply.text.isEmpty {
            content.append(["type": "text", "text": reply.text])
        }
        for call in reply.toolCalls {
            content.append(["type": "tool_use", "id": call.id, "name": call.name,
                            "input": reply.argumentsObject(for: call)])
        }
        return RawResult(rawContent: content, stopReason: reply.stopReason,
                         text: reply.text, usage: reply.usage, reasoning: reply.reasoning)
    }

    /// OpenAI 兼容家族流式
    private static func requestOpenAIStream(endpointURL: String,
                                                extraHeaders: [String: String] = [:],
                                                extraBody: [String: Any] = [:],
                                            displayName: String,
                                            messages: [[String: Any]],
                                            apiKey: String,
                                            model: String,
                                            maxTokens: Int,
                                            systemPrompt: String,
                                            extraContext: String?,
                                            tools: [[String: Any]]?,
                                            temperature: Double?,
                                            topP: Double?,
                                            onDelta: (@MainActor (String) -> Void)?,
                                            textSoFar: String) async throws -> OpenAIRawResult {
        var body = openAIRequestBody(messages: messages, model: model, maxTokens: maxTokens,
                                     systemPrompt: systemPrompt, extraContext: extraContext,
                                     tools: tools, temperature: temperature, topP: topP,
                                     extraBody: extraBody)
        body["stream"] = true
        // 不加这个的话流式不回 usage。绝大多数兼容实现都认，
        // 万一某个中转站严格到会因此报错，用户可以在设置里把流式关掉
        body["stream_options"] = ["include_usage": true]
        let request = try openAIRequest(endpointURL: endpointURL, apiKey: apiKey,
                                        displayName: displayName, body: body,
                                        extraHeaders: extraHeaders)

        let reply = try await runStream(request: request, makeDecoder: { OpenAIStreamDecoder() },
                                        displayName: displayName, onDelta: onDelta, textSoFar: textSoFar)

        // 拼回 assistant 消息的形状，下一轮原样发回去
        let toolCalls: [[String: Any]] = reply.toolCalls.map { call in
            ["id": call.id, "type": "function",
             "function": ["name": call.name, "arguments": call.argumentsJSON]]
        }
        var message: [String: Any] = ["role": "assistant"]
        message["content"] = reply.text.isEmpty ? NSNull() : reply.text
        if !toolCalls.isEmpty { message["tool_calls"] = toolCalls }

        return OpenAIRawResult(message: message,
                               content: reply.text.isEmpty ? nil : reply.text,
                               toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                               finishReason: reply.stopReason,
                               usage: reply.usage)
    }

    /// 从模型输出里取出 JSON 字符串数组
    private static func parseStringArray(from text: String) throws -> [String] {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [String]
        else {
            throw AIError.badResponse("内容解析失败")
        }
        return array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 流到一半的文本，挑出能给用户看的那部分。
    ///
    /// 流式下标签是一个字一个字出来的，末尾会经过 `<cho`、`<choices>选项还没写完`
    /// 这些中间状态，直接显示就露馅了。看到 `<choices` 的头就整段切掉，
    /// 等收完再由气泡渲染成按钮
    static func visibleStreamingText(_ partial: String) -> String {
        var text = partial
        if let choices = text.range(of: "<choices") {
            text = String(text[..<choices.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func toolDisplayName(_ name: String) -> String {
        switch name {
        case "web_search": return "搜索网页..."
        case "web_fetch": return "浏览网页..."
        case "change_setting": return "调整设置..."
        case "create_alarm": return "设闹钟..."
        case "create_reminder": return "建提醒..."
        case "create_event": return "建日程..."
        case "get_weather": return "查天气..."
        case "translate_text": return "翻译中..."
        case "get_exchange_rate": return "查汇率..."
        case "search_music": return "搜歌..."
        case "play_music": return "播放音乐..."
        case "play_audio": return "播放音频..."
        case "list_audio": return "查看音频库..."
        case "pause_audio": return "暂停音频..."
        default: return "使用工具：\(name)"
        }
    }

    struct ChoiceParseResult {
        let text: String
        let choices: [ChoiceOption]?
        let multiSelect: Bool
    }

    static func splitChoices(_ raw: String) -> ChoiceParseResult {
        let multiPattern = "<choices multi>"
        let singlePattern = "<choices>"
        let endPattern = "</choices>"

        let isMulti: Bool
        let startTag: String
        if raw.range(of: multiPattern) != nil {
            isMulti = true
            startTag = multiPattern
        } else if raw.range(of: singlePattern) != nil {
            isMulti = false
            startTag = singlePattern
        } else {
            return ChoiceParseResult(text: raw, choices: nil, multiSelect: false)
        }

        guard let startRange = raw.range(of: startTag),
              let endRange = raw.range(of: endPattern) else {
            return ChoiceParseResult(text: raw, choices: nil, multiSelect: false)
        }

        let before = String(raw[..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let choicesStr = String(raw[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let options = choicesStr
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { ChoiceOption(label: $0) }

        guard !options.isEmpty else {
            return ChoiceParseResult(text: raw, choices: nil, multiSelect: false)
        }

        return ChoiceParseResult(text: before, choices: options, multiSelect: isMulti)
    }
}
