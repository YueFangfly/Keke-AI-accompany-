import Foundation

/// 支持的 AI 提供方。每家有自己的 API Key、Base URL、请求格式
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude, deepseek, openai, grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .deepseek: return "DeepSeek"
        case .openai: return "GPT (OpenAI)"
        case .grok: return "Grok (xAI)"
        }
    }

    /// 请求地址；Claude 走自己的 Messages API，其它几家是 OpenAI 兼容的 Chat Completions
    var baseURL: String {
        switch self {
        case .claude: return "https://api.anthropic.com/v1/messages"
        case .deepseek: return "https://api.deepseek.com/chat/completions"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .grok: return "https://api.x.ai/v1/chat/completions"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-…"
        case .deepseek: return "sk-…"
        case .openai: return "sk-…"
        case .grok: return "xai-…"
        }
    }

    var keyURLHint: String {
        switch self {
        case .claude: return "console.anthropic.com"
        case .deepseek: return "platform.deepseek.com"
        case .openai: return "platform.openai.com"
        case .grok: return "console.x.ai"
        }
    }

    /// Claude 用固定的模型选择器；其它家用户自己填模型名（免得列表跟不上更新）
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
        }
    }

    /// 能不能看照片
    var supportsVision: Bool {
        switch self {
        case .claude, .openai, .grok: return true
        case .deepseek: return false
        }
    }

    /// 联网（搜索/打开链接）目前只接了 Claude 官方工具
    var supportsWebTools: Bool { self == .claude }
}
