import SwiftUI

/// 给克克打电话的全屏界面：上面是会动的像素 keke，中间实时字幕，下面闭麦/挂断。
/// 从聊天页顶栏的电话图标进来（fullScreenCover）。
struct CallView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var call: VoiceCallService
    @Environment(\.dismiss) private var dismiss

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        ZStack {
            // 打电话用夜晚配色（跟主页像素猫的夜空一个调），深浅色模式都好看
            LinearGradient(colors: [Color(red: 0.106, green: 0.118, blue: 0.20),
                                    Color(red: 0.078, green: 0.090, blue: 0.165)],
                           startPoint: .top, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                CallKekeAvatar(state: call.state)
                    .frame(width: 148, height: 148)

                Text("克克")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 14)

                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 4)

                if case .failed(let message) = call.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 14)
                }

                if call.state == .ringing, let reason = call.incomingReason {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 10)
                }

                if call.state == .softHangup {
                    Text(L.t("说句话就能继续聊", lang))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 8)
                }

                captions
                    .frame(maxHeight: .infinity)
                    .padding(.top, 18)

                if let note = call.noteText {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 6)
                }

                controls
                    .padding(.bottom, 36)
            }
        }
        .onAppear {
            if call.state == .idle {
                call.startCall(store: store)
            }
        }
        .onChange(of: call.state) { state in
            switch state {
            case .failed:
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if case .failed = call.state {
                        call.hangUp()
                        dismiss()
                    }
                }
            case .idle where call.lines.isEmpty:
                dismiss()
            default:
                break
            }
        }
    }

    private var statusLine: String {
        switch call.state {
        case .idle: return " "
        case .ringing: return L.t("克克来电", lang)
        case .connecting: return L.t("正在接通…", lang)
        case .listening: return call.muted ? L.t("已闭麦", lang) : L.t("在听你说", lang) + " · " + timeText
        case .thinking: return L.t("克克在想…", lang) + " · " + timeText
        case .speaking: return L.t("克克在说话", lang) + " · " + timeText
        case .softHangup: return L.t("克克要挂了", lang) + " · \(call.softHangupCountdown)s"
        case .failed: return L.t("没接通", lang)
        }
    }

    private var timeText: String {
        String(format: "%d:%02d", call.seconds / 60, call.seconds % 60)
    }

    /// 实时字幕：最近几句 + 正在识别的半句
    private var captions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(call.lines.suffix(8)) { line in
                        captionBubble(role: line.role, text: line.text)
                            .id(line.id)
                    }
                    if !call.partialText.isEmpty {
                        captionBubble(role: .user, text: call.partialText + "…")
                            .opacity(0.6)
                            .id("partial")
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: call.lines.count) { _ in
                if let last = call.lines.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: call.partialText) { text in
                if !text.isEmpty {
                    proxy.scrollTo("partial", anchor: .bottom)
                }
            }
        }
    }

    private func captionBubble(role: ChatMessage.Role, text: String) -> some View {
        HStack {
            if role == .user { Spacer(minLength: 40) }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(role == .user ? 0.85 : 1))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(role == .user ? Color.white.opacity(0.10) : Color.white.opacity(0.18))
                )
            if role == .keke { Spacer(minLength: 40) }
        }
    }

    private var controls: some View {
        Group {
            if call.state == .ringing {
                ringingControls
            } else {
                normalControls
            }
        }
    }

    private var ringingControls: some View {
        HStack(spacing: 50) {
            CallControlButton(icon: "phone.down.fill", label: L.t("拒接", lang),
                              background: Color(red: 0.92, green: 0.30, blue: 0.28),
                              foreground: .white, big: true) {
                call.declineCall(store: store)
                dismiss()
            }
            CallControlButton(icon: "phone.fill", label: L.t("接听", lang),
                              background: Color(red: 0.30, green: 0.78, blue: 0.40),
                              foreground: .white, big: true) {
                call.answerCall(store: store)
            }
        }
    }

    private var normalControls: some View {
        HStack(spacing: 30) {
            CallControlButton(icon: call.muted ? "mic.slash.fill" : "mic.fill",
                              label: L.t(call.muted ? "开麦" : "闭麦", lang),
                              background: call.muted ? .white.opacity(0.9) : .white.opacity(0.14),
                              foreground: call.muted ? Color(red: 0.106, green: 0.118, blue: 0.20) : .white) {
                call.toggleMute()
            }
            .disabled(!inCall)
            .opacity(inCall ? 1 : 0.35)

            CallControlButton(icon: "phone.down.fill", label: L.t("挂断", lang),
                              background: Color(red: 0.92, green: 0.30, blue: 0.28),
                              foreground: .white, big: true) {
                call.softHangUp()
                if call.state == .idle { dismiss() }
            }

            switch call.state {
            case .speaking:
                CallControlButton(icon: "hand.raised.fill", label: L.t("我说句话", lang),
                                  background: .white.opacity(0.14), foreground: .white) {
                    call.interrupt()
                }
            case .listening:
                CallControlButton(icon: "checkmark", label: L.t("说完了", lang),
                                  background: .white.opacity(0.14), foreground: .white) {
                    call.finishTurnNow()
                }
                .disabled(call.partialText.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(call.partialText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
            case .softHangup:
                CallControlButton(icon: "xmark", label: L.t("直接挂断", lang),
                                  background: .white.opacity(0.14), foreground: .white) {
                    call.hangUp()
                    dismiss()
                }
            default:
                CallControlButton(icon: "checkmark", label: " ",
                                  background: .clear, foreground: .clear) {}
                    .disabled(true)
            }
        }
    }

    private var inCall: Bool {
        switch call.state {
        case .listening, .thinking, .speaking, .softHangup: return true
        default: return false
        }
    }
}

private struct CallControlButton: View {
    let icon: String
    let label: String
    let background: Color
    let foreground: Color
    var big = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: big ? 24 : 19, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: big ? 68 : 56, height: big ? 68 : 56)
                    .background(Circle().fill(background))
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 76)
    }
}

/// 通话页的迷你像素 keke：跟主页像素猫同一套画法和配色（暖杏色那只），
/// 她说话时嘴一张一合，听你说时耳朵偶尔动一下，想事情时眼睛看向旁边
private struct CallKekeAvatar: View {
    let state: VoiceCallService.CallState

    private static let fur = Color(red: 0.953, green: 0.812, blue: 0.635)
    private static let dark = Color(red: 0.867, green: 0.659, blue: 0.431)
    private static let deep = Color(red: 0.078, green: 0.09, blue: 0.165)
    private static let blush = Color(red: 0.949, green: 0.651, blue: 0.722)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // 说话时往外一圈圈扩的声波
                if state == .speaking {
                    ForEach(0..<2, id: \.self) { index in
                        let phase = (t / 1.6 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(Self.fur.opacity(0.5 * (1 - phase)), lineWidth: 2)
                            .scaleEffect(1 + phase * 0.45)
                    }
                }
                Circle()
                    .fill(Color.white.opacity(0.08))
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                cat(t: t)
                    .padding(24)
            }
        }
    }

    private func cat(t: TimeInterval) -> some View {
        let cycle = 5.0
        let phase = t.truncatingRemainder(dividingBy: cycle)
        let blinking = phase > cycle * 0.88 && phase < cycle * 0.96
        // 说话的嘴：一张一合
        let talkOpen = (1 - cos(t * 2 * .pi / 0.36)) / 2
        // 听的时候耳朵偶尔抖一下
        let earTwitch = state == .listening && phase.truncatingRemainder(dividingBy: 2.4) < 0.25

        return Canvas { context, size in
            // 头部占原设计稿 10 格网格的 (10,20)~(80,110) 区域，这里只画头
            let scale = size.width / 90
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 10, _ h: CGFloat = 10) -> Path {
                Path(CGRect(x: x * scale, y: (y - 20) * scale, width: w * scale, height: h * scale))
            }

            // 耳朵
            let earLift: CGFloat = earTwitch ? -3 : 0
            for (x, y) in [(10.0, 20.0), (70.0, 20.0)] {
                context.fill(rect(x, y + earLift), with: .color(Self.fur))
            }
            for (x, y) in [(10.0, 30.0), (20.0, 30.0), (60.0, 30.0), (70.0, 30.0)] {
                context.fill(rect(x, y), with: .color(Self.fur))
            }
            // 头
            for y in stride(from: 40.0, through: 70.0, by: 10) {
                for x in stride(from: 10.0, through: 70.0, by: 10) {
                    context.fill(rect(x, y), with: .color(Self.fur))
                }
            }
            for y in stride(from: 80.0, through: 100.0, by: 10) {
                for x in stride(from: 0.0, through: 80.0, by: 10) {
                    context.fill(rect(x, y), with: .color(Self.fur))
                }
            }

            // 眼睛：想事情时看向旁边，眨眼时弯弯的
            let eyeShift: CGFloat = state == .thinking ? 3 : 0
            if blinking {
                for cx in [33.0, 61.0] {
                    var path = Path()
                    path.move(to: CGPoint(x: (cx - 4) * scale, y: (66 - 20) * scale))
                    path.addQuadCurve(to: CGPoint(x: (cx + 4) * scale, y: (66 - 20) * scale),
                                      control: CGPoint(x: cx * scale, y: (70 - 20) * scale))
                    context.stroke(path, with: .color(Self.deep),
                                   style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round))
                }
            } else {
                context.fill(rect(29 + eyeShift, 62), with: .color(Self.deep))
                context.fill(rect(57 + eyeShift, 62), with: .color(Self.deep))
                context.fill(rect(31.7 + eyeShift, 63.2, 2.6, 2.6), with: .color(.white.opacity(0.95)))
                context.fill(rect(59.7 + eyeShift, 63.2, 2.6, 2.6), with: .color(.white.opacity(0.95)))
            }

            // 嘴：说话时张合的小椭圆，其他时候是 w 型猫嘴
            if state == .speaking {
                let height = (2 + talkOpen * 5) * scale
                let mouthRect = CGRect(x: 43 * scale, y: (76 - 20) * scale - height / 2,
                                       width: 9 * scale, height: height)
                context.fill(Path(ellipseIn: mouthRect), with: .color(Self.deep))
            } else {
                var path = Path()
                path.move(to: CGPoint(x: 41 * scale, y: (76 - 20) * scale))
                path.addQuadCurve(to: CGPoint(x: 46 * scale, y: (76 - 20) * scale),
                                  control: CGPoint(x: 43.5 * scale, y: (79 - 20) * scale))
                path.addQuadCurve(to: CGPoint(x: 51 * scale, y: (76 - 20) * scale),
                                  control: CGPoint(x: 48.5 * scale, y: (79 - 20) * scale))
                context.stroke(path, with: .color(Self.deep),
                               style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round))
            }

            // 腮红
            context.fill(rect(20, 71, 8, 5), with: .color(Self.blush.opacity(0.75)))
            context.fill(rect(63, 71, 8, 5), with: .color(Self.blush.opacity(0.75)))
        }
    }
}
