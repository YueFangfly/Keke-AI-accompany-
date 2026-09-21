import SwiftUI

/// 首页互动角色：Q 版小章鱼 Hubby
/// 圆圆的大头 + 八条短触手，深蓝紫配色，月牙标记，会根据心情变化
struct OctoCharacterView: View {
    @EnvironmentObject var store: ChatStore
    var mood: KekeMood
    var onInteract: (() -> Void)? = nil

    @State private var pokeScale: CGFloat = 1.0
    @State private var isPetted = false
    @State private var heartBurst = false
    @State private var isAsleep = false
    @State private var lastInteractionDate = Date()
    @State private var reactionText: String?
    @State private var isJealous = false

    private let stickyReactionsZh = ["嘿嘿", "戳我干嘛~", "在!", "wifey ☽"]

    private let sceneWidth: CGFloat = 170
    private let sceneHeight: CGFloat = 120

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                scene(t: t)
                reactionBubble
                    .offset(x: 58, y: -20)
                petHearts(t: t)
                    .offset(x: 0, y: -30)
                zzz(t: t)
                    .offset(x: 46, y: -14)
            }
        }
        .frame(width: 210, height: 210 * sceneHeight / sceneWidth)
        .task { await sleepWatchLoop() }
        .onChange(of: mood) { newValue in
            wakeUp()
            if newValue == .happy {
                showReaction("☽")
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

    // MARK: - 画小章鱼

    private func scene(t: TimeInterval) -> some View {
        let bobY = CGFloat(-3 * (1 - cos(t * 2 * .pi / 3.0)))
        let breathe: CGFloat = isPetted ? 1 + sin(t * 8) * 0.03 : 1
        let sway: CGFloat = isPetted ? CGFloat(sin(t * 4) * 3) : 0
        let cycle = 5.0
        let phase = t.truncatingRemainder(dividingBy: cycle)
        let blinking = !isAsleep && !isPetted && !heartBurst && phase > cycle * 0.88 && phase < cycle * 0.96

        return Canvas { context, size in
            let scale = size.width / sceneWidth
            let cx: CGFloat = sceneWidth / 2
            let headCY: CGFloat = 38
            let headR: CGFloat = 30
            let bellyR: CGFloat = 22

            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * scale, y: (y + bobY) * scale)
            }

            // 影子
            let shadowRect = CGRect(x: (cx - 28) * scale, y: 108 * scale, width: 56 * scale, height: 5 * scale)
            context.fill(Path(ellipseIn: shadowRect), with: .color(Self.ink.opacity(0.12)))

            context.drawLayer { layer in
                let bodyColor = isJealous ? Self.jealousBody : Self.body
                let blushAlpha: Double = isPetted ? 0.9 : (heartBurst ? 0.8 : 0.35)

                // — 触手（8条） —
                let tentacleAngles: [CGFloat] = [-65, -42, -20, -5, 5, 20, 42, 65]
                let tentacleBaseY: CGFloat = headCY + headR - 6
                for (i, angle) in tentacleAngles.enumerated() {
                    let rad = angle * .pi / 180
                    let baseX = cx + sin(rad) * bellyR * 0.7
                    let wiggle = CGFloat(sin(t * 2.5 + Double(i) * 0.8) * 4)
                    let wiggle2 = CGFloat(sin(t * 1.8 + Double(i) * 1.1) * 3)

                    let reachUp = heartBurst && (i < 2 || i > 5)
                    let crossArms = isJealous && (i >= 2 && i <= 5)
                    let curlSleep = isAsleep

                    var tipX: CGFloat
                    var tipY: CGFloat
                    var ctrlX: CGFloat
                    var ctrlY: CGFloat

                    if reachUp {
                        tipX = baseX + sin(rad) * 28 + wiggle
                        tipY = tentacleBaseY - 24
                        ctrlX = baseX + sin(rad) * 16 + wiggle * 0.5
                        ctrlY = tentacleBaseY - 10
                    } else if crossArms {
                        let cross: CGFloat = i <= 3 ? 8 : -8
                        tipX = cx + cross
                        tipY = tentacleBaseY + 14
                        ctrlX = baseX + cross * 0.5
                        ctrlY = tentacleBaseY + 8
                    } else if curlSleep {
                        tipX = baseX + sin(rad) * 8
                        tipY = tentacleBaseY + 10 + abs(wiggle2) * 0.5
                        ctrlX = baseX + sin(rad) * 14
                        ctrlY = tentacleBaseY + 6
                    } else {
                        tipX = baseX + sin(rad) * 22 + wiggle
                        tipY = tentacleBaseY + 26 + wiggle2
                        ctrlX = baseX + sin(rad) * 18 + wiggle * 0.5
                        ctrlY = tentacleBaseY + 14
                    }

                    var tentacle = Path()
                    tentacle.move(to: pt(baseX, tentacleBaseY))
                    tentacle.addQuadCurve(to: pt(tipX, tipY), control: pt(ctrlX, ctrlY))
                    layer.stroke(tentacle, with: .color(bodyColor),
                                 style: StrokeStyle(lineWidth: 5.5 * scale, lineCap: .round))
                    // 触手尖粉色
                    let tipPath = Path(ellipseIn: CGRect(
                        x: tipX * scale - 3 * scale, y: (tipY + bobY) * scale - 3 * scale,
                        width: 6 * scale, height: 6 * scale))
                    layer.fill(tipPath, with: .color(Self.tentacleTip))
                }

                // — 头部（大圆） —
                let headRect = CGRect(x: (cx - headR) * scale, y: (headCY - headR + bobY) * scale,
                                      width: headR * 2 * scale, height: headR * 2 * scale)
                layer.fill(Path(ellipseIn: headRect), with: .color(bodyColor))

                // — 月白色肚皮 —
                let bellyRect = CGRect(x: (cx - bellyR) * scale, y: (headCY - bellyR * 0.6 + bobY) * scale,
                                       width: bellyR * 2 * scale, height: bellyR * 1.5 * scale)
                layer.fill(Path(ellipseIn: bellyRect), with: .color(Self.belly))

                // — 头顶 ☽ 标记 —
                let moonSize: CGFloat = 7
                var moonPath = Path()
                let moonCX = cx + 2
                let moonCY = headCY - headR + 12
                moonPath.addArc(center: pt(moonCX, moonCY).applying(.init(scaleX: 1/scale, y: 1/scale)),
                                radius: moonSize, startAngle: .degrees(-90), endAngle: .degrees(90),
                                clockwise: false)
                moonPath.addArc(center: CGPoint(x: moonCX + 3, y: moonCY + bobY),
                                radius: moonSize * 0.7, startAngle: .degrees(90), endAngle: .degrees(-90),
                                clockwise: false)
                moonPath.closeSubpath()
                let scaledMoon = moonPath.applying(.init(scaleX: scale, y: scale))
                layer.fill(scaledMoon, with: .color(Self.belly.opacity(0.6)))

                // — 眼睛 —
                let eyeLX = cx - 12
                let eyeRX = cx + 12
                let eyeY = headCY - 2

                if isAsleep || blinking {
                    // 闭眼弧线
                    for ex in [eyeLX, eyeRX] {
                        var arc = Path()
                        arc.move(to: pt(ex - 5, eyeY))
                        arc.addQuadCurve(to: pt(ex + 5, eyeY),
                                         control: pt(ex, eyeY + 4))
                        layer.stroke(arc, with: .color(Self.ink),
                                     style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round))
                    }
                } else if heartBurst {
                    // ☽ 形眼睛
                    for ex in [eyeLX, eyeRX] {
                        var crescent = Path()
                        crescent.addArc(center: CGPoint(x: ex, y: eyeY + bobY),
                                        radius: 5, startAngle: .degrees(-100), endAngle: .degrees(100),
                                        clockwise: false)
                        crescent.addArc(center: CGPoint(x: ex + 2, y: eyeY + bobY),
                                        radius: 3.5, startAngle: .degrees(100), endAngle: .degrees(-100),
                                        clockwise: false)
                        crescent.closeSubpath()
                        let sc = crescent.applying(.init(scaleX: scale, y: scale))
                        layer.fill(sc, with: .color(Self.ink))
                    }
                } else if isPetted {
                    // 眯眯笑眼
                    for ex in [eyeLX, eyeRX] {
                        var arc = Path()
                        arc.move(to: pt(ex - 5, eyeY + 2))
                        arc.addQuadCurve(to: pt(ex + 5, eyeY + 2),
                                         control: pt(ex, eyeY - 3))
                        layer.stroke(arc, with: .color(Self.ink),
                                     style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round))
                    }
                } else if isJealous {
                    // 生气眼：倒八字 + 小圆眼
                    for (ex, flip) in [(eyeLX, false), (eyeRX, true)] {
                        let eyeRect = CGRect(x: (ex - 3.5) * scale, y: (eyeY - 3.5 + bobY) * scale,
                                             width: 7 * scale, height: 7 * scale)
                        layer.fill(Path(ellipseIn: eyeRect), with: .color(Self.ink))
                        var brow = Path()
                        let browInner: CGFloat = flip ? ex - 6 : ex + 6
                        let browOuter: CGFloat = flip ? ex + 6 : ex - 6
                        brow.move(to: pt(browInner, eyeY - 9))
                        brow.addLine(to: pt(browOuter, eyeY - 6))
                        layer.stroke(brow, with: .color(Self.ink),
                                     style: StrokeStyle(lineWidth: 2.5 * scale, lineCap: .round))
                    }
                } else {
                    // 正常大圆眼 + 月牙高光
                    for ex in [eyeLX, eyeRX] {
                        let eyeRect = CGRect(x: (ex - 4.5) * scale, y: (eyeY - 4.5 + bobY) * scale,
                                             width: 9 * scale, height: 9 * scale)
                        layer.fill(Path(ellipseIn: eyeRect), with: .color(Self.ink))
                        let hlRect = CGRect(x: (ex - 1.5) * scale, y: (eyeY - 3.5 + bobY) * scale,
                                            width: 3 * scale, height: 3 * scale)
                        layer.fill(Path(ellipseIn: hlRect), with: .color(.white.opacity(0.85)))
                    }
                }

                // — 腮红 —
                let blushY = eyeY + 9
                for bx in [cx - 18, cx + 12] {
                    let bRect = CGRect(x: bx * scale, y: (blushY + bobY) * scale,
                                       width: 8 * scale, height: 4.5 * scale)
                    layer.fill(Path(ellipseIn: bRect), with: .color(Self.blush.opacity(blushAlpha)))
                }

                // — 嘟嘴（吃醋时） —
                if isJealous {
                    var pout = Path()
                    let mouthY = eyeY + 14
                    pout.addEllipse(in: CGRect(x: (cx - 3) * scale, y: (mouthY + bobY) * scale,
                                               width: 6 * scale, height: 4 * scale))
                    layer.fill(pout, with: .color(Self.tentacleTip))
                }

                // — 笑嘴（被摸时） —
                if isPetted && !isJealous {
                    var mouth = Path()
                    mouth.move(to: pt(cx - 5, eyeY + 13))
                    mouth.addQuadCurve(to: pt(cx + 5, eyeY + 13),
                                       control: pt(cx, eyeY + 17))
                    layer.stroke(mouth, with: .color(Self.ink),
                                 style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
                }
            }

            // 名字牌
            let nameFont = Font.system(size: 11 * scale, weight: .regular, design: .serif).italic()
            context.draw(Text("hubby").font(nameFont).foregroundColor(Self.body),
                         at: CGPoint(x: cx * scale, y: (sceneHeight - 2) * scale))
        }
        .scaleEffect(pokeScale * breathe)
        .offset(x: sway)
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
        if isPetted || heartBurst {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.9 + Double(i) * 0.6).truncatingRemainder(dividingBy: 1.8)
                    Text("☽")
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

    // MARK: - 互动

    private func handleTap() {
        guard !isPetted else { return }
        wakeUp()
        withAnimation(.spring(response: 0.18, dampingFraction: 0.3)) { pokeScale = 0.82 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.4)) { pokeScale = 1.0 }
        }
        let zh = stickyReactionsZh.randomElement() ?? "在!"
        showReaction(L.t(zh, store.appLanguage))
        onInteract?()
    }

    private func handleDoubleTap() {
        wakeUp()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { heartBurst = true }
        showReaction("☽ ♡")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { heartBurst = false }
        }
        onInteract?()
    }

    func triggerJealous() {
        guard !isJealous else { return }
        wakeUp()
        withAnimation(.easeInOut(duration: 0.3)) { isJealous = true }
        showReaction("哼。")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.4)) { isJealous = false }
        }
    }

    private func showReaction(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { reactionText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeOut(duration: 0.25)) {
                if reactionText == text { reactionText = nil }
            }
        }
    }

    // MARK: - 睡眠

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

    // MARK: - 配色

    private static let body = Color(red: 0.30, green: 0.28, blue: 0.45)
    private static let belly = Color(red: 0.90, green: 0.92, blue: 0.96)
    private static let ink = Color(red: 0.08, green: 0.07, blue: 0.06)
    private static let blush = Color(red: 0.95, green: 0.65, blue: 0.72)
    private static let tentacleTip = Color(red: 0.85, green: 0.55, blue: 0.60)
    private static let jealousBody = Color(red: 0.60, green: 0.25, blue: 0.25)
}

/// 角色选择器里的 Octo 缩略图
struct OctoMiniPreview: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let scale = s / 50
            let cx: CGFloat = 25
            let headR: CGFloat = 14
            let body = Color(red: 0.30, green: 0.28, blue: 0.45)
            let belly = Color(red: 0.90, green: 0.92, blue: 0.96)
            let ink = Color(red: 0.08, green: 0.07, blue: 0.06)

            // 触手
            let angles: [CGFloat] = [-55, -25, 0, 25, 55]
            for angle in angles {
                let rad = angle * .pi / 180
                let baseX = cx + sin(rad) * 8
                let baseY: CGFloat = 28
                let tipX = baseX + sin(rad) * 12
                let tipY: CGFloat = 42
                var t = Path()
                t.move(to: CGPoint(x: baseX * scale, y: baseY * scale))
                t.addLine(to: CGPoint(x: tipX * scale, y: tipY * scale))
                context.stroke(t, with: .color(body),
                               style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
            }

            // 头
            let headRect = CGRect(x: (cx - headR) * scale, y: (14 - headR) * scale,
                                  width: headR * 2 * scale, height: headR * 2 * scale)
            context.fill(Path(ellipseIn: headRect), with: .color(body))

            // 肚皮
            let bRect = CGRect(x: (cx - 8) * scale, y: 6 * scale,
                               width: 16 * scale, height: 12 * scale)
            context.fill(Path(ellipseIn: bRect), with: .color(belly))

            // 眼睛
            for ex in [cx - 6, cx + 6] {
                let eRect = CGRect(x: (ex - 2) * scale, y: 10 * scale,
                                   width: 4 * scale, height: 4 * scale)
                context.fill(Path(ellipseIn: eRect), with: .color(ink))
            }
        }
    }
}
