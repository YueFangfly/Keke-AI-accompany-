import Foundation

enum SpeechError: LocalizedError {
    case missing(String)
    case bad(String)

    var errorDescription: String? {
        switch self {
        case .missing(let what): return "还没填「\(what)」"
        case .bad(let message): return message
        }
    }
}

/// 每家一个适配器。形状统一：给文本和音色，还回一段能直接播的音频数据。
///
/// 三家的怪癖各不相同，都记在各自的注释里——**这些坑不写下来，
/// 下次换供应商还得再踩一遍**。
enum SpeechEngines {

    static func speech(vendor: SpeechVendor, text: String, voice: String,
                       model: String, credentials: [String: String]) async throws -> Data {
        switch vendor {
        case .elevenLabs: return try await elevenLabs(text, voice, model, credentials)
        case .minimax:    return try await minimax(text, voice, model, credentials)
        case .doubao:     return try await doubao(text, voice, credentials)
        }
    }

    // MARK: - ElevenLabs

    /// 直接复用已经在用的那份实现，一行没改——它是这个项目里唯一
    /// 真跑过的 TTS 代码，没理由为了整齐重写一遍
    private static func elevenLabs(_ text: String, _ voice: String, _ model: String,
                                   _ credentials: [String: String]) async throws -> Data {
        let key = credentials["key"] ?? ""
        guard !key.isEmpty else { throw SpeechError.missing("API Key") }
        guard !voice.isEmpty else { throw SpeechError.missing("音色") }
        return try await ElevenLabsService.speech(text: text, voiceID: voice,
                                                  modelID: model.isEmpty ? ElevenLabsService.defaultModel : model,
                                                  apiKey: key)
    }

    // MARK: - MiniMax

    /// 两个怪癖：
    /// 1. **GroupId 在 query 里**，不在 header 里
    /// 2. **返回的音频是十六进制字符串**，不是 base64、也不是裸字节。
    ///    按 base64 解会得到一坨噪音
    private static func minimax(_ text: String, _ voice: String, _ model: String,
                                _ credentials: [String: String]) async throws -> Data {
        let key = credentials["key"] ?? ""
        let group = credentials["group"] ?? ""
        guard !key.isEmpty else { throw SpeechError.missing("API Key") }
        guard !group.isEmpty else { throw SpeechError.missing("GroupId") }
        guard !voice.isEmpty else { throw SpeechError.missing("音色") }

        let host = (credentials["host"]?.isEmpty == false) ? credentials["host"]! : "api.minimaxi.chat"
        guard let url = URL(string: "https://\(host)/v1/t2a_v2?GroupId=\(group)") else {
            throw SpeechError.bad("接入点地址不对：\(host)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model": model.isEmpty ? "speech-02-hd" : model,
            "stream": false,
            "voice_setting": ["voice_id": voice, "speed": 1.0, "pitch": 0],
            "audio_setting": ["format": "mp3", "sample_rate": 32000],
            "language_boost": "Chinese",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data, vendor: "MiniMax")

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SpeechError.bad("MiniMax 回的不是 JSON")
        }
        // 业务错误是 200 + base_resp.status_code != 0，光看 HTTP 状态码看不出来
        if let base = json["base_resp"] as? [String: Any],
           let code = base["status_code"] as? Int, code != 0 {
            throw SpeechError.bad((base["status_msg"] as? String) ?? "MiniMax 错误码 \(code)")
        }
        guard let payload = json["data"] as? [String: Any],
              let hex = payload["audio"] as? String, !hex.isEmpty else {
            throw SpeechError.bad("MiniMax 没给出音频")
        }
        guard let audio = dataFromHex(hex) else {
            throw SpeechError.bad("MiniMax 的音频解不开")
        }
        return audio
    }

    /// 十六进制字符串 → 字节。奇数长度、非法字符都当坏数据处理
    static func dataFromHex(_ hex: String) -> Data? {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0, !chars.isEmpty else { return nil }
        var out = Data(capacity: chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let high = nibble(chars[index]), let low = nibble(chars[index + 1]) else { return nil }
            out.append(high << 4 | low)
            index += 2
        }
        return out
    }

    private static func nibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30          // 0-9
        case 0x61...0x66: return byte - 0x61 + 10     // a-f
        case 0x41...0x46: return byte - 0x41 + 10     // A-F
        default: return nil
        }
    }

    // MARK: - 豆包 / 火山引擎

    /// 三个怪癖：
    /// 1. 鉴权不是 `Authorization`，是三个自定义头（App ID / Access Key / Resource ID）
    /// 2. `additions` 要求是**一段 JSON 字符串**，不是 JSON 对象
    /// 3. **回的是 NDJSON**：一行一个 `{"code":0,"data":"<base64 片段>"}`，
    ///    要把所有片段按顺序拼起来才是完整音频；最后一行是 `{"code":20000000}`
    private static func doubao(_ text: String, _ voice: String,
                               _ credentials: [String: String]) async throws -> Data {
        let appID = credentials["appid"] ?? ""
        let key = credentials["key"] ?? ""
        guard !appID.isEmpty else { throw SpeechError.missing("App ID") }
        guard !key.isEmpty else { throw SpeechError.missing("Access Token") }
        guard !voice.isEmpty else { throw SpeechError.missing("音色") }
        let resource = (credentials["resource"]?.isEmpty == false)
            ? credentials["resource"]! : "seed-tts-2.0"

        var request = URLRequest(
            url: URL(string: "https://openspeech.bytedance.com/api/v3/tts/unidirectional")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Id")
        request.setValue(key, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resource, forHTTPHeaderField: "X-Api-Resource-Id")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user": ["uid": "keke"],
            "req_params": [
                "text": text,
                "speaker": voice,
                "audio_params": ["format": "mp3", "sample_rate": 24000],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTP(response, data, vendor: "豆包")
        return try mergeNDJSONAudio(data)
    }

    /// 把 NDJSON 里的 base64 片段按顺序拼成一段音频。
    /// 任何一行带非零且非结束码的 `code`，都当成服务器报错
    static func mergeNDJSONAudio(_ raw: Data) throws -> Data {
        var audio = Data()
        for line in String(decoding: raw, as: UTF8.self).split(separator: "\n") {
            // 用 whitespacesAndNewlines 而不是 whitespaces：有的服务器发 CRLF，
            // 只去空格的话行尾会留一个 \r，JSON 就解不了了
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let json = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)))
                    as? [String: Any] else { continue }
            let code = (json["code"] as? Int) ?? 0
            // 20000000 是「说完了」，不是错误
            if code != 0, code != 20_000_000 {
                let message = (json["message"] as? String) ?? "错误码 \(code)"
                throw SpeechError.bad("豆包：\(message)")
            }
            if let chunk = json["data"] as? String, !chunk.isEmpty,
               let bytes = Data(base64Encoded: chunk) {
                audio.append(bytes)
            }
        }
        guard !audio.isEmpty else { throw SpeechError.bad("豆包没给出音频") }
        return audio
    }

    // MARK: - 公共

    private static func checkHTTP(_ response: URLResponse, _ data: Data, vendor: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SpeechError.bad("\(vendor) 没有响应")
        }
        guard http.statusCode != 401, http.statusCode != 403 else {
            throw SpeechError.bad("\(vendor) 的凭据不对或者失效了")
        }
        guard (200...299).contains(http.statusCode) else {
            // 各家报错格式不一样，尽量捞一句人话出来，捞不到就给状态码
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (json?["message"] as? String)
                ?? ((json?["base_resp"] as? [String: Any])?["status_msg"] as? String)
                ?? (json?["detail"] as? String)
                ?? "HTTP \(http.statusCode)"
            throw SpeechError.bad("\(vendor)：\(message)")
        }
    }
}
