import Foundation

/// ElevenLabs 语音合成 API。只做两件事：拉可选的声音列表、把一句话合成语音（mp3）。
/// 跟聊天用的 AI Key 是两码事，要去 elevenlabs.io 单独注册拿 Key。
enum ElevenLabsService {

    struct Voice: Identifiable, Equatable {
        let id: String      // voice_id
        let name: String
        /// labels 拼出来的简介（口音/年龄/风格），帮助挑声音
        let detail: String
    }

    /// 没挑过声音时用的默认声音（ElevenLabs 内置的 Rachel）
    static let defaultVoiceID = "21m00Tcm4TlvDq8ikWAM"
    static let defaultVoiceName = "Rachel"

    /// 支持中文的几个合成模型；名字里备注了取舍
    static let models: [(id: String, name: String)] = [
        ("eleven_multilingual_v2", "Multilingual v2 · 音质最好"),
        ("eleven_turbo_v2_5", "Turbo v2.5 · 快、便宜一半"),
        ("eleven_flash_v2_5", "Flash v2.5 · 最快最省"),
    ]
    static let defaultModel = "eleven_multilingual_v2"

    enum ElevenError: LocalizedError {
        case noKey
        case bad(String)

        var errorDescription: String? {
            switch self {
            case .noKey: return "还没填 ElevenLabs 的 API Key"
            case .bad(let message): return message
            }
        }
    }

    /// 账号里能用的声音列表（内置的 + 自己在 ElevenLabs 网站上添加的都在里面）
    static func voices(apiKey: String) async throws -> [Voice] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ElevenError.noKey }

        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!)
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response: response, data: data)

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = json["voices"] as? [[String: Any]] else {
            throw ElevenError.bad("声音列表解析失败")
        }
        return list.compactMap { item in
            guard let id = item["voice_id"] as? String,
                  let name = item["name"] as? String else { return nil }
            let labels = (item["labels"] as? [String: String]) ?? [:]
            let detail = ["gender", "age", "accent", "description", "use_case"]
                .compactMap { labels[$0] }
                .joined(separator: " · ")
            return Voice(id: id, name: name, detail: detail)
        }
    }

    /// 把一句话合成语音，返回 mp3 数据（一次要一整段，不做流式——电话里一句话很短，等得起）
    static func speech(text: String, voiceID: String, modelID: String, apiKey: String) async throws -> Data {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ElevenError.noKey }

        var request = URLRequest(url: URL(string:
            "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)?output_format=mp3_44100_128")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "text": text,
            "model_id": modelID,
            "voice_settings": ["stability": 0.45, "similarity_boost": 0.75],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response: response, data: data)
        guard !data.isEmpty else { throw ElevenError.bad("没合成出声音") }
        return data
    }

    private static func checkStatus(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ElevenError.bad("服务器没有响应")
        }
        guard http.statusCode != 401 else {
            throw ElevenError.bad("ElevenLabs 的 API Key 不对或者失效了")
        }
        guard http.statusCode == 200 else {
            // 报错格式可能是 {"detail":{"message":"…"}} 或 {"detail":"…"}
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = ((json?["detail"] as? [String: Any])?["message"] as? String)
                ?? (json?["detail"] as? String)
                ?? "HTTP \(http.statusCode)"
            throw ElevenError.bad(message)
        }
    }
}
