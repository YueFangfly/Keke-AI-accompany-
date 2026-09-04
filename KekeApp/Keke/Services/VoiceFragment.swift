import Foundation
import AVFoundation
import Speech

/// 说一句就记一句。
///
/// 跟 `VoiceCallService` 用的是同一套 Speech 框架，但**刻意不复用那个类**：
/// 通话那边缠着一整个状态机（响铃、软挂断、静音计时、TTS 播放），
/// 为了录一句碎片去动它，坏掉的会是通话。这里只做一件事：把说的话变成字。
///
/// **音频不存**。碎片要的是那句话，不是那段声音；存下来只会占空间。
@MainActor
final class VoiceFragment: NSObject, ObservableObject {
    static let shared = VoiceFragment()

    @Published private(set) var recording = false
    /// 边说边出的字。停下来的时候这就是最终结果
    @Published private(set) var transcript = ""
    @Published var problem: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private override init() { super.init() }

    /// 开始听。`callState` 传通话当前的状态——**正在打电话时不许录**，
    /// 两边抢同一个音频输入，结果是两边都听不清
    func start(callState: VoiceCallService.CallState) async {
        guard !recording else { return }
        guard callState == .idle else {
            problem = "正在通话里，先挂了再记"
            return
        }
        problem = nil
        transcript = ""

        guard await requestPermission() else {
            problem = "没有语音识别或麦克风权限，去「设置 → 隐私」里打开"
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else {
            problem = "语音识别现在用不了，可能是网络或者系统语音包的问题"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                problem = "拿不到麦克风，可能被别的 App 占着"
                teardown()
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    // 识别自己报错：把已经听到的留着，别把用户说过的话吞掉
                    if error != nil, self.transcript.isEmpty {
                        self.problem = "没听清，再说一次试试"
                    }
                }
            }

            engine.prepare()
            try engine.start()
            recording = true
        } catch {
            problem = error.localizedDescription
            ErrorLog.shared.record(source: "语音碎片", message: error.localizedDescription)
            teardown()
        }
    }

    /// 停下来，把听到的那句话交出来（空的就返回 nil）
    @discardableResult
    func stop() -> String? {
        guard recording else { return nil }
        teardown()
        recording = false
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// 不要这一句了
    func cancel() {
        teardown()
        recording = false
        transcript = ""
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 麦克风和语音识别两个权限都要。缺一个就录不成
    private func requestPermission() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
