import Foundation

/// 一个可以选的音色
struct SpeechVoice: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    /// 一句话说清这是个什么声音，挑的时候用
    var detail: String = ""
}

/// 语音合成的供应商。
///
/// 本来只接了 ElevenLabs。但**它的中文有明显的「翻译腔」**——成语和长句的
/// 重音位置经常不对。对一个说中文的陪伴角色，这是能不能用的问题，
/// 不是好不好听的问题。所以这里开成一层，让用户自己挑。
enum SpeechVendor: String, CaseIterable, Identifiable, Codable {
    case elevenLabs, minimax, doubao

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elevenLabs: return "ElevenLabs"
        case .minimax: return "MiniMax"
        case .doubao: return "豆包 · 火山引擎"
        }
    }

    /// 选的时候该知道的取舍。写得直白点，别让人去查
    var blurb: String {
        switch self {
        case .elevenLabs:
            return "音色库最大、克隆最成熟，但**中文有翻译腔**，成语和长句的重音经常不对"
        case .minimax:
            return "中文自然，价格大约是 ElevenLabs 的一半。情感只能调语速和音高"
        case .doubao:
            return "**中文情感最好**，而且能用一句话描述语气。凭据要填三样，比别家麻烦一点"
        }
    }

    var signupHint: String {
        switch self {
        case .elevenLabs: return "elevenlabs.io"
        case .minimax: return "platform.minimaxi.com（国内）/ platform.minimax.io（海外）"
        case .doubao: return "火山引擎控制台 → 语音技术 → 语音合成"
        }
    }

    // MARK: - 凭据

    /// 一家要填几样东西。ElevenLabs 一个 key 就够，
    /// MiniMax 还要 GroupId，豆包要 AppID + Access Key + Resource ID
    struct Field: Identifiable, Equatable {
        let key: String
        let label: String
        let placeholder: String
        /// 密钥性质的字段在界面上用 SecureField
        var secure: Bool = true
        /// 有合理默认值的字段（比如豆包的 Resource ID）
        var defaultValue: String = ""
        var id: String { key }
    }

    var fields: [Field] {
        switch self {
        case .elevenLabs:
            return [Field(key: "key", label: "API Key", placeholder: "xi-…")]
        case .minimax:
            return [
                Field(key: "key", label: "API Key", placeholder: "eyJ…"),
                Field(key: "group", label: "GroupId", placeholder: "18…", secure: false),
                Field(key: "host", label: "接入点", placeholder: "api.minimaxi.chat",
                      secure: false, defaultValue: "api.minimaxi.chat"),
            ]
        case .doubao:
            return [
                Field(key: "appid", label: "App ID", placeholder: "在控制台应用里找", secure: false),
                Field(key: "key", label: "Access Token", placeholder: "…"),
                Field(key: "resource", label: "Resource ID", placeholder: "seed-tts-2.0",
                      secure: false, defaultValue: "seed-tts-2.0"),
            ]
        }
    }

    // MARK: - 模型

    var models: [(id: String, name: String)] {
        switch self {
        case .elevenLabs:
            return [
                ("eleven_multilingual_v2", "Multilingual v2 · 音质最好"),
                ("eleven_turbo_v2_5", "Turbo v2.5 · 快、便宜一半"),
                ("eleven_flash_v2_5", "Flash v2.5 · 最快最省"),
            ]
        case .minimax:
            return [
                ("speech-02-hd", "speech-02-hd · 音质最好"),
                ("speech-02-turbo", "speech-02-turbo · 快而省"),
            ]
        case .doubao:
            // 豆包的模型档位是跟 Resource ID 绑的，这里不另外给
            return []
        }
    }

    var defaultModel: String {
        switch self {
        case .elevenLabs: return "eleven_multilingual_v2"
        case .minimax: return "speech-02-hd"
        case .doubao: return ""
        }
    }

    // MARK: - 音色

    /// 能不能从服务器拉音色列表。不能的就只能用内置清单或者手填
    var canListVoices: Bool { self == .elevenLabs }

    /// 内置的几个中文音色。**不求全**，只是让人开箱有得选；
    /// 想要别的，界面上可以直接填 id
    var builtInVoices: [SpeechVoice] {
        switch self {
        case .elevenLabs:
            // ElevenLabs 的音色是跟账号走的，这里给不出来——必须去拉列表
            return []
        case .minimax:
            return [
                SpeechVoice(id: "Chinese (Mandarin)_Warm_Bestie", name: "暖姐妹", detail: "温柔、日常"),
                SpeechVoice(id: "Chinese (Mandarin)_Gentleman", name: "绅士", detail: "沉稳男声"),
                SpeechVoice(id: "Chinese (Mandarin)_Lyrical_Voice", name: "抒情", detail: "偏叙述"),
            ]
        case .doubao:
            return [
                SpeechVoice(id: "zh_female_vv_uranus_bigtts", name: "vv", detail: "女声，自然口语"),
                SpeechVoice(id: "zh_male_liufei_uranus_bigtts", name: "柳飞", detail: "男声"),
            ]
        }
    }

    /// 开箱默认音色。
    ///
    /// **ElevenLabs 刻意返回 nil**：它原来写死的是 `Rachel`（一个英文女声），
    /// 结果就算用户填了 key，开箱第一次朗读也是错的。中文音色在 ElevenLabs
    /// 那边是跟账号走的，给不出通用默认值，所以宁可**强制先选一个**
    var defaultVoice: SpeechVoice? { builtInVoices.first }
}
