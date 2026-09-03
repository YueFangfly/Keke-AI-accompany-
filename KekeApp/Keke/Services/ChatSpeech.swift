import Foundation
import AVFoundation

/// 聊天里的朗读。
///
/// ElevenLabs 之前只接在语音通话里——通话是「事件」，朗读是「日常」：
/// 想听 TA 说这一段，但不想开一通电话。
///
/// **按文本缓存音频**：同一段话重复点朗读不该重复合成。合成是按字符收费的，
/// 而重听同一条是很常见的操作。
@MainActor
final class ChatSpeech: NSObject, ObservableObject {
    static let shared = ChatSpeech()

    /// 正在读哪条消息。界面靠它把按钮切成「停止」
    @Published private(set) var speakingID: UUID?
    @Published private(set) var preparing: UUID?

    private var player: AVAudioPlayer?
    /// 文本哈希 → 音频文件。放临时目录，系统清了就重新合成
    private var cache: [String: URL] = [:]

    private override init() { super.init() }

    /// 朗读一条消息；正在读同一条就停下（按钮是个开关）
    func toggle(_ message: ChatMessage, voiceCall: VoiceCallService) async {
        if speakingID == message.id || preparing == message.id { stop(); return }
        stop()

        let text = Self.readable(message.text)
        guard !text.isEmpty else { return }
        let key = voiceCall.elevenKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            ErrorLog.shared.record(source: "朗读", message: "还没填 ElevenLabs 的 Key，去「设置 → 语音」里填一下")
            return
        }

        preparing = message.id
        defer { preparing = nil }

        let cacheKey = Self.cacheKey(text: text, voice: voiceCall.voiceID)
        do {
            let url: URL
            if let cached = cache[cacheKey], FileManager.default.fileExists(atPath: cached.path) {
                url = cached
            } else {
                let data = try await ElevenLabsService.speech(
                    text: text, voiceID: voiceCall.voiceID,
                    modelID: voiceCall.ttsModel, apiKey: key)
                url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tts_\(cacheKey).mp3")
                try data.write(to: url, options: .atomic)
                cache[cacheKey] = url
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            self.player = player
            speakingID = message.id
        } catch {
            ErrorLog.shared.record(source: "朗读", message: error.localizedDescription)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        speakingID = nil
    }

    /// 要读出来的文字。
    ///
    /// 星号动作（`*歪头*`）、Markdown 标记、`<choices>` 块都不该被念出来——
    /// 念「星号歪头星号」很出戏
    static func readable(_ raw: String) -> String {
        var text = raw
        // 整块删掉：念出来只有噪音
        for pattern in [#"<choices>[\s\S]*?</choices>"#,   // 选项块
                        #"```[\s\S]*?```"#,                 // 代码块
                        #"`[^`\n]*`"#,                       // 行内代码
                        #"!?\[[^\]]*\]\([^)]*\)"#] {       // 链接和图片
            text = text.replacingOccurrences(of: pattern, with: " ",
                                             options: .regularExpression)
        }
        // 加粗要先脱壳再删动作。**很**重要 里的 `*很*` 会被下面的动作正则整个吃掉，
        // 顺序反了就变成「重要」——把语气词念没了
        for pattern in [#"\*\*([^*\n]{1,200})\*\*"#, #"__([^_\n]{1,200})__"#] {
            text = text.replacingOccurrences(of: pattern, with: "$1",
                                             options: .regularExpression)
        }
        // *歪头* 这种动作描写整段拿掉，念「星号歪头星号」很出戏
        text = text.replacingOccurrences(of: #"\*[^*\n]{1,40}\*"#, with: " ",
                                         options: .regularExpression)
        // 剩下的 Markdown 标记直接去掉
        text = text.replacingOccurrences(of: "[*_#>]", with: "",
                                         options: .regularExpression)
        // 上面留下的空格会连成一片，压回单个
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ",
                                         options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 缓存键：正文 + 音色。换了音色要重新合成，换了标点也算换了内容
    private static func cacheKey(text: String, voice: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in Array((voice + "\u{0}" + text).utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 36)
    }
}

extension ChatSpeech: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.speakingID = nil }
    }
}
