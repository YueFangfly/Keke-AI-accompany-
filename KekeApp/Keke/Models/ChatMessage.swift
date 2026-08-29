import Foundation

struct ChoiceOption: Codable, Equatable, Identifiable {
    var id: String { label }
    let label: String
}

/// 一次回复烧掉的 token。分四份记是因为它们单价不一样：
/// 命中缓存的输入最便宜，写缓存的比普通输入贵一点，输出最贵。
///
/// 各家 API 的口径不统一（Claude 的 input_tokens 不含缓存，OpenAI 的 prompt_tokens 含缓存），
/// 统一在 ClaudeService 解析的时候抹平，存进来的一律是"四份互不重叠"，直接相加就是总数。
struct TokenUsage: Codable, Equatable {
    /// 普通输入（不含缓存那部分）
    var input: Int
    /// 输出
    var output: Int
    /// 命中缓存的输入
    var cacheRead: Int
    /// 写进缓存的输入
    var cacheWrite: Int

    static let zero = TokenUsage(input: 0, output: 0, cacheRead: 0, cacheWrite: 0)

    var total: Int { input + output + cacheRead + cacheWrite }
    var isEmpty: Bool { total == 0 }

    /// 一次回复可能发好几轮请求（每次工具调用都要再问一遍模型），逐轮累加。
    /// 不用取最大值——这里是非流式，每轮都是一个完整独立的响应
    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(input: lhs.input + rhs.input,
                   output: lhs.output + rhs.output,
                   cacheRead: lhs.cacheRead + rhs.cacheRead,
                   cacheWrite: lhs.cacheWrite + rhs.cacheWrite)
    }

    static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }

    init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        // 有的中转站会回负数或者缺字段，兜一下底，免得统计页出现负的 token
        self.input = max(0, input)
        self.output = max(0, output)
        self.cacheRead = max(0, cacheRead)
        self.cacheWrite = max(0, cacheWrite)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
        let output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
        let cacheRead = try c.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
        let cacheWrite = try c.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
        // 走上面那个 init，负数一样会被夹回 0
        self.init(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite)
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case keke
    }

    var id: UUID
    let role: Role
    var text: String
    let date: Date
    var isFavorite: Bool
    /// 附件图片（attachments 目录里的文件名）
    var imagePath: String?
    /// 附件文档名
    var docName: String?
    /// 从文档里提取的文字（发给克克用）
    var docText: String?
    /// 通话记录的完整字幕，默认折叠。
    /// 字段名是历史原因（以前装的是「心里话」，那个功能已经去掉），存的键名保持不变
    var thinking: String?
    /// 本地识图（Vision 框架，不花钱）算出来的大致内容，缓存起来避免重复算。
    /// 只在当前用的模型不支持看图（比如 DeepSeek）时才会用到
    var localImageCaption: String?
    /// 可点击的选项按钮（AI 弹出让用户选择）
    var choices: [ChoiceOption]?
    var multiSelect: Bool?
    /// 关联的音频 ID（AI 调用播放工具时附带）
    var audioTrackId: String?

    // MARK: - 生成信息（只有 AI 回复才有，用户消息一律 nil）

    /// 这次回复烧的 token
    var usage: TokenUsage?
    /// 从发出请求到拿到完整回复花了多少毫秒（含工具调用的来回）
    var durationMs: Int?
    /// 是哪个模型说的。换过模型之后回看聊天记录，能知道当时用的是谁
    var model: String?
    /// 哪家提供方（AIProvider 的 rawValue；自定义供应商存 "custom"）
    var providerId: String?

    /// 重新生成会产生同一句话的多个版本：它们共享一个 groupId，version 从 0 往上递增。
    /// 没重新生成过的消息两个都是 nil——绝大多数消息都是这种，所以不写进文件里
    var groupId: UUID?
    var version: Int?

    /// 译文缓存。按条存，翻译过一次就不用再花钱翻第二次
    var translation: String?

    /// 模型的思考过程（Claude 开了自适应思考才有）。
    /// 跟上面的 thinking 是两回事：那个装通话转写，这个是 API 真正返回的 thinking 块
    var reasoning: String?

    /// 版本序号，没重新生成过就算第 0 版
    var versionIndex: Int { version ?? 0 }

    init(role: Role, text: String, date: Date = Date(), isFavorite: Bool = false,
         imagePath: String? = nil, docName: String? = nil, docText: String? = nil,
         thinking: String? = nil, choices: [ChoiceOption]? = nil, multiSelect: Bool? = nil,
         audioTrackId: String? = nil,
         usage: TokenUsage? = nil, durationMs: Int? = nil,
         model: String? = nil, providerId: String? = nil,
         groupId: UUID? = nil, version: Int? = nil, translation: String? = nil,
         reasoning: String? = nil) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.date = date
        self.isFavorite = isFavorite
        self.imagePath = imagePath
        self.docName = docName
        self.docText = docText
        self.thinking = thinking
        self.choices = choices
        self.multiSelect = multiSelect
        self.audioTrackId = audioTrackId
        self.usage = usage
        self.durationMs = durationMs
        self.model = model
        self.providerId = providerId
        self.groupId = groupId
        self.version = version
        self.translation = translation
        self.reasoning = reasoning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        isFavorite = try c.decode(Bool.self, forKey: .isFavorite)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        docName = try c.decodeIfPresent(String.self, forKey: .docName)
        docText = try c.decodeIfPresent(String.self, forKey: .docText)
        thinking = try c.decodeIfPresent(String.self, forKey: .thinking)
        localImageCaption = try c.decodeIfPresent(String.self, forKey: .localImageCaption)
        choices = try c.decodeIfPresent([ChoiceOption].self, forKey: .choices)
        multiSelect = try c.decodeIfPresent(Bool.self, forKey: .multiSelect)
        audioTrackId = try c.decodeIfPresent(String.self, forKey: .audioTrackId)
        // 下面这些是后加的字段，老的聊天记录里没有，一律 decodeIfPresent
        usage = try c.decodeIfPresent(TokenUsage.self, forKey: .usage)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        providerId = try c.decodeIfPresent(String.self, forKey: .providerId)
        groupId = try c.decodeIfPresent(UUID.self, forKey: .groupId)
        version = try c.decodeIfPresent(Int.self, forKey: .version)
        translation = try c.decodeIfPresent(String.self, forKey: .translation)
        reasoning = try c.decodeIfPresent(String.self, forKey: .reasoning)
    }
}
