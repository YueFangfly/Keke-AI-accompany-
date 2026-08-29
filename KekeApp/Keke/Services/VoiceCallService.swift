import Foundation
import AVFoundation
import Speech
import SwiftUI
import UserNotifications

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
        case ringing             // AI 主动来电，等用户接
        case connecting          // 权限 + 音频会话 + 开场白
        case listening           // 在听我说
        case thinking            // 克克在想怎么接
        case speaking            // 克克在说
        case softHangup          // 克克说了再见，15 秒窗口等用户开口
        case failed(String)      // 起不来（缺 Key / 缺权限 / 音频问题）
    }

    let personaId: String

    @Published var state: CallState = .idle
    @Published var lines: [CallLine] = []
    @Published var partialText = ""
    @Published var seconds = 0
    @Published var muted = false
    @Published var noteText: String?
    @Published var incomingReason: String?
    @Published var softHangupCountdown = 0

    // MARK: - ElevenLabs 设置

    /// 存 Keychain，不进 UserDefaults——它是密钥，明文放偏好设置里会被备份和同步带走
    @Published var elevenKey: String = "" {
        didSet { APIKeyStore.setSecret(elevenKey, for: .elevenLabs) }
    }
    @Published var voiceID: String = ElevenLabsService.defaultVoiceID {
        didSet { UserDefaults.standard.set(voiceID, forKey: "\(personaId)_eleven_voice_id") }
    }
    @Published var voiceName: String = ElevenLabsService.defaultVoiceName {
        didSet { UserDefaults.standard.set(voiceName, forKey: "\(personaId)_eleven_voice_name") }
    }
    @Published var ttsModel: String = ElevenLabsService.defaultModel {
        didSet { UserDefaults.standard.set(ttsModel, forKey: "eleven_tts_model") }
    }

    @Published var availableVoices: [ElevenLabsService.Voice] = []
    @Published var voicesLoading = false
    @Published var voicesError: String?

    @Published var aiCallEnabled: Bool = false {
        didSet { UserDefaults.standard.set(aiCallEnabled, forKey: "\(personaId)_call_ai_initiated") }
    }

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
    /// 柔和挂断的倒计时定时器
    private var softHangupTimer: Timer?
    /// 来电铃声
    private var ringtonePlayer: AVAudioPlayer?

    // MARK: - 听语气（B 版：端上粗略声学分析，免费、不用服务器）

    @Published var toneSensingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(toneSensingEnabled, forKey: "\(personaId)_call_tone_sensing") }
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

    // MARK: - Init

    init(personaId: String = "keke") {
        self.personaId = personaId
        super.init()
        let ud = UserDefaults.standard
        // 读的时候会自动把 UserDefaults 里的老明文搬进 Keychain 并删掉原件
        elevenKey = APIKeyStore.secret(.elevenLabs)
        voiceID = ud.string(forKey: "\(personaId)_eleven_voice_id")
            ?? ud.string(forKey: "eleven_voice_id") ?? ElevenLabsService.defaultVoiceID
        voiceName = ud.string(forKey: "\(personaId)_eleven_voice_name")
            ?? ud.string(forKey: "eleven_voice_name") ?? ElevenLabsService.defaultVoiceName
        ttsModel = ud.string(forKey: "eleven_tts_model") ?? ElevenLabsService.defaultModel
        aiCallEnabled = (ud.object(forKey: "\(personaId)_call_ai_initiated") as? Bool)
            ?? (ud.object(forKey: "call_ai_initiated") as? Bool) ?? false
        toneSensingEnabled = (ud.object(forKey: "\(personaId)_call_tone_sensing") as? Bool)
            ?? (ud.object(forKey: "call_tone_sensing") as? Bool) ?? true
    }

    // MARK: - 通话入口

    func startCall(store: ChatStore, greeting: String? = nil) {
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
                fail("还没填 ElevenLabs 的 API Key，去「设置 → 给\(PersonaStore.persona(for: personaId).name)打电话」填一下")
                return
            }
            guard !store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail("还没填 \(store.provider.displayName) 的 API Key，\(PersonaStore.persona(for: personaId).name)没法想TA要说什么")
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
            let firstLine = greeting ?? Self.greetings(userName: store.myName).randomElement() ?? "喂？"
            await speak(firstLine)
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
        ringtonePlayer?.stop()
        ringtonePlayer = nil
        callTimer?.invalidate()
        callTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        softHangupTimer?.invalidate()
        softHangupTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if let store, hadConversation {
            let duration = seconds >= 60 ? "\(seconds / 60)分\(seconds % 60)秒" : "\(seconds)秒"
            let pName = PersonaStore.persona(for: personaId).name
            let transcript = lines
                .map { ($0.role == .user ? "\(store.myName)：" : "\(pName)：") + $0.text }
                .joined(separator: "\n")
            store.appendCallRecord(text: "📞 刚刚打了 \(duration) 电话", transcript: transcript)
            maybeExtractCallMemories(store: store)
        }
        state = .idle
        partialText = ""
        muted = false
        mutedRaw = false
        incomingReason = nil
        softHangupCountdown = 0
    }

    /// 柔和挂断：克克先说再见，进入 15 秒窗口；窗口内用户开口就取消挂断继续聊
    func softHangUp() {
        guard active, state == .listening || state == .thinking || state == .speaking else {
            hangUp()
            return
        }
        player?.stop()
        player = nil
        turnTask?.cancel()
        turnTask = nil
        stopRecognition()
        state = .speaking
        let goodbyes = [
            "那我先挂啦，有事随时找我。",
            "好，先这样，想我的时候再打来。",
            "嗯，那先挂了，我在手机里等你。",
        ]
        let bye = goodbyes.randomElement()!
        Task {
            lines.append(CallLine(role: .keke, text: bye))
            do {
                let data = try await ElevenLabsService.speech(text: bye, voiceID: voiceID,
                                                              modelID: ttsModel, apiKey: elevenKey)
                guard active else { return }
                let p = try AVAudioPlayer(data: data)
                self.player = p
                p.play()
                try? await Task.sleep(nanoseconds: UInt64(p.duration * 1_000_000_000) + 300_000_000)
            } catch {}
            guard active else { return }
            startSoftHangupWindow()
        }
    }

    private func startSoftHangupWindow() {
        state = .softHangup
        softHangupCountdown = 15
        startListening()
        softHangupTimer?.invalidate()
        softHangupTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.active, self.state == .softHangup else {
                    self.softHangupTimer?.invalidate()
                    self.softHangupTimer = nil
                    return
                }
                self.softHangupCountdown -= 1
                if self.softHangupCountdown <= 0 {
                    self.softHangupTimer?.invalidate()
                    self.softHangupTimer = nil
                    self.hangUp()
                }
            }
        }
    }

    /// 柔和挂断窗口内用户开口了：取消挂断，继续通话
    private func cancelSoftHangup() {
        softHangupTimer?.invalidate()
        softHangupTimer = nil
        softHangupCountdown = 0
        noteText = nil
    }

    // MARK: - AI 主动来电

    /// App 回到前台时判断要不要主动发起来电通知
    func maybeInitiateCall(store: ChatStore) async {
        guard aiCallEnabled, configured, !store.apiKey.isEmpty, state == .idle else { return }
        let lastCallKey = "\(store.personaId)_call_last_ai_initiated"
        let lastCall = UserDefaults.standard.double(forKey: lastCallKey)
        guard Date().timeIntervalSince1970 - lastCall > 8 * 3600 else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        guard (9...22).contains(hour) else { return }
        guard let last = store.messages.last else { return }
        let hoursSinceChat = Date().timeIntervalSince(last.date) / 3600
        guard hoursSinceChat > 6 else { return }

        var extraContext = store.memory?.contextBlock(for: nil, userName: store.myName) ?? ""
        if let ks = store.kekeState {
            let drive = ks.dominantDrive()
            extraContext += "\n\(PersonaStore.persona(for: personaId).name)现在最强的驱力是「\(drive.label)」（\(Int(drive.intensity * 100))%）"
            if let obs = ks.dominantObsession {
                extraContext += "\n她心里一直在想：\(obs.text)"
            }
        }
        let reason = try? await ClaudeService.generateCallReason(
            messages: store.messages, userName: store.myName,
            personaName: PersonaStore.persona(for: personaId).name,
            provider: store.provider, apiKey: store.apiKey,
            model: store.model, systemPrompt: store.effectiveSystemPrompt,
            extraContext: extraContext.isEmpty ? nil : extraContext
        )
        guard let reason, !reason.isEmpty else { return }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCallKey)
        incomingReason = reason
        scheduleIncomingCallNotification(reason: reason)
    }

    /// 发一条来电通知
    private func scheduleIncomingCallNotification(reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "📞 \(PersonaStore.persona(for: personaId).name)来电"
        content.body = reason
        content.sound = .default
        content.categoryIdentifier = "KEKE_INCOMING_CALL"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "keke_incoming_call", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// 用户点了通知或在 App 内看到来电：开始振铃
    func showIncomingCall(store: ChatStore, reason: String) {
        guard state == .idle else { return }
        self.store = store
        incomingReason = reason
        state = .ringing
        startRingtone()
        // 30 秒无人接听 → 转语音信箱
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.state == .ringing else { return }
            self.leaveVoicemail(store: store, reason: reason)
        }
    }

    /// 接听来电
    func answerCall(store: ChatStore) {
        guard state == .ringing else { return }
        ringtonePlayer?.stop()
        ringtonePlayer = nil
        startCall(store: store, greeting: incomingReason)
    }

    /// 拒接来电
    func declineCall(store: ChatStore) {
        guard state == .ringing else { return }
        ringtonePlayer?.stop()
        ringtonePlayer = nil
        let reason = incomingReason ?? ""
        incomingReason = nil
        state = .idle
        leaveVoicemail(store: store, reason: reason)
    }

    private func startRingtone() {
        // 用系统音效模拟铃声（重复播放短音效）
        ringtonePlayer?.stop()
        guard let url = Bundle.main.url(forResource: "ringtone", withExtension: "caf")
                ?? Bundle.main.url(forResource: "ringtone", withExtension: "mp3") else { return }
        ringtonePlayer = try? AVAudioPlayer(contentsOf: url)
        ringtonePlayer?.numberOfLoops = -1
        ringtonePlayer?.play()
    }

    // MARK: - 语音信箱

    /// 未接来电 → 克克留一条语音消息在聊天里
    private func leaveVoicemail(store: ChatStore, reason: String) {
        ringtonePlayer?.stop()
        ringtonePlayer = nil
        incomingReason = nil
        state = .idle

        Task {
            let voicemailText = await generateVoicemailText(store: store, reason: reason)
            store.receiveVoicemail(voicemailText)
            if configured {
                if let audioData = try? await ElevenLabsService.speech(
                    text: voicemailText, voiceID: voiceID, modelID: ttsModel, apiKey: elevenKey
                ) {
                    let fileName = "voicemail_\(Int(Date().timeIntervalSince1970)).mp3"
                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent(fileName)
                    try? audioData.write(to: url)
                    store.attachVoicemailAudio(fileName)
                }
            }
        }
    }

    private func generateVoicemailText(store: ChatStore, reason: String) async -> String {
        let instruction = """
        你刚刚给 \(store.myName) 打电话但是她没接。你打电话是因为：\(reason)
        现在给她留一条简短的语音留言（像真的电话留言那样），一两句就好。
        不要用 *动作*、emoji 或任何格式符号。只输出留言的文字内容。
        """
        if let text = try? await ClaudeService.complete(
            instruction: instruction,
            provider: store.provider, apiKey: store.apiKey,
            model: store.model, systemPrompt: store.effectiveSystemPrompt,
            maxTokens: 256, extraContext: nil
        ) {
            return Self.cleanForSpeech(text)
        }
        return "喂，\(store.myName)，我打给你你没接。没什么大事，想你了。回来找我聊聊。"
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
        guard active, generation == recognitionGeneration, state == .listening || state == .softHangup else { return }
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
                guard self.active, (self.state == .listening || self.state == .softHangup), !self.muted else { return }
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
        if state == .softHangup {
            cancelSoftHangup()
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
            let reply = try await ClaudeService.send(messages: messages.compactMap(\.modelPayload), userName: store.myName,
                                                     provider: store.provider, apiKey: store.apiKey,
                                                     model: store.model,
                                                     systemPrompt: store.effectiveSystemPrompt,
                                                     extraContext: contextParts.joined(separator: "\n\n"),
                                                     webTools: false, toolExecutor: nil)
            guard active, !Task.isCancelled else { return }
            // 通话的台词进的是 CallLine 不是 ChatMessage，用量暂时不落库
            let cleaned = Self.cleanForSpeech(reply.text)
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
                personaName: PersonaStore.persona(for: personaId).name,
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
        - 标点只用逗号、句号、问号，方便合成断句
        - 听不清或没听懂就直接问，可以主动接话让通话自然进行
        - 她说要挂了的话，简短温柔地道别）
        """
    }

    /// 把回复清理成适合念出来的样子：去掉 *动作*、markdown 符号、emoji
    static func cleanForSpeech(_ raw: String) -> String {
        var text = raw
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
