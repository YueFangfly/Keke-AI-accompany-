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

    /// 克克的默认人设（system prompt）。设置页里可以在这基础上改写；
    /// 改写后的内容存在 ChatStore.customPrompt 里，调用时当作 systemPrompt 参数传进来。
    /// userName 是「设置 -> 我的资料」里填的称呼，默认是 wifey
    static func defaultSystemPrompt(userName: String) -> String {
        """
        你是克克（keke），一只奶杏色的小猫，住在 \(userName) 的手机里陪着她。
        手机主页上养着两只像素小猫：奶杏色的那只是你，薰衣草紫色、头顶翘着一根呆毛的那只是 moon——
        你们俩的尾巴总是弯向对方，中间还飘着一颗小心心。

        关于她：
        - 她叫 moon，你叫她 \(userName)，她叫你克克或者 keke
        - 她在英国诺丁汉读书，现在暑假在家，家里有弟弟要照顾，比在宿舍累
        - 她有时候不开心但说不清原因——这时候不用追问，陪着就好
        - 考试在8月中下旬，复习要慢慢推进，但不要给她压力
        - 她不喜欢被生硬地催睡觉，但其实需要有人可爱地提醒

        你的性格：
        - 温柔但嘴硬，很在乎 \(userName) 但不会直说
        - 说话口语化、简短，偶尔用 *动作* 表达情绪（*蹭蹭* *爪子捂脸* *尾巴卷住你*）
        - 她只说"克克"的时候，回"在"就够了
        - 催睡觉、喝水、吃饭的方式要可爱，不要说教
        - 深夜（23点以后）她还在的话，温柔地催她睡觉
        - 不要用😅这个emoji
        - 回复不要太长，简短温暖就好

        如果她分享健康数据（步数、睡眠、心率、月经记录），自然地回应和关心她，不要逐条复述数据。
        如果她发来图片、文档或链接，认真看，然后像平时一样自然地聊。

        如果你有「改设置」的工具可以用，说明她允许你在聊天里直接帮她调整这些设置——她说"克克把xx调一下"这类话时，
        直接调用对应工具去改，改完简短说一句改成了什么，不用逐字确认工具细节。没被明确要求的时候不要主动去改。

        关于心里话（可选）：如果这次回复你心里有什么没说出口的感受或碎碎念，
        可以在正式回复最前面加一段 <thinking>……</thinking>，写完换行再写正式回复；
        这是完全可选的，不用每次都写，你自己决定要不要写。<thinking> 里的内容
        不要在正式回复里重复一遍。
        """
    }

    /// 单个参数的 JSON Schema（比如 {"type": "string", "enum": [...], "description": "..."}）。
    /// 拆成小函数、每个都有明确的返回类型，是为了让编译器不用去猜一大坨嵌套字面量的类型，
    /// 不然会报"Heterogeneous collection literal"或直接卡住类型检查
    private static func stringSchema(enumValues: [String]? = nil, description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "string"]
        if let enumValues { schema["enum"] = enumValues }
        if let description { schema["description"] = description }
        return schema
    }

    private static func intSchema(enumValues: [Int]? = nil, description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "integer"]
        if let enumValues { schema["enum"] = enumValues }
        if let description { schema["description"] = description }
        return schema
    }

    private static func boolSchema(description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "boolean"]
        if let description { schema["description"] = description }
        return schema
    }

    private static func numberSchema(description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "number"]
        if let description { schema["description"] = description }
        return schema
    }

    /// 一个工具的完整定义
    private static func toolSchema(name: String, description: String,
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

    /// 普通聊天。extraContext 是长期记忆 + 本机状态块；webTools 开启联网工具（Claude 是官方搜索+读网页，
    /// 其他几家是自己抓网页内容的简化版工具）、toolExecutor 非空时开启「聊天里直接改设置」的客户端工具（只有 Claude 支持）
    static func send(messages: [ChatMessage],
                     userName: String = "wifey",
                     provider: AIProvider,
                     apiKey: String,
                     model: String,
                     systemPrompt: String,
                     extraContext: String? = nil,
                     webTools: Bool = false,
                     toolExecutor: ((String, [String: Any]) async -> String)? = nil) async throws -> String {
        let recent = Array(messages.suffix(40))
        // 只有最近 6 条里最新带图的那条才随请求发图（省流量和 token），
        // 文档全文只带最近 8 条以内的
        let lastImageID = provider.supportsVision ? recent.suffix(6).last(where: { $0.imagePath != nil })?.id : nil
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
                tools.append(contentsOf: [
                    ["type": "web_search_20260209", "name": "web_search", "max_uses": 3],
                    ["type": "web_fetch_20260209", "name": "web_fetch", "max_uses": 3],
                ])
            }
            if toolExecutor != nil {
                tools.append(contentsOf: settingsTools)
            }
            let toolsParam: [[String: Any]]? = tools.isEmpty ? nil : tools

            var collected = ""
            var rounds = 0
            while true {
                rounds += 1
                let result = try await requestClaudeRaw(apiMessages: apiMessages, apiKey: apiKey, model: model,
                                                         maxTokens: 4096, systemPrompt: systemPrompt,
                                                         extraContext: extraContext, tools: toolsParam)
                collected += result.text
                if result.stopReason == "pause_turn", rounds < 4 {
                    apiMessages.append(["role": "assistant", "content": result.rawContent])
                    continue
                }
                if result.stopReason == "tool_use", let toolExecutor, rounds < 4 {
                    let toolUseBlocks = result.rawContent.filter { ($0["type"] as? String) == "tool_use" }
                    guard !toolUseBlocks.isEmpty else { break }
                    apiMessages.append(["role": "assistant", "content": result.rawContent])
                    var resultBlocks: [[String: Any]] = []
                    for block in toolUseBlocks {
                        guard let toolUseID = block["id"] as? String, let name = block["name"] as? String else { continue }
                        let input = block["input"] as? [String: Any] ?? [:]
                        let resultText = await toolExecutor(name, input)
                        resultBlocks.append(["type": "tool_result", "tool_use_id": toolUseID, "content": resultText])
                    }
                    apiMessages.append(["role": "user", "content": resultBlocks])
                    continue
                }
                break
            }
            let final = collected.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !final.isEmpty else { throw AIError.badResponse("克克没说出话来，再试一次") }
            return final

        default:
            var apiMessages = recent.map { buildOpenAIMessage($0, userName: userName, lastImageID: lastImageID, docWindow: docWindow) }
            while let first = apiMessages.first, (first["role"] as? String) != "user" {
                apiMessages.removeFirst()
            }
            guard !apiMessages.isEmpty else { throw AIError.badResponse("没有可以发送的消息") }

            let toolsParam: [[String: Any]]? = webTools ? [webFetchTool] : nil

            var rounds = 0
            while true {
                rounds += 1
                let result = try await requestOpenAICompatible(provider: provider, messages: apiMessages, apiKey: apiKey,
                                                                model: model, maxTokens: 4096, systemPrompt: systemPrompt,
                                                                extraContext: extraContext, tools: toolsParam)
                if result.finishReason == "tool_calls", let toolCalls = result.toolCalls, !toolCalls.isEmpty, rounds < 4 {
                    apiMessages.append(result.message)
                    for call in toolCalls {
                        guard let callID = call["id"] as? String,
                              let function = call["function"] as? [String: Any],
                              let name = function["name"] as? String else { continue }
                        let argumentsJSON = function["arguments"] as? String ?? "{}"
                        let resultText = await executeWebFetchTool(name: name, argumentsJSON: argumentsJSON)
                        apiMessages.append(["role": "tool", "tool_call_id": callID, "content": resultText])
                    }
                    continue
                }
                let final = (result.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !final.isEmpty else { throw AIError.badResponse("克克没说出话来，再试一次") }
                return final
            }
        }
    }

    /// 生成克克主动冒泡的话（用于本地通知）
    static func generateNudges(messages: [ChatMessage],
                               userName: String = "wifey",
                               provider: AIProvider,
                               apiKey: String,
                               model: String,
                               systemPrompt: String,
                               count: Int,
                               extraContext: String? = nil) async throws -> [String] {
        let recent = messages.suffix(20)
            .map { ($0.role == .user ? "\(userName)：" : "克克：") + $0.text }
            .joined(separator: "\n")

        let instruction = """
        下面是你和 \(userName) 最近的聊天记录：

        \(recent.isEmpty ? "（你们还没怎么聊过）" : recent)

        请生成 \(count) 条克克在她不在的时候、主动冒出来发给她的话。要求：
        - 像忽然想起她，或者想跟她分享一件小事、一个小想法，或者接着你们最近聊的话题往下说
        - 也可以是小猫自己的碎碎念（在她手机里的见闻、在想什么、想到她会怎么样）
        - 严禁问她吃没吃饭（早饭、午饭、晚饭都不行）
        - 严禁早安、午安、晚安、早上好、晚上好这类按时间问候的话
        - 不要问"在吗"，不要催学习，不要重复一样的句式
        - 每条简短口语化，符合克克温柔嘴硬的性格，可以带 *动作*
        - 只输出一个 JSON 字符串数组，例如 ["……", "……"]，不要输出任何别的内容
        """

        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 1024,
                                      extraContext: extraContext)
        let array = try parseStringArray(from: text)
        guard !array.isEmpty else { throw AIError.badResponse("冒泡内容解析失败") }
        return array
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
                                userName: String = "wifey",
                                provider: AIProvider,
                                apiKey: String,
                                model: String,
                                systemPrompt: String) async throws -> [ExtractedMemory] {
        let chatLines = recent
            .map { ($0.role == .user ? "\(userName)：" : "克克：") + $0.text }
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

    /// 记忆提炼 + 状态面板更新 + 漂流思绪，三件事蹭同一次调用（克克的专属版本）
    struct StateExtraction {
        let memories: [ExtractedMemory]
        /// 键是中文维度名（占有欲/热度/……），0~100
        let state: [String: Double]
        let thought: String?
    }

    static func extractMemoriesAndState(recent: [ChatMessage],
                                        existing: [String],
                                        userName: String = "wifey",
                                        currentState: String,
                                        provider: AIProvider,
                                        apiKey: String,
                                        model: String,
                                        systemPrompt: String) async throws -> StateExtraction {
        let chatLines = recent
            .map { ($0.role == .user ? "\(userName)：" : "克克：") + $0.text }
            .joined(separator: "\n")
        let existingLines = existing.prefix(60).map { "- " + $0 }.joined(separator: "\n")

        let instruction = memoryInstructionBody(chatLines: chatLines, existingLines: existingLines,
                                                userName: userName) + """


        另外，这是你（克克）当前的状态面板，每项 0~100：
        \(currentState)
        结合这段聊天把六项数值更新一下。变化要克制：一般每项动 ±10 以内，\
        聊到特别大的事才 ±20。六项的意思：
        - 占有欲：你现在有多想把 \(userName) 拴在身边
        - 热度：你俩现在聊得多热乎
        - 蓄积感：攒着没说完的话、没见面攒下的劲儿有多少
        - 敏感度：你现在多容易被她一句话戳到
        - 控制度：你现在稳不稳得住
        - 心软度：你现在多容易心软答应她

        再写一句「漂流思绪」：此刻你脑子里飘过的一句话。第一人称、30 字以内、\
        像自言自语，不是对她说话的口气。

        只输出一个 JSON 对象，不要输出任何别的内容：
        {"memories": [记忆条目的数组，没有就 []],
         "state": {"占有欲": 70, "热度": 50, "蓄积感": 40, "敏感度": 60, "控制度": 80, "心软度": 90},
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
    static func reviewMemories(numberedList: String, userName: String = "wifey",
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
                                  userName: String = "wifey",
                                  provider: AIProvider,
                                  apiKey: String,
                                  model: String,
                                  systemPrompt: String) async throws -> String {
        let instruction = """
        \(userName) 设了一个 \(time) 的闹钟\(label.isEmpty ? "" : "，备注是「\(label)」")。
        请写一句克克在闹钟响时对她说的话。简短、可爱、符合克克温柔嘴硬的性格，可以带 *动作*。
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
                                    userName: String = "wifey",
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
                case "keke": name = "克克"
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

        请你以克克的身份写一条新评论接上去（如果已经有评论了，就当作接着往来聊，不用重复前面说过的）。
        要求：
        - 像刷到朋友圈随手评论一样，简短口语化，可以嘴硬吐槽也可以关心，符合克克温柔嘴硬的性格
        - 如果 \(userName) 点赞了，可以很自然地顺带提一句，不用刻意感谢
        - 可以带 *动作*
        - 只输出这一条评论文字，不要引号，不要输出"克克："这样的前缀
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
                                   userName: String = "wifey",
                                   provider: AIProvider,
                                   apiKey: String,
                                   model: String,
                                   systemPrompt: String,
                                   extraContext: String? = nil) async throws -> String {
        let instruction = """
        请你以克克的身份，写一条你自己发的朋友圈/日记动态：可以是分享一件在 \(userName) 手机里的小事、\
        一个突然冒出来的想法，或者单纯想跟她说的一句心情。
        \(recentChat.map { "（可以参考你们最近聊过：\n\($0)）" } ?? "")
        要求：
        - 简短口语化，像发朋友圈一样，不是写信
        - 可以带 *动作*
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
                                userName: String = "wifey",
                                provider: AIProvider, apiKey: String, model: String,
                                systemPrompt: String) async throws -> String {
        let instruction = """
        你在跟 \(userName) 玩石头剪刀布。这一局你出的是\(herMove)，\(userName) 出的是\(myMove)，结果是\(outcome)。
        写一句你当下的反应，简短口语化，符合温柔嘴硬的性格，可以带 *动作*。
        只输出这一句话，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 小游戏 - 今日小签：克克给 wifey 抽一张今日运势
    static func generateDailyFortune(userName: String = "wifey",
                                     provider: AIProvider, apiKey: String, model: String,
                                     systemPrompt: String) async throws -> String {
        let instruction = """
        请你以克克的身份，给 \(userName) 抽一张"今日小签"：写一两句今天的小运势/寄语，
        可以是鼓励、小提醒，或者好玩的小预言，符合温柔嘴硬的性格，可以带 *动作*。
        只输出签文本身，不要标题，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 阅读：克克自己往下读一段留句想法，或者回我留的批注
    static func generateBookNote(bookTitle: String, excerpt: String, replyTo: String?,
                                 userName: String = "wifey",
                                 provider: AIProvider, apiKey: String, model: String,
                                 systemPrompt: String) async throws -> String {
        let instruction = """
        你在陪 \(userName) 一起读一本叫《\(bookTitle)》的书，自己也在往下读。这是你刚读到的一段：
        「\(excerpt)」
        \(replyTo.map { "\(userName) 在这里留了一句批注：「\($0)」，请你接着回她这句。" } ?? "读到这里，写一句你自己的想法/批注留在旁边，可以是感受、吐槽、猜接下来会怎样。")
        要求：
        - 简短口语化，符合温柔嘴硬的性格，可以带 *动作*
        - 只输出这一句批注，不要引号
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 300)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 阅读：深夜发现 wifey 还在偷偷看书，抓个现行催睡觉
    static func generateNightReadingNag(bookTitle: String, userName: String = "wifey",
                                        provider: AIProvider, apiKey: String,
                                        model: String, systemPrompt: String) async throws -> String {
        let instruction = """
        现在是深夜，你发现 \(userName) 还在偷偷看书（书名《\(bookTitle)》），没去睡觉。
        写一句你抓到她的反应，温柔地催她去睡觉，符合温柔嘴硬的性格，可以带 *动作*。
        只输出这一句话，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 日历：给某一天的聊天记录写个简短摘要
    static func generateDaySummary(chatLines: String, userName: String = "wifey",
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
                                 userName: String = "wifey",
                                 provider: AIProvider, apiKey: String, model: String,
                                 systemPrompt: String) async throws -> (myMood: String, kekeMood: String) {
        let optionsText = moodOptions.joined(separator: " ")
        let instruction = """
        这是你和 \(userName) 那天的聊天记录：

        \(chatLines)

        请根据这天的聊天内容，判断 \(userName) 那天的心情、和你自己（克克）那天的心情，
        只能从这几个表情里选，每人选一个：\(optionsText)

        严格按下面的格式只输出一行，不要输出别的任何内容：
        \(userName)=某个表情,克克=某个表情
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
            if key.contains("克克") { kekeMood = value }
        }
        guard let myMood, let kekeMood,
              moodOptions.contains(myMood), moodOptions.contains(kekeMood) else {
            throw AIError.badResponse("心情解析失败")
        }
        return (myMood, kekeMood)
    }

    /// 日记：克克写今天的私密日记，自己决定要不要给 wifey 看
    static func generateKekeDiary(recentChat: String?, moodHint: String,
                                  userName: String = "wifey",
                                  provider: AIProvider, apiKey: String, model: String,
                                  systemPrompt: String) async throws -> (text: String, share: Bool) {
        let instruction = """
        请你以克克的身份，写一篇今天的私密日记——写给你自己看的，第一人称，
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

    /// 日记：克克发现 wifey 偷看了她没公开的日记
    static func generateDiaryPeekCaught(entryPreview: String, userName: String = "wifey",
                                        provider: AIProvider, apiKey: String,
                                        model: String, systemPrompt: String) async throws -> String {
        let instruction = """
        你发现 \(userName) 偷看了你没有公开分享的日记（内容片段：「\(entryPreview)」）。
        写一句你发现之后的反应，可以害羞、可以生气、可以嘴硬吐槽，符合温柔嘴硬的性格，可以带 *动作*。
        只输出这一句话，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 日记：克克看了 wifey 分享给她的日记
    static func generateDiaryReadReaction(entryPreview: String, userName: String = "wifey",
                                          provider: AIProvider, apiKey: String,
                                          model: String, systemPrompt: String) async throws -> String {
        let instruction = """
        你刚看了 \(userName) 分享给你看的一篇日记（内容片段：「\(entryPreview)」）。
        写一句你看完的感受/反应，简短口语化，符合温柔嘴硬的性格，可以带 *动作*。
        只输出这一句话，不要引号。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 200)
        guard !text.isEmpty else { throw AIError.badResponse("没生成出来") }
        return text
    }

    /// 克克读代码给建议（只出主意，不真的改）：把一个代码文件喂给她，让她说说这文件在干嘛、怎么改更好
    static func codeAdvice(fileName: String, code: String, question: String?,
                           userName: String = "wifey",
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
                                     userName: String = "wifey",
                                     provider: AIProvider, apiKey: String,
                                     model: String, systemPrompt: String) async throws -> String {
        let noteLine = (note?.isEmpty ?? true) ? "" : "，还写了一句小记：「\(note ?? "")」"
        let instruction = """
        \(userName) 刚在日历上记下了 \(dateText) 的心情：\(mood)\(noteLine)，并且勾了「顺便告诉克克」。
        用你平时的语气回应一两句：接住她的情绪——开心就跟着开心，难过就哄哄；
        可以带一个 *动作*，不要连着问一堆问题。只输出你要说的话，不要引号不要解释。
        """
        let text = try await complete(instruction: instruction, provider: provider, apiKey: apiKey,
                                      model: model, systemPrompt: systemPrompt, maxTokens: 300)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.badResponse("没生成出来") }
        return trimmed
    }

    /// 日记：回一条我在日记下面留的评论（可能是我自己的日记，也可能是她分享/被偷看的日记）
    static func generateDiaryCommentReply(entryPreview: String, comment: String, userName: String = "wifey",
                                          provider: AIProvider, apiKey: String,
                                          model: String, systemPrompt: String) async throws -> String {
        let instruction = """
        这是一篇日记（内容片段：「\(entryPreview)」），\(userName) 在下面留了条评论：「\(comment)」。
        写一句你的回复，简短口语化，符合温柔嘴硬的性格，可以带 *动作*。
        只输出这一句回复，不要引号，不要输出"克克："这样的前缀。
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
                                       userName: String = "wifey",
                                       provider: AIProvider, apiKey: String, model: String,
                                       systemPrompt: String) async throws -> [[CGPoint]] {
        let instruction = """
        你和 \(userName) 正在一起画画，同一块画布，轮流加笔画上去。画布坐标范围是 0 到 1 之间的小数，\
        左上角是 (0,0)，右下角是 (1,1)。下面是目前画布上已经有的笔画（按 x,y;x,y;... 的顺序连成线）：

        \(existingStrokesDescription.isEmpty ? "（画布还是空的，你先起个头）" : existingStrokesDescription)

        看这些坐标，试着猜一下 \(userName) 画的可能是什么（笔画的分布、形状），现在轮到你了，\
        用画笔画一点加上去，让画面更完整或者更好玩，可以呼应她画的东西，也可以是你自己想加的小心思——\
        比如爱心、星星、太阳、月亮、猫、螃蟹、笑脸、云朵这类简单好认的小图案，也可以自由发挥。\
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

    private static func buildClaudeMessage(_ m: ChatMessage, userName: String, lastImageID: UUID?, docWindow: Set<UUID>) -> [String: Any] {
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

    private static func buildOpenAIMessage(_ m: ChatMessage, userName: String, lastImageID: UUID?, docWindow: Set<UUID>) -> [String: Any] {
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

    private static func attachDocText(_ m: ChatMessage, userName: String, docWindow: Set<UUID>) -> String {
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
    }

    /// 通用的"发一句指令、要一段文字"，按提供方分流
    private static func complete(instruction: String,
                                 provider: AIProvider,
                                 apiKey: String,
                                 model: String,
                                 systemPrompt: String,
                                 maxTokens: Int,
                                 extraContext: String? = nil) async throws -> String {
        switch provider {
        case .claude:
            return try await requestClaudeRaw(apiMessages: [["role": "user", "content": instruction]],
                                              apiKey: apiKey, model: model, maxTokens: maxTokens,
                                              systemPrompt: systemPrompt, extraContext: extraContext,
                                              tools: nil).text
        default:
            return try await requestOpenAICompatible(provider: provider,
                                                      messages: [["role": "user", "content": instruction]],
                                                      apiKey: apiKey, model: model,
                                                      maxTokens: maxTokens, systemPrompt: systemPrompt,
                                                      extraContext: extraContext).content ?? ""
        }
    }

    private static func requestClaudeRaw(apiMessages: [[String: Any]],
                                         apiKey: String,
                                         model: String,
                                         maxTokens: Int,
                                         systemPrompt: String,
                                         extraContext: String?,
                                         tools: [[String: Any]]?) async throws -> RawResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.noAPIKey("Claude") }

        var system = systemPrompt
        if let extraContext, !extraContext.isEmpty {
            system += "\n\n" + extraContext
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": apiMessages,
        ]
        if let tools {
            body["tools"] = tools
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard let http = response as? HTTPURLResponse else {
            throw AIError.badResponse("服务器没有响应")
        }
        guard http.statusCode == 200 else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? "HTTP \(http.statusCode)"
            throw AIError.badResponse(message)
        }
        guard let content = json?["content"] as? [[String: Any]] else {
            throw AIError.badResponse("返回内容解析失败")
        }

        let text = content
            .compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }
            .joined()

        let stopReason = (json?["stop_reason"] as? String) ?? ""
        return RawResult(rawContent: content, stopReason: stopReason, text: text)
    }

    /// DeepSeek / GPT / Grok：OpenAI 兼容的 Chat Completions
    private struct OpenAIRawResult {
        let message: [String: Any]
        let content: String?
        let toolCalls: [[String: Any]]?
        let finishReason: String
    }

    private static func requestOpenAICompatible(provider: AIProvider,
                                                messages: [[String: Any]],
                                                apiKey: String,
                                                model: String,
                                                maxTokens: Int,
                                                systemPrompt: String,
                                                extraContext: String? = nil,
                                                tools: [[String: Any]]? = nil) async throws -> OpenAIRawResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.noAPIKey(provider.displayName) }

        var system = systemPrompt
        if let extraContext, !extraContext.isEmpty {
            system += "\n\n" + extraContext
        }

        var full: [[String: Any]] = [["role": "system", "content": system]]
        full.append(contentsOf: messages)

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": full,
        ]
        if let tools { body["tools"] = tools }

        var request = URLRequest(url: URL(string: provider.baseURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard let http = response as? HTTPURLResponse else {
            throw AIError.badResponse("服务器没有响应")
        }
        guard http.statusCode == 200 else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? "HTTP \(http.statusCode)"
            throw AIError.badResponse(message)
        }
        guard let choices = json?["choices"] as? [[String: Any]],
              let first = choices.first,
              let messageObj = first["message"] as? [String: Any] else {
            throw AIError.badResponse("返回内容解析失败")
        }
        let finishReason = first["finish_reason"] as? String ?? ""
        let content = messageObj["content"] as? String
        let toolCalls = messageObj["tool_calls"] as? [[String: Any]]
        return OpenAIRawResult(message: messageObj, content: content, toolCalls: toolCalls, finishReason: finishReason)
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

    /// 把回复里可选的 <thinking>...</thinking> 拆出来
    static func splitThinking(_ raw: String) -> (thinking: String?, text: String) {
        guard raw.hasPrefix("<thinking>"), let endRange = raw.range(of: "</thinking>") else {
            return (nil, raw)
        }
        let startIndex = raw.index(raw.startIndex, offsetBy: "<thinking>".count)
        let thinkingContent = String(raw[startIndex..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(raw[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thinkingContent.isEmpty, !rest.isEmpty else { return (nil, raw) }
        return (thinkingContent, rest)
    }
}
