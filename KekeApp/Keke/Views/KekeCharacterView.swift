import SwiftUI

enum KekeMood {
    case idle       // 待机：轻轻晃、慢慢眨眼
    case thinking   // 思考中：冒"……"
    case happy      // 开心：一声"喵~"
}

/// 养克克那块：keke 和 moon 两只像素小猫，尾巴弯向彼此，中间一颗跳动的小心心。
/// 戳一下、长按摸头、双击比心，闲置久了会睡着——原来螃蟹的互动逻辑照搬过来，
/// 只是画法从 SwiftUI 图形换成了像素画风的 Canvas
struct KekeCharacterView: View {
    @EnvironmentObject var store: ChatStore
    var mood: KekeMood
    /// 每次真的有互动（戳/摸/双击）触发一次，Home 页养克克那块用它来涨状态条
    var onInteract: (() -> Void)? = nil

    // 互动状态
    @State private var pokeScale: CGFloat = 1.0
    @State private var isPetted = false
    @State private var heartBurst = false
    @State private var isAsleep = false
    @State private var lastInteractionDate = Date()
    @State private var reactionText: String?
    @State private var stars: [Star] = []
    private let stickyReactionsZh = ["嘻嘻", "戳我干嘛~", "在!"]

    private struct Star: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
        let phase: Double
    }

    // 原始设计稿的 viewBox 是 340×175
    private let sceneWidth: CGFloat = 340
    private let sceneHeight: CGFloat = 175

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                scene(t: t)
                reactionBubble
                    .offset(x: 60, y: -6)
                petHearts(t: t)
                    .offset(x: 0, y: -20)
                zzz(t: t)
                    .offset(x: 54, y: 6)
            }
        }
        .frame(width: 220, height: 220 * sceneHeight / sceneWidth)
        .task { await sleepWatchLoop() }
        .onChange(of: mood) { newValue in
            wakeUp()
            if newValue == .happy {
                showReaction("喵~")
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

    // MARK: - 画两只猫

    private func scene(t: TimeInterval) -> some View {
        let bobY = -3 * (1 - cos(t * 2 * .pi / 3.4))
        let kekeTailAngle = 3 - 3 * cos(t * 2 * .pi / 2.8)
        let moonTailAngle = -(3 - 3 * cos((t - 1.4) * 2 * .pi / 2.8))
        let ahogeAngle = 0.5 - 6.5 * cos(t * 2 * .pi / 2.2)
        let heartScale = 1 + 0.09 * (1 - cos(t * 2 * .pi / 2.5))
        let heartOpacity = 0.85 + 0.075 * (1 - cos(t * 2 * .pi / 2.5))
        let cycle = 5.0
        let kekePhase = t.truncatingRemainder(dividingBy: cycle)
        let kekeBlinking = !isAsleep && !isPetted && kekePhase > cycle * 0.88 && kekePhase < cycle * 0.96
        let moonPhase = (t + cycle - 0.9).truncatingRemainder(dividingBy: cycle)
        let moonBlinking = !isAsleep && !isPetted && moonPhase > cycle * 0.88 && moonPhase < cycle * 0.96
        let breathe = isPetted ? 1 + sin(t * 8) * 0.03 : 1

        return Canvas { context, size in
            let scale = size.width / sceneWidth

            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 10, _ h: CGFloat = 10) -> Path {
                Path(CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale))
            }
            func fillPixels(_ points: [(CGFloat, CGFloat)], offset: (CGFloat, CGFloat), color: Color) {
                for (x, y) in points { context.fill(rect(x + offset.0, y + offset.1), with: .color(color)) }
            }
            func rotatedPixels(_ points: [(CGFloat, CGFloat)], offset: (CGFloat, CGFloat),
                               pivot: (CGFloat, CGFloat), angle: Double, color: Color) {
                context.drawLayer { layer in
                    layer.translateBy(x: pivot.0 * scale, y: pivot.1 * scale)
                    layer.rotate(by: .degrees(angle))
                    layer.translateBy(x: -pivot.0 * scale, y: -pivot.1 * scale)
                    for (x, y) in points {
                        layer.fill(rect(x + offset.0, y + offset.1), with: .color(color))
                    }
                }
            }
            func smileEyes(center: (CGFloat, CGFloat), color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: (center.0 - 4) * scale, y: center.1 * scale))
                path.addQuadCurve(to: CGPoint(x: (center.0 + 4) * scale, y: center.1 * scale),
                                  control: CGPoint(x: center.0 * scale, y: (center.1 + 4) * scale))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round))
            }
            func sleepyEyes(center: (CGFloat, CGFloat), color: Color) {
                context.fill(rect(center.0 - 6, center.1 - 1, 12, 2.5), with: .color(color))
            }
            func mouth(startX: CGFloat, y: CGFloat, color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: startX * scale, y: y * scale))
                path.addQuadCurve(to: CGPoint(x: (startX + 5) * scale, y: y * scale),
                                  control: CGPoint(x: (startX + 2.5) * scale, y: (y + 3) * scale))
                path.addQuadCurve(to: CGPoint(x: (startX + 10) * scale, y: y * scale),
                                  control: CGPoint(x: (startX + 7.5) * scale, y: (y + 3) * scale))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round))
            }

            // 夜空小月亮
            for (x, y) in Self.skyMoonPixels { context.fill(rect(x, y), with: .color(Self.starColor.opacity(0.9))) }

            // 星星
            for star in stars {
                let twinkle = (1 - cos((t + star.phase) * 2 * .pi / 3.4)) / 2
                let opacity = 0.15 + 0.65 * twinkle
                let radius = (1.4 + 0.6 * twinkle) * scale
                let center = CGPoint(x: star.x * sceneWidth * scale, y: star.y * sceneHeight * scale)
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2)),
                            with: .color(Self.starColor.opacity(opacity)))
            }

            // keke（左，暖杏色）
            rotatedPixels(Self.tailPixels, offset: (20, 30), pivot: (75, 140), angle: kekeTailAngle, color: Self.kekeDark)
            fillPixels(Self.earPixels, offset: (20, 30), color: Self.kekeFur)
            fillPixels(Self.headBodyPixels, offset: (20, 30), color: Self.kekeFur)
            fillPixels(Self.pawPixels, offset: (20, 30), color: Self.kekeDark)
            if isAsleep {
                sleepyEyes(center: (53, 86), color: Self.nightDeep)
                sleepyEyes(center: (81, 86), color: Self.nightDeep)
            } else if isPetted || kekeBlinking {
                smileEyes(center: (53, 86), color: Self.nightDeep)
                smileEyes(center: (81, 86), color: Self.nightDeep)
            } else {
                context.fill(rect(49, 82), with: .color(Self.nightDeep))
                context.fill(rect(77, 82), with: .color(Self.nightDeep))
                context.fill(rect(51.7, 83.2, 2.6, 2.6), with: .color(.white.opacity(0.95)))
                context.fill(rect(79.7, 83.2, 2.6, 2.6), with: .color(.white.opacity(0.95)))
            }
            mouth(startX: 61, y: 96, color: Self.nightDeep)
            context.fill(rect(40, 91, 8, 5), with: .color(Self.blushColor.opacity(isPetted ? 0.9 : 0.75)))
            context.fill(rect(83, 91, 8, 5), with: .color(Self.blushColor.opacity(isPetted ? 0.9 : 0.75)))

            // moon（右，薰衣草紫，带呆毛）
            rotatedPixels(Self.moonTailPixels, offset: (230, 30), pivot: (265, 140), angle: moonTailAngle, color: Self.moonDark)
            rotatedPixels(Self.ahogePixels, offset: (230, 30), pivot: (270, 50), angle: ahogeAngle, color: Self.moonDark)
            fillPixels(Self.earPixels, offset: (230, 30), color: Self.moonFur)
            fillPixels(Self.headBodyPixels, offset: (230, 30), color: Self.moonFur)
            fillPixels(Self.pawPixels, offset: (230, 30), color: Self.moonDark)
            if isAsleep {
                sleepyEyes(center: (258, 86), color: Self.nightDeep)
                sleepyEyes(center: (286, 86), color: Self.nightDeep)
            } else if isPetted || moonBlinking {
                smileEyes(center: (258, 86), color: Self.nightDeep)
                smileEyes(center: (286, 86), color: Self.nightDeep)
            } else {
                context.fill(rect(254, 82), with: .color(Self.nightDeep))
                context.fill(rect(282, 82), with: .color(Self.nightDeep))
                context.fill(rect(256.7, 83.2, 2.6, 2.6), with: .color(.white.opacity(0.95)))
                context.fill(rect(284.7, 83.2, 2.6, 2.6), with: .color(.white.opacity(0.95)))
            }
            mouth(startX: 266, y: 96, color: Self.nightDeep)
            context.fill(rect(245, 91, 8, 5), with: .color(Self.blushColor.opacity(isPetted ? 0.9 : 0.75)))
            context.fill(rect(288, 91, 8, 5), with: .color(Self.blushColor.opacity(isPetted ? 0.9 : 0.75)))

            // 中间的心心
            context.drawLayer { layer in
                let cx: CGFloat = 170 * scale
                let cy: CGFloat = 104 * scale
                layer.translateBy(x: cx, y: cy)
                let s = heartScale * (heartBurst ? 1.6 : 1)
                layer.scaleBy(x: s, y: s)
                layer.translateBy(x: -cx, y: -cy)
                layer.opacity = heartOpacity
                for (x, y, w, h) in Self.heartPixels {
                    layer.fill(rect(x, y, w, h), with: .color(Self.blushColor))
                }
            }

            // 名字牌
            let nameFont = Font.system(size: 12 * scale, weight: .regular, design: .serif).italic()
            context.draw(Text("keke").font(nameFont).foregroundColor(Self.kekeFur), at: CGPoint(x: 65 * scale, y: 168 * scale))
            context.draw(Text("moon").font(nameFont).foregroundColor(Self.moonFur), at: CGPoint(x: 275 * scale, y: 168 * scale))
        }
        .scaleEffect(pokeScale * breathe)
        .offset(y: bobY)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Self.night, Self.nightDeep], startPoint: .top, endPoint: .bottom))
        )
        .onAppear { if stars.isEmpty { generateStars() } }
    }

    private func generateStars() {
        stars = (0..<16).map { _ in
            Star(x: Double.random(in: 0.03...0.97), y: Double.random(in: 0.05...0.85), phase: Double.random(in: 0...3.4))
        }
    }

    // MARK: - 反应气泡 / 心心 / zZz（跟原来螃蟹版一样的逻辑，换个位置摆）

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

    // MARK: - 像素画数据（对应原设计稿里 10 格单位的网格）

    private static let earPixels: [(CGFloat, CGFloat)] = [
        (10, 20), (70, 20), (10, 30), (20, 30), (60, 30), (70, 30),
    ]
    private static let headBodyPixels: [(CGFloat, CGFloat)] = {
        // stride 的字面量要显式标成 CGFloat，不然被推断成 Int，
        // (Int, Int) 塞不进 [(CGFloat, CGFloat)] 会编译报错
        var pts: [(CGFloat, CGFloat)] = []
        for y in stride(from: CGFloat(40), through: 70, by: 10) {
            for x in stride(from: CGFloat(10), through: 70, by: 10) { pts.append((x, y)) }
        }
        for y in stride(from: CGFloat(80), through: 110, by: 10) {
            for x in stride(from: CGFloat(0), through: 80, by: 10) { pts.append((x, y)) }
        }
        return pts
    }()
    private static let pawPixels: [(CGFloat, CGFloat)] = [(10, 120), (30, 120), (50, 120), (70, 120)]
    private static let tailPixels: [(CGFloat, CGFloat)] = [(90, 110), (100, 100), (100, 90), (90, 80)]
    private static let moonTailPixels: [(CGFloat, CGFloat)] = [(-20, 110), (-30, 100), (-30, 90), (-20, 80)]
    private static let ahogePixels: [(CGFloat, CGFloat)] = [(30, 10), (40, 0)]
    private static let heartPixels: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (157, 88, 8, 8), (175, 88, 8, 8), (152, 96, 36, 8), (157, 104, 26, 8), (162, 112, 16, 8), (167, 120, 6, 6),
    ]
    private static let skyMoonPixels: [(CGFloat, CGFloat)] = [
        (160, 0), (170, 0), (150, 10), (160, 20), (170, 20),
    ]

    private static let night = Color(red: 0.106, green: 0.118, blue: 0.2)
    private static let nightDeep = Color(red: 0.078, green: 0.09, blue: 0.165)
    private static let kekeFur = Color(red: 0.953, green: 0.812, blue: 0.635)
    private static let kekeDark = Color(red: 0.867, green: 0.659, blue: 0.431)
    private static let moonFur = Color(red: 0.804, green: 0.706, blue: 0.910)
    private static let moonDark = Color(red: 0.651, green: 0.533, blue: 0.812)
    private static let blushColor = Color(red: 0.949, green: 0.651, blue: 0.722)
    private static let starColor = Color(red: 1.0, green: 0.914, blue: 0.659)
}
