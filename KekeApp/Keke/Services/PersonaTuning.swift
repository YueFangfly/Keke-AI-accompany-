import Foundation

// 人设调教的四件套：按深度注入、正则处理、预设开场、世界书。
// 都是**按角色分开存**的——一个角色的调教规则不该影响另一个。

/// 提示词往哪儿插
enum InjectionPosition: String, Codable, CaseIterable, Identifiable {
    /// 历史最前面
    case start
    /// 历史最后面（紧挨着最新那条）
    case end
    /// 从最新消息往前数第 N 条**之前**
    case atDepth

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .start: return "开头"
        case .end: return "结尾"
        case .atDepth: return "指定深度"
        }
    }
}

/// 按深度注入的一段提示词。
///
/// 为什么需要它：长对话里 system prompt 离最新消息越来越远，注意力被稀释，
/// 人设就飘了。往最近几条里插一句，比一直往 system prompt 后面加有效得多。
struct PromptInjection: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var text = ""
    var position: InjectionPosition = .atDepth
    /// `atDepth` 时用：从最新消息往前数第几条
    var depth = 4
    /// 以用户身份注入还是以角色身份注入
    var asUser = true
}

/// 正则处理规则。
///
/// `visualOnly` 是关键：想把模型输出里的某些标记藏起来只给自己看，
/// 又不想改真正进历史的内容——这两件事必须分开。
struct RegexRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var name = ""
    var pattern = ""
    var replacement = ""
    /// 作用在用户发出的内容上
    var onInput = false
    /// 作用在模型回复上
    var onOutput = true
    /// **只改显示，不改发给模型的内容**
    var visualOnly = true
}

/// 预设开场对话：用来给人设定调，不显示在聊天里，只发给模型
struct PresetMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var isUser = true
    var text = ""
}

/// 世界书条目：关键词命中才注入的设定。
///
/// 比「把所有设定塞进 system prompt」省 token 得多——
/// 一百条设定里这轮只可能用上两三条。
struct WorldBookEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var enabled = true
    var name = ""
    /// 命中任意一个就注入
    var keywords: [String] = []
    var content = ""
    /// 常驻：不看关键词，每轮都注入
    var constantActive = false
    /// 越大越靠前
    var priority = 0
    /// 往前扫几条消息找关键词
    var scanDepth = 6
    var caseSensitive = false
}

/// 一个角色的全部调教设置
struct PersonaTuning: Codable, Equatable {
    var injections: [PromptInjection] = []
    var regexRules: [RegexRule] = []
    var presetMessages: [PresetMessage] = []
    var worldBook: [WorldBookEntry] = []
    /// 每次最多发几条历史。0 = 不限制（交给上下文压缩管）
    var contextMessageSize = 0
    /// 在用户消息后面自动附上当前时间
    var appendCurrentTime = false

    static func load(_ personaId: String) -> PersonaTuning {
        guard let data = UserDefaults.standard.data(forKey: key(personaId)),
              let value = try? JSONDecoder().decode(PersonaTuning.self, from: data) else {
            return PersonaTuning()
        }
        return value
    }

    func save(_ personaId: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(personaId))
    }

    private static func key(_ personaId: String) -> String { "\(personaId)_tuning" }

    var isEmpty: Bool {
        injections.isEmpty && regexRules.isEmpty && presetMessages.isEmpty
            && worldBook.isEmpty && contextMessageSize == 0 && !appendCurrentTime
    }
}

/// 把调教设置真正作用到内容上。
///
/// 全是**纯函数**：输入什么出什么完全确定，没有副作用。
/// 这样这套逻辑能脱离 App 单独验证——它改的是发给模型的东西，错了不好发现。
enum PersonaTuningEngine {

    // MARK: - 提示词变量

    /// `{{user}}` `{{char}}` `{{time}}` `{{date}}` 这几个。
    /// 认不出来的变量**原样留着**，不要吞掉——用户写错了得看得见
    static func expand(_ text: String, userName: String, personaName: String,
                       now: Date = Date()) -> String {
        guard text.contains("{{") else { return text }
        let time = DateFormatter()
        time.locale = Locale(identifier: "zh_CN")
        time.dateFormat = "HH:mm"
        let date = DateFormatter()
        date.locale = Locale(identifier: "zh_CN")
        date.dateFormat = "yyyy-MM-dd EEEE"

        var out = text
        for (name, value) in [("user", userName), ("char", personaName),
                              ("time", time.string(from: now)), ("date", date.string(from: now))] {
            // 兼容 {{user}} 和 {{ user }} 两种写法
            out = out.replacingOccurrences(of: "{{\(name)}}", with: value)
            out = out.replacingOccurrences(of: "{{ \(name) }}", with: value)
        }
        return out
    }

    // MARK: - 正则

    /// 应用一批规则。`visual` 决定这次是"给界面看"还是"给模型看"：
    /// **给模型看的那次会跳过 visualOnly 的规则**——这正是 visualOnly 的意义
    static func applyRegex(_ text: String, rules: [RegexRule],
                           isUser: Bool, visual: Bool) -> String {
        var out = text
        for rule in rules where rule.enabled && !rule.pattern.isEmpty {
            guard isUser ? rule.onInput : rule.onOutput else { continue }
            // 给模型的那一遍跳过只影响显示的规则
            if !visual && rule.visualOnly { continue }
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range,
                                                 withTemplate: rule.replacement)
        }
        return out
    }

    // MARK: - 世界书

    /// 挑出这轮该注入的条目，拼成一段。没有命中的返回 nil。
    ///
    /// `recent` 是最近的消息正文（新的在后）。常驻条目不看关键词。
    static func worldBookBlock(_ entries: [WorldBookEntry], recent: [String]) -> String? {
        var hits: [WorldBookEntry] = []
        for entry in entries where entry.enabled && !entry.content.isEmpty {
            if entry.constantActive { hits.append(entry); continue }
            let depth = max(1, entry.scanDepth)
            let window = recent.suffix(depth).joined(separator: "\n")
            let haystack = entry.caseSensitive ? window : window.lowercased()
            let matched = entry.keywords.contains { keyword in
                let needle = keyword.trimmingCharacters(in: .whitespaces)
                guard !needle.isEmpty else { return false }
                return haystack.contains(entry.caseSensitive ? needle : needle.lowercased())
            }
            if matched { hits.append(entry) }
        }
        guard !hits.isEmpty else { return nil }
        // 优先级高的在前；同优先级按名字排，保证每次顺序一样（顺序一变就影响缓存）
        hits.sort { ($0.priority, $1.name) > ($1.priority, $0.name) }
        let body = hits.map { entry -> String in
            let title = entry.name.trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? entry.content : "【\(title)】\(entry.content)"
        }.joined(separator: "\n")
        return "以下是这次可能用得上的设定：\n" + body
    }

    // MARK: - 注入与预设

    /// 把注入和预设开场拼进要发的历史里。
    ///
    /// 插完会**合并相邻的同角色消息**——各家 API 对连续同角色消息的容忍度不一样，
    /// 合并之后无论哪家都是合法的一问一答。
    static func assemble(_ payloads: [ChatMessage.Payload],
                         tuning: PersonaTuning,
                         userName: String, personaName: String,
                         now: Date = Date()) -> [ChatMessage.Payload] {
        var result = payloads

        // 1. 历史条数上限（0 = 不限，交给上下文压缩管）
        if tuning.contextMessageSize > 0, result.count > tuning.contextMessageSize {
            result = Array(result.suffix(tuning.contextMessageSize))
        }

        // 2. 用户消息后附时间
        if tuning.appendCurrentTime, let last = result.indices.last, result[last].role == .user {
            let stamp = expand("（现在是 {{time}}）", userName: userName,
                               personaName: personaName, now: now)
            result[last] = rewrite(result[last], text: result[last].text + "\n" + stamp)
        }

        // 3. 注入。先按深度插，depth 大的先插——不然前面插进去的会把后面的深度算错
        let active = tuning.injections.filter { $0.enabled && !$0.text.isEmpty }
        for injection in active.sorted(by: { $0.depth > $1.depth }) {
            let text = expand(injection.text, userName: userName,
                              personaName: personaName, now: now)
            let payload = make(text: text, asUser: injection.asUser)
            switch injection.position {
            case .start:
                result.insert(payload, at: 0)
            case .end:
                result.append(payload)
            case .atDepth:
                // depth 从最新往前数：depth=1 表示插在最后一条之前
                let index = max(0, result.count - max(1, injection.depth))
                result.insert(payload, at: index)
            }
        }

        // 4. 预设开场排在最前面：它是给人设定调的，得在真实对话之前
        let presets = tuning.presetMessages.filter { $0.enabled && !$0.text.isEmpty }
        for preset in presets.reversed() {
            let text = expand(preset.text, userName: userName, personaName: personaName, now: now)
            result.insert(make(text: text, asUser: preset.isUser), at: 0)
        }

        return coalesce(result)
    }

    /// 合并相邻的同角色消息。Claude 对连续同角色的容忍度各版本不一，
    /// 有的中转站更严——统一合并掉，谁都不会拒
    static func coalesce(_ payloads: [ChatMessage.Payload]) -> [ChatMessage.Payload] {
        var out: [ChatMessage.Payload] = []
        for payload in payloads {
            guard let last = out.last, last.role == payload.role,
                  // 带图片/文档的不合并：那些字段合不了，硬合会把附件弄丢
                  last.imagePath == nil, last.docName == nil,
                  payload.imagePath == nil, payload.docName == nil else {
                out.append(payload); continue
            }
            out[out.count - 1] = rewrite(last, text: last.text + "\n\n" + payload.text)
        }
        return out
    }

    private static func make(text: String, asUser: Bool) -> ChatMessage.Payload {
        ChatMessage.Payload(role: asUser ? .user : .keke, id: UUID(), text: text,
                            imagePath: nil, docName: nil, docText: nil)
    }

    private static func rewrite(_ payload: ChatMessage.Payload, text: String) -> ChatMessage.Payload {
        ChatMessage.Payload(role: payload.role, id: payload.id, text: text,
                            imagePath: payload.imagePath, docName: payload.docName,
                            docText: payload.docText)
    }
}
