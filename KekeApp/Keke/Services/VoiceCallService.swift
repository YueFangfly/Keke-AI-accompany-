import Foundation
import AVFoundation
import Speech
import SwiftUI

/// 通话字幕里的一句话
struct CallLine: Identifiable, Equatable {
    let id = UUID()
    let role: ChatMessage.Role
    var text: String
}

/// 给克克打电话：苹果本地语音识别听我说（免费）→ 现有的 AI 管线想回复
/// （带人设/记忆/最近聊天，四家提供方都能用）→ ElevenLabs 合成克克的声音读出来。
/// 不是真的实时语音流（那要接 WebRTC 那一套），是"你一句我一句"的回合制，
/// 说完停顿一下她就接话，体验接近打电话。
@MainActor
final class VoiceCallService: NSObject, ObservableObject {

    enum CallState: Equatable {
        case idle
        case connecting          // 权限 + 音频会话 + 开场白
        case listening           // 在听我说
        case thinking            // 克克在想怎么接
        case speaking            // 克克在说
        case failed(String)      // 起不来（缺 Key / 缺权限 / 音频问题）
    }

    @Published var state: CallState = .idle
    @Published var lines: [CallLine] = []
    /// 正在识别中的半句话（实时字幕）
    @Published var partialText = ""
    @Published var seconds = 0
    @Published var muted = false
    /// 通话中的小提示（合成失败之类的），显示在字幕下面，不打断通话
    @Published var noteText: String?

    // MARK: - ElevenLabs 设置（都存 UserDefaults，跟聊天的 AI Key 分开）

    @Published var elevenKey: String = UserDefaults.standard.string(forKey: "eleven_api_key") ?? "" {
        didSet { UserDefaults.standard.set(elevenKey, forKey: "eleven_api_key") }
    }
    @Published var voiceID: String = UserDefaults.standard.string(forKey: "eleven_voice_id") ?? ElevenLabsService.defaultVoiceID {
        didSet { UserDefaults.standard.set(voiceID, forKey: "eleven_voice_id") }
    }
    @Published var voiceName: String = UserDefaults.standard.string(forKey: "eleven_voice_name") ?? ElevenLabsService.defaultVoiceName {
        didSet { UserDefaults.standard.set(voiceName, forKey: "eleven_voice_name") }
    }
    @Published var ttsModel: String = UserDefaults.standard.string(forKey: "eleven_tts_model") ?? ElevenLabsService.defaultModel {
        didSet { UserDefaults.standard.set(ttsModel, forKey: "eleven_tts_model") }
    }

    /// 设置页拉取的声音列表（只在内存里，下次进设置再拉）
    @Published var availableVoices: [ElevenLabsService.Voice] = []
    @Published var voicesLoading = false
    @Published var voicesError: String?

    var configured: Bool { !elevenKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - 内部状态

    private weak var store: ChatStore?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// 每开一轮识别 +1；旧识别的回调靠它作废，不会串到新一轮里
    private var recognitionGeneration = 0
    private var player: AVAudioPlayer?
    private var callTimer: Timer?
    private var silenceTimer: Timer?
    private var lastPartialAt = Date()
    private var turnTask: Task<Void, Never>?
    /// 通话是否进行中（挂断后所有回调都以它为准直接退出）
    private var active = false
    /// 麦克风回调在音频线程上跑，用这个普通布尔镜像 muted 状态给它看
    private var mutedRaw = false
    /// 识别连续空转重启的次数，防止出错时无限循环
    private var restartCount = 0

    // MARK: - 听语气（B 版：端上粗略声学分析，免费、不用服务器）

    /// 设置页开关：通话时让克克顺带"听出"你说话的语气
    @Published var toneSensingEnabled: Bool =
        (UserDefaults.standard.object(forKey: "call_tone_sensing") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(toneSensingEnabled, forKey: "call_tone_sensing") }
    }
    /// 这一轮说话的声学累计（只在音频线程累加；finalize 前会先 stopRecognition 摘掉 tap，之后主线程读才安全）
    private var toneStart: Date?
    private var energySum: Double = 0
    private var energyPeak: Float = 0
    private var energyFrames: Int = 0
    private var voicedFrames: Int = 0
    /// 跨轮的响度基线（这轮跟平时比是大是小），一通电话内累积
    private var energyBaseline: Double = 0
    /// 刚说完那句的语气提示，requestReply 用完即清
    private var lastToneHint: String?

    // MARK: - 通话入口

    func startCall(store: ChatStore) {
        guard state == .idle || isFailed else { return }
        self.store = store
        lines = []
        partialText = ""
        seconds = 0
        muted = false
        mutedRaw = false
        noteText = nil
        energyBaseline = 0
        lastToneHint = nil
        state = .connecting
        active = true

        Task {
            guard configured else {
                fail("还没填 ElevenLabs 的 API Key，去「设置 → 给克克打电话」填一下")
                return
            }
            guard !store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail("还没填 \(store.provider.displayName) 的 API Key，克克没法想她要说什么")
                return
            }
            guard await requestPermissions() else {
                fail("需要麦克风和语音识别权限才能打电话：去 iPhone 的 设置 → Moonlight 里打开")
                return
            }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .voiceChat,
                                        options: [.defaultToSpeaker, .allowBluetooth])
                try session.setActive(true)
            } catch {
                fail("音频启动失败：\(error.localizedDescription)")
                return
            }
            guard active else { return }
            startCallTimer()
            // 接通的第一句本地随机挑，不用等 AI，接起来就有声音
            await speak(Self.greetings(userName: store.myName).randomElement() ?? "喂？")
        }
    }

    func hangUp() {
        let hadConversation = lines.count > 1
        active = false
        turnTask?.cancel()
        turnTask = nil
        stopRecognition()
        player?.stop()
        player = nil
        callTimer?.invalidate()
        callTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if let store, hadConversation {
            let duration = seconds >= 60 ? "\(seconds / 60)分\(seconds % 60)秒" : "\(seconds)秒"
            let transcript = lines
                .map { ($0.role == .user ? "\(store.myName)：" : "克克：") + $0.text }
                .joined(separator: "\n")
            store.appendCallRecord(text: "📞 刚刚打了 \(duration) 电话", transcript: transcript)
            maybeExtractCallMemories(store: store)
        }
        state = .idle
        partialText = ""
        muted = false
        mutedRaw = false
    }

    /// 她说话说到一半，我插话：停掉播放直接开始听我说
    func interrupt() {
        guard state == .speaking else { return }
        player?.stop()
        player = nil
        startListening()
    }

    /// 不想等静音判定，手动"说完了"
    func finishTurnNow() {
        guard state == .listening else { return }
        finalizeTurn()
    }

    func toggleMute() {
        muted.toggle()
        mutedRaw = muted
        if muted {
            // 闭麦时把没说完的半句丢掉，免得静音判定把它当一轮发出去
            partialText = ""
        }
        lastPartialAt = Date()
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func fail(_ message: String) {
        active = false
        stopRecognition()
        callTimer?.invalidate()
        callTimer = nil
        state = .failed(message)
    }

    // MARK: - 权限

    private func requestPermissions() async -> Bool {
        let mic = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard mic else { return false }
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        return speech == .authorized
    }

    // MARK: - 听我说（苹果本地识别）

    private func startListening() {
        guard active else { return }
        state = .listening
        partialText = ""
        lastPartialAt = Date()
        // 新一轮的声学累计清零
        toneStart = Date()
        energySum = 0
        energyPeak = 0
        energyFrames = 0
        voicedFrames = 0

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else {
            fail("这台手机的语音识别现在不可用（可能是网络或系统设置问题）")
            return
        }

        recognitionGeneration += 1
        let generation = recognitionGeneration

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // 音频线程：闭麦时不喂数据就等于听不见
            guard let self, !self.mutedRaw else { return }
            request.append(buffer)
            // 顺手量一下这一小段的响度（RMS），攒起来给 finalize 判断语气
            if self.toneSensingEnabled, let rms = Self.rms(of: buffer) {
                self.energySum += Double(rms)
                self.energyFrames += 1
                if rms > self.energyPeak { self.energyPeak = rms }
                if rms > 0.02 { self.voicedFrames += 1 }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            fail("麦克风启动失败：\(error.localizedDescription)")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognition(generation: generation, result: result, error: error)
            }
        }
        startSilenceTimer()
    }

    private func handleRecognition(generation: Int, result: SFSpeechRecognitionResult?, error: Error?) {
        guard active, generation == recognitionGeneration, state == .listening else { return }
        if let result {
            let text = result.bestTranscription.formattedString
            if text != partialText {
                partialText = text
                lastPartialAt = Date()
                restartCount = 0
            }
            if result.isFinal {
                finalizeTurn()
            }
            return
        }
        if error != nil {
            // 苹果的识别一段时间会自己断开；有话就当这轮说完了，没话就重新开一轮继续听
            if !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finalizeTurn()
            } else if restartCount < 5 {
                restartCount += 1
                stopRecognition()
                startListening()
            } else {
                fail("语音识别一直起不来，先挂了再试一次吧")
            }
        }
    }

    /// 每 0.3 秒看一眼：说了话、且停顿超过 1.6 秒，就当这句说完了
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            // 先解包成不可变的 self 再进 Task，不然弱引用变量被并发闭包捕获会编译报错
            guard let self else { return }
            Task { @MainActor in
                guard self.active, self.state == .listening, !self.muted else { return }
                let said = !self.partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if said, Date().timeIntervalSince(self.lastPartialAt) > 1.6 {
                    self.finalizeTurn()
                }
            }
        }
    }

    private func stopRecognition() {
        recognitionGeneration += 1
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }

    private func finalizeTurn() {
        let said = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        // stopRecognition 会摘掉 tap，之后音频线程不再动那些累计值，主线程读才安全
        stopRecognition()
        guard active else { return }
        guard !said.isEmpty else {
            startListening()
            return
        }
        lastToneHint = toneSensingEnabled ? computeToneHint(text: said) : nil
        lines.append(CallLine(role: .user, text: said))
        partialText = ""
        noteText = nil
        state = .thinking
        turnTask = Task { await requestReply() }
    }

    /// 把这一轮攒的声学特征粗略翻成一句"语气提示"。手机麦克风的绝对响度不可靠，
    /// 所以响度跟"这通电话里的平时"比，语速/停顿用相对阈值，够给克克一个方向感
    private func computeToneHint(text: String) -> String? {
        guard energyFrames > 8 else { return nil }   // 采样太少不瞎猜
        let avg = energySum / Double(energyFrames)
        let voicedRatio = Double(voicedFrames) / Double(energyFrames)
        let duration = max(0.5, lastPartialAt.timeIntervalSince(toneStart ?? lastPartialAt))
        let charsPerSec = Double(text.count) / duration

        var parts: [String] = []
        if energyBaseline > 0 {
            if avg > energyBaseline * 1.5 { parts.append("声音比平时大、像是激动或急") }
            else if avg < energyBaseline * 0.55 { parts.append("声音比平时轻、像是没什么精神或在小声说") }
        }
        if charsPerSec > 5.2 { parts.append("语速偏快") }
        else if charsPerSec < 2.0 { parts.append("语速偏慢") }
        if voicedRatio < 0.42 { parts.append("中间停顿较多、像在斟酌或提不起劲") }

        // 更新响度基线（指数移动平均）
        energyBaseline = energyBaseline == 0 ? avg : energyBaseline * 0.7 + avg * 0.3

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "，")
    }

    /// 从一小段音频算 RMS 响度
    nonisolated private static func rms(of buffer: AVAudioPCMBuffer) -> Float? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }
        var sum: Float = 0
        for i in 0..<count {
            let sample = channel[i]
            sum += sample * sample
        }
        return (sum / Float(count)).squareRoot()
    }

    // MARK: - 克克想怎么接（复用现有 AI 管线）

    private func requestReply() async {
        guard let store, active else { return }

        // 上下文 = 最近的文字聊天做背景 + 这通电话里已经说过的话
        var messages = Array(store.messages.suffix(12))
        messages.append(contentsOf: lines.map { ChatMessage(role: $0.role, text: $0.text) })

        let lastSaid = lines.last(where: { $0.role == .user })?.text
        var contextParts: [String] = []
        if let memoryBlock = store.memory?.contextBlock(for: lastSaid, userName: store.myName) {
            contextParts.append(memoryBlock)
        }
        contextParts.append(Self.phonePromptBlock(userName: store.myName))
        if let hint = lastToneHint {
            contextParts.append("（\(store.myName) 刚说这句时的语气，手机粗略听出来是：\(hint)。"
                + "这不一定准，你结合她说的内容体会一下她的情绪再回应，但千万别把这些描述词直接念出来。）")
        }
        lastToneHint = nil

        do {
            let raw = try await ClaudeService.send(messages: messages, userName: store.myName,
                                                   provider: store.provider, apiKey: store.apiKey,
                                                   model: store.model,
                                                   systemPrompt: store.effectiveSystemPrompt,
                                                   extraContext: contextParts.joined(separator: "\n\n"),
                                                   webTools: false, toolExecutor: nil)
            guard active, !Task.isCancelled else { return }
            let cleaned = Self.cleanForSpeech(raw)
            store.petStats?.onChatReply()
            await speak(cleaned.isEmpty ? "嗯……我在听。" : cleaned)
        } catch is CancellationError {
            // 挂断了，什么都不用做
        } catch {
            guard active else { return }
            noteText = error.localizedDescription
            await speak("……信号好像不太好，你再说一遍？")
        }
    }

    // MARK: - 克克开口（ElevenLabs 合成）

    private func speak(_ text: String) async {
        guard active else { return }
        lines.append(CallLine(role: .keke, text: text))
        state = .speaking
        do {
            let data = try await ElevenLabsService.speech(text: text, voiceID: voiceID,
                                                          modelID: ttsModel, apiKey: elevenKey)
            guard active, state == .speaking else { return }
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            self.player = player
            player.play()
        } catch {
            // 合成失败就只出字幕，通话继续
            guard active else { return }
            noteText = "语音合成失败：\(error.localizedDescription)"
            startListening()
        }
    }

    // MARK: - 计时

    private func startCallTimer() {
        callTimer?.invalidate()
        callTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.active else { return }
                self.seconds += 1
            }
        }
    }

    // MARK: - 通话记忆

    /// 电话聊得多的话，后台照常提炼一次长期记忆（通话记录本体只留一条带折叠字幕的消息）
    private func maybeExtractCallMemories(store: ChatStore) {
        guard lines.count >= 6, store.memory != nil else { return }
        let callMessages = lines.map { ChatMessage(role: $0.role, text: $0.text) }
        Task { [weak store] in
            guard let store, let memory = store.memory else { return }
            guard let new = try? await ClaudeService.extractMemories(
                recent: callMessages, existing: memory.allTexts, userName: store.myName,
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt
            ), !new.isEmpty else { return }
            for entry in new {
                memory.add(entry.text, importance: entry.importance, valence: entry.valence,
                           arousal: entry.arousal, status: entry.open ? .open : .none)
            }
        }
    }

    // MARK: - 设置页：拉声音列表

    func fetchVoices() {
        guard !voicesLoading else { return }
        voicesLoading = true
        voicesError = nil
        Task {
            do {
                availableVoices = try await ElevenLabsService.voices(apiKey: elevenKey)
                if availableVoices.isEmpty {
                    voicesError = "账号里没有可用的声音"
                }
            } catch {
                voicesError = error.localizedDescription
            }
            voicesLoading = false
        }
    }

    // MARK: - 文案

    /// 接通电话的第一句（本地挑，不等 AI）
    static func greetings(userName: String) -> [String] {
        let hour = Calendar.current.component(.hour, from: Date())
        var lines = [
            "喂？",
            "喂，\(userName)？",
            "嗯，我在。怎么啦？",
            "喂——听得到吗？",
        ]
        if hour >= 23 || hour < 5 {
            lines.append("这么晚打电话……怎么了？")
        }
        return lines
    }

    /// 附加在人设后面的"打电话规则"（不改人设本体，只在通话时生效）
    static func phonePromptBlock(userName: String) -> String {
        """
        （现在你们不是在打字，而是在 App 里语音通话——你说的每个字都会用你的声音念出来给 \(userName) 听。通话时：
        - 像打电话一样说话：口语、自然、简短，一般一两句就好，别一次说一大段
        - 绝对不要用 *动作*、emoji、颜文字、括号旁白或任何排版符号——念出来会很怪
        - 不要写 <thinking>
        - 标点只用逗号、句号、问号，方便合成断句
        - 听不清或没听懂就直接问，可以主动接话让通话自然进行
        - 她说要挂了的话，简短温柔地道别）
        """
    }

    /// 把回复清理成适合念出来的样子：去掉心里话、*动作*、markdown 符号、emoji
    static func cleanForSpeech(_ raw: String) -> String {
        var text = ClaudeService.splitThinking(raw).text
        // *动作* 和 （旁白）
        text = text.replacingOccurrences(of: #"\*[^*\n]*\*"#, with: "", options: .regularExpression)
        // markdown 残留
        for symbol in ["**", "__", "##", "`"] {
            text = text.replacingOccurrences(of: symbol, with: "")
        }
        // emoji 念不出来，直接去掉
        text = String(text.unicodeScalars.filter { scalar in
            !(scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C))
        })
        // 换行念出来是停顿，换成句号
        text = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 播放结束回调（AVAudioPlayerDelegate）

extension VoiceCallService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.active, self.state == .speaking else { return }
            self.player = nil
            self.startListening()
        }
    }
}
