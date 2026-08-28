import Foundation
import Combine

@MainActor
final class TypingRhythm: ObservableObject {
    @Published var isComposing = false
    @Published var swallowedWordsCount = 0

    private var composeStartTime: Date?
    private var pauseCount = 0
    private var lastKeystrokeTime: Date?
    private var hadSubstantialText = false
    private let pauseThreshold: TimeInterval = 3.0
    private var pauseTimer: Timer?

    var onSwallowedWords: (() -> Void)?

    func startedTyping() {
        if composeStartTime == nil {
            composeStartTime = Date()
            pauseCount = 0
            isComposing = true
        }
        if let last = lastKeystrokeTime, Date().timeIntervalSince(last) > pauseThreshold {
            pauseCount += 1
        }
        lastKeystrokeTime = Date()
        resetPauseTimer()
    }

    func textChanged(_ text: String) {
        if text.count >= 5 { hadSubstantialText = true }

        if text.isEmpty && hadSubstantialText {
            swallowedWordsCount += 1
            hadSubstantialText = false
            onSwallowedWords?()
        }
        if !text.isEmpty { startedTyping() }
    }

    func messageSent() -> RhythmSnapshot? {
        guard let start = composeStartTime else { return nil }
        let duration = Date().timeIntervalSince(start)
        let snapshot = RhythmSnapshot(
            composeDuration: duration,
            pauseCount: pauseCount,
            hadSwallowedWords: false
        )
        reset()
        return snapshot
    }

    func reset() {
        composeStartTime = nil
        pauseCount = 0
        lastKeystrokeTime = nil
        hadSubstantialText = false
        isComposing = false
        pauseTimer?.invalidate()
    }

    private func resetPauseTimer() {
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isComposing = false
            }
        }
    }

    func contextHint(for snapshot: RhythmSnapshot) -> String? {
        var hints: [String] = []
        if snapshot.composeDuration > 30 {
            let secs = Int(snapshot.composeDuration)
            hints.append("这条消息用户想了\(secs)秒才发出来")
        }
        if snapshot.pauseCount >= 2 {
            hints.append("打字中间犹豫停顿了\(snapshot.pauseCount)次")
        }
        guard !hints.isEmpty else { return nil }
        return "【打字节奏提示：\(hints.joined(separator: "，"))，请温柔一点回应】"
    }

    func swallowedWordsHint() -> String? {
        guard swallowedWordsCount > 0 else { return nil }
        let count = swallowedWordsCount
        swallowedWordsCount = 0
        return "【用户刚才打了字又删掉没发出来（\(count)次），似乎有话想说又犹豫了，可以温柔地主动关心一下】"
    }
}

struct RhythmSnapshot {
    let composeDuration: TimeInterval
    let pauseCount: Int
    let hadSwallowedWords: Bool
}
