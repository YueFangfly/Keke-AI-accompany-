import SwiftUI

/// 首页养克克那块：clawd-on-desk 同款像素小螃蟹 Clawd——
/// 陶土橘的方身子、两颗竖条黑豆眼、左右小爪、四条小短腿、脚下一条影子。
/// 戳一下、长按摸头、双击比心，闲置久了会睡着；互动逻辑跟之前的像素猫一样，
/// 只是主角换成了小螃蟹
struct ClawdCharacterView: View {
    @EnvironmentObject var store: ChatStore
    var mood: KekeMood
    /// 每次真的有互动（戳/摸/双击）触发一次，Home 页用它来涨状态条
    var onInteract: (() -> Void)? = nil

    // 互动状态
    @State private var pokeScale: CGFloat = 1.0
    @State private var isPetted = false
    @State private var heartBurst = false
    @State private var isAsleep = false
    @State private var lastInteractionDate = Date()
    @State private var reactionText: String?
    private let stickyReactionsZh = ["嘻嘻", "戳我干嘛~", "在!", "*挥爪*"]

    // 场景画布（单位网格），螃蟹本体 130×83，水平居中
    private let sceneWidth: CGFloat = 170
    private let sceneHeight: CGFloat = 104

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                scene(t: t)
                reactionBubble
                    .offset(x: 58, y: -14)
                petHearts(t: t)
                    .offset(x: 0, y: -26)
                zzz(t: t)
                    .offset(x: 46, y: -8)
            }
        }
        .frame(width: 210, height: 210 * sceneHeight / sceneWidth)
        .task { await sleepWatchLoop() }
        .onChange(of: mood) { newValue in
            wakeUp()
            if newValue == .happy {
                showReaction("*举爪爪*")
            }
        }
        .onTapGesture(count: 2) { handleDoubleTap() }
        .onTapGesture(count: 1) { handleTap() }
        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 24, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { isPetted = pressing }
            if pressing {
                wakeUp()
                onInteract?()
            }
        }, perform: {})
    }

    // MARK: - 画小螃蟹

    private func scene(t: TimeInterval) -> some View {
        let bobY = CGFloat(-2.5 * (1 - cos(t * 2 * .pi / 3.2)))
        // 两只小爪交替轻轻抬；开心的时候一起举起来
        let leftArmDY: CGFloat = heartBurst ? -8 : CGFloat(-2 * (1 - cos(t * 2 * .pi / 2.4)))
        let rightArmDY: CGFloat = heartBurst ? -8 : CGFloat(-2 * (1 - cos((t - 1.2) * 2 * .pi / 2.4)))
        let cycle = 5.0
        let phase = t.truncatingRemainder(dividingBy: cycle)
        let blinking = !isAsleep && !isPetted && phase > cycle * 0.88 && phase < cycle * 0.96
        let breathe = isPetted ? 1 + sin(t * 8) * 0.03 : 1

        return Canvas { context, size in
            let scale = size.width / sceneWidth
            // 螃蟹本体 130 宽，水平居中
            let crabX: CGFloat = (sceneWidth - 130) / 2
            let crabY: CGFloat = 12

            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(CGRect(x: (crabX + x) * scale, y: (crabY + y) * scale,
                            width: w * scale, height: h * scale))
            }
            func smileEye(_ target: GraphicsContext, centerX: CGFloat, y: CGFloat) {
                var path = Path()
                path.move(to: CGPoint(x: (crabX + centerX - 5) * scale, y: (crabY + y) * scale))
                path.addQuadCurve(to: CGPoint(x: (crabX + centerX + 5) * scale, y: (crabY + y) * scale),
                                  control: CGPoint(x: (crabX + centerX) * scale, y: (crabY + y + 5) * scale))
                target.stroke(path, with: .color(Self.inkColor),
                              style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round))
            }

            // 脚下淡淡的影子，给点落地感（在浅色卡片上不要太重）
            context.fill(rect(28, 77, 74, 4), with: .color(Self.inkColor.opacity(0.15)))

            context.drawLayer { layer in
                layer.translateBy(x: 0, y: bobY * scale)

                func fill(_ path: Path, _ color: Color) { layer.fill(path, with: .color(color)) }

                // 左右小爪
                fill(rect(0, 26 + leftArmDY, 16, 16), Self.shellColor)
                fill(rect(114, 26 + rightArmDY, 16, 16), Self.shellColor)
                // 方身子
                fill(rect(16, 0, 98, 56), Self.shellColor)
                // 四条小短腿
                fill(rect(26, 56, 10, 20), Self.shellColor)
                fill(rect(42, 56, 10, 20), Self.shellColor)
                fill(rect(78, 56, 10, 20), Self.shellColor)
                fill(rect(93, 56, 10, 20), Self.shellColor)

                // 眼睛：竖条黑豆眼；眨眼/睡着变一条缝；摸头的时候眯眯眼
                if isAsleep || blinking {
                    fill(rect(33, 27, 13, 3.5), Self.inkColor)
                    fill(rect(84, 27, 13, 3.5), Self.inkColor)
                } else if isPetted {
                    smileEye(layer, centerX: 39.5, y: 26)
                    smileEye(layer, centerX: 90.5, y: 26)
                } else {
                    fill(rect(35, 14, 9, 17), Self.inkColor)
                    fill(rect(86, 14, 9, 17), Self.inkColor)
                }

                // 摸头的时候脸红 + 小嘴
                if isPetted {
                    fill(rect(24, 36, 11, 6), Self.blushColor.opacity(0.9))
                    fill(rect(95, 36, 11, 6), Self.blushColor.opacity(0.9))
                    var mouth = Path()
                    mouth.move(to: CGPoint(x: (crabX + 60) * scale, y: (crabY + 42) * scale))
                    mouth.addQuadCurve(to: CGPoint(x: (crabX + 70) * scale, y: (crabY + 42) * scale),
                                       control: CGPoint(x: (crabX + 65) * scale, y: (crabY + 46) * scale))
                    layer.stroke(mouth, with: .color(Self.inkColor),
                                 style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
                }
            }

            // 名字牌
            let nameFont = Font.system(size: 11 * scale, weight: .regular, design: .serif).italic()
            context.draw(Text("keke").font(nameFont).foregroundColor(Self.shellColor),
                         at: CGPoint(x: sceneWidth / 2 * scale, y: (sceneHeight - 4) * scale))
        }
        .scaleEffect(pokeScale * breathe)
    }

    // MARK: - 反应气泡 / 心心 / zZz

    @ViewBuilder
    private var reactionBubble: some View {
        if let text = reactionText ?? (mood == .thinking ? L.t("……让我想想", store.appLanguage) : nil) {
            Text(text)
                .font(.caption2)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.card.opacity(0.95)))
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func petHearts(t: TimeInterval) -> some View {
        if isPetted {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.9 + Double(i) * 0.6).truncatingRemainder(dividingBy: 1.8)
                    Text("💕")
                        .font(.system(size: 11))
                        .opacity(phase < 1.4 ? (1 - phase / 1.4) : 0)
                        .offset(x: CGFloat(i - 1) * 16, y: -CGFloat(phase * 22))
                }
            }
        }
    }

    @ViewBuilder
    private func zzz(t: TimeInterval) -> some View {
        if isAsleep {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.5 + Double(i) * 0.7).truncatingRemainder(dividingBy: 2.1)
                    Text("z")
                        .font(.system(size: 9 + CGFloat(i) * 3, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .opacity(phase < 1.6 ? (1 - phase / 1.6) : 0)
                        .offset(x: CGFloat(i) * 7, y: -CGFloat(phase * 16))
                }
            }
        }
    }

    // MARK: - 互动处理

    private func handleTap() {
        guard !isPetted else { return }
        wakeUp()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.35)) { pokeScale = 1.08 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { pokeScale = 1.0 }
        }
        let zh = stickyReactionsZh.randomElement() ?? "在!"
        showReaction(L.t(zh, store.appLanguage))
        onInteract?()
    }

    private func handleDoubleTap() {
        wakeUp()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { heartBurst = true }
        showReaction("💕")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { heartBurst = false }
        }
        onInteract?()
    }

    private func showReaction(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { reactionText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeOut(duration: 0.25)) {
                if reactionText == text { reactionText = nil }
            }
        }
    }

    // MARK: - 闲置太久就睡着

    private func wakeUp() {
        lastInteractionDate = Date()
        if isAsleep {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { isAsleep = false }
        }
    }

    private func sleepWatchLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard mood == .idle, !isPetted, !isAsleep else { continue }
            if Date().timeIntervalSince(lastInteractionDate) > 20 {
                withAnimation(.easeInOut(duration: 0.4)) { isAsleep = true }
            }
        }
    }

    // MARK: - 配色（壳色取自 clawd-on-desk 原图）

    private static let shellColor = Color(red: 0.816, green: 0.502, blue: 0.376)
    private static let inkColor = Color(red: 0.08, green: 0.07, blue: 0.06)
    private static let blushColor = Color(red: 0.949, green: 0.651, blue: 0.722)
}
