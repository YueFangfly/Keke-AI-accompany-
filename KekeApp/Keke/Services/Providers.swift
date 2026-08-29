import Foundation

/// 支持的 AI 提供方。每家有自己的 API Key、Base URL、请求格式
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude, deepseek, openai, grok, gemini, kimi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .deepseek: return "DeepSeek"
        case .openai: return "GPT (OpenAI)"
        case .grok: return "Grok (xAI)"
        case .gemini: return "Gemini (Google)"
        case .kimi: return "Kimi (Moonshot)"
        }
    }

    var baseURL: String {
        switch self {
        case .claude: return "https://api.anthropic.com/v1/messages"
        case .deepseek: return "https://api.deepseek.com/chat/completions"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .grok: return "https://api.x.ai/v1/chat/completions"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .kimi: return "https://api.moonshot.cn/v1/chat/completions"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-…"
        case .deepseek: return "sk-…"
        case .openai: return "sk-…"
        case .grok: return "xai-…"
        case .gemini: return "AIza…"
        case .kimi: return "sk-…"
        }
    }

    var keyURLHint: String {
        switch self {
        case .claude: return "console.anthropic.com"
        case .deepseek: return "platform.deepseek.com"
        case .openai: return "platform.openai.com"
        case .grok: return "console.x.ai"
        case .gemini: return "aistudio.google.com"
        case .kimi: return "platform.moonshot.cn"
        }
    }

    var curatedModels: [(id: String, name: String)]? {
        switch self {
        case .claude:
            return [
                ("claude-opus-4-8", "Opus 4.8 · 最聪明"),
                ("claude-sonnet-5", "Sonnet 5 · 聪明又均衡"),
                ("claude-haiku-4-5", "Haiku 4.5 · 快而省"),
            ]
        default:
            return nil
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-opus-4-8"
        case .deepseek: return "deepseek-chat"
        case .openai: return "gpt-4o"
        case .grok: return "grok-4"
        case .gemini: return "gemini-2.5-flash"
        case .kimi: return "moonshot-v1-8k"
        }
    }

    var supportsVision: Bool {
        switch self {
        case .claude, .openai, .grok, .gemini: return true
        case .deepseek, .kimi: return false
        }
    }

    var supportsWebTools: Bool { self == .claude }

    var supportsFunctionCalling: Bool {
        switch self {
        case .claude, .openai, .grok, .gemini, .deepseek: return true
        case .kimi: return true
        }
    }

    var isClaude: Bool { self == .claude }
}

// MARK: - 模型能力

/// 同一家的不同模型能力不一样，所以这些要按**模型 id**判断，不能只看提供方。
///
/// 主要是为了 Claude 这几年的一个变化：Opus 4.7 之后的模型**移除了采样参数**，
/// temperature / top_p 传过去直接 400。替代品是 `output_config.effort`
/// （生成投入档位）和自适应思考。
///
/// 只对内置的 Claude 生效。自定义供应商走的是 OpenAI 兼容格式，
/// 中转站自己会翻译，该发的还是照发。
enum ModelCapability {

    /// 采样参数被移除的那一批（传了会 400）
    private static let noSampling = [
        "claude-fable-5", "claude-mythos-5",
        "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7",
        "claude-sonnet-5",
    ]

    /// 支持自适应思考 + effort 档位的那一批
    private static let adaptiveThinking = noSampling + ["claude-opus-4-6", "claude-sonnet-4-6"]

    private static func matches(_ model: String, _ family: [String]) -> Bool {
        let id = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return family.contains { id.hasPrefix($0) }
    }

    /// 能不能传 temperature / top_p
    static func supportsSampling(provider: AIProvider, model: String) -> Bool {
        guard provider.isClaude else { return true }
        return !matches(model, noSampling)
    }

    /// 能不能用生成投入档位（output_config.effort）
    static func supportsEffort(provider: AIProvider, model: String) -> Bool {
        guard provider.isClaude else { return false }
        return matches(model, adaptiveThinking)
    }

    /// 能不能开自适应思考（thinking: {type: "adaptive"}）。
    /// 更老的模型要用 budget_tokens 那套旧写法，形状不一样，这里不支持
    static func supportsThinking(provider: AIProvider, model: String) -> Bool {
        supportsEffort(provider: provider, model: model)
    }
}

/// 生成投入档位。档位越高想得越久、花得越多，也越聪明
enum ReasoningEffort: String, CaseIterable, Identifiable, Codable {
    case low, medium, high, xhigh, max

    var id: String { rawValue }

    /// 不传的话 API 默认是 high
    static let apiDefault = ReasoningEffort.high

    var displayName: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        case .xhigh: return "很高"
        case .max: return "最高"
        }
    }
}

// MARK: - Custom Provider

struct CustomAIProvider: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var baseURL: String
    var defaultModel: String
    var keyPlaceholder: String
    var supportsVision: Bool
    var supportsFunctionCalling: Bool

    init(name: String, baseURL: String, defaultModel: String = "",
         keyPlaceholder: String = "sk-…", supportsVision: Bool = false,
         supportsFunctionCalling: Bool = true) {
        self.id = "custom_\(UUID().uuidString.prefix(8))"
        self.name = name
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.keyPlaceholder = keyPlaceholder
        self.supportsVision = supportsVision
        self.supportsFunctionCalling = supportsFunctionCalling
    }
}

// MARK: - Unified Provider Wrapper

enum UnifiedProvider: Equatable, Codable {
    case builtIn(AIProvider)
    case custom(String)

    var id: String {
        switch self {
        case .builtIn(let p): return p.rawValue
        case .custom(let id): return id
        }
    }

    var isClaude: Bool {
        if case .builtIn(.claude) = self { return true }
        return false
    }

    var isBuiltIn: Bool {
        if case .builtIn = self { return true }
        return false
    }

    static func == (lhs: UnifiedProvider, rhs: UnifiedProvider) -> Bool {
        lhs.id == rhs.id
    }

    enum CodingKeys: String, CodingKey { case type, value }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .builtIn(let p):
            try c.encode("builtIn", forKey: .type)
            try c.encode(p.rawValue, forKey: .value)
        case .custom(let id):
            try c.encode("custom", forKey: .type)
            try c.encode(id, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let value = try c.decode(String.self, forKey: .value)
        if type == "builtIn", let p = AIProvider(rawValue: value) {
            self = .builtIn(p)
        } else {
            self = .custom(value)
        }
    }
}

// MARK: - Custom Provider Store

@MainActor
final class CustomProviderStore: ObservableObject {
    @Published var providers: [CustomAIProvider] = []

    private let saveKey = "custom_ai_providers"

    init() {
        load()
    }

    func add(_ provider: CustomAIProvider) {
        providers.append(provider)
        save()
    }

    func update(_ provider: CustomAIProvider) {
        if let i = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[i] = provider
            save()
        }
    }

    func remove(id: String) {
        providers.removeAll { $0.id == id }
        save()
    }

    func provider(for id: String) -> CustomAIProvider? {
        providers.first(where: { $0.id == id })
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([CustomAIProvider].self, from: data) else { return }
        providers = decoded
    }
}
