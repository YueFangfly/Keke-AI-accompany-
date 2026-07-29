import SwiftUI

/// 点首页状态面板的某一条百分比进来：这一维的 24 小时曲线 + 漂流思绪
struct KekeStateDetailView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var kekeState: KekeStateService
    let dim: KekeStateDim

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                curveCard
                thoughtsCard
            }
            .padding(14)
        }
        .background(Theme.background)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L.t(dim.labelKey, lang))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(Int(kekeState.value(dim).rounded()))%")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 24h 曲线

    private var curveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("24 小时曲线", lang))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            let points = kekeState.curvePoints(for: dim)
            if points.count < 2 {
                Text(L.t("数据还太少，聊一聊、过一会儿再来看", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                StateCurveChart(points: points)
                    .frame(height: 150)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    // MARK: - 漂流思绪

    private var thoughtsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("🫧")
                Text(L.t("漂流思绪", lang))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            if kekeState.thoughts.isEmpty {
                Text(L.t("还没有思绪飘过——多聊聊，她脑子里的话会自己冒出来，也会记进她的日记", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 10)
            } else {
                ForEach(kekeState.thoughts.prefix(30)) { thought in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(thought.text)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            if thought.isObsession {
                                Text(L.t("执念", lang))
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.accent))
                            }
                        }
                        HStack(spacing: 6) {
                            Text(thought.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary)
                            intensityDots(thought.intensity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(thought.isObsession ? Theme.accent.opacity(0.08) : Theme.card))
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    private func intensityDots(_ intensity: Double) -> some View {
        let filled = max(1, min(5, Int((intensity * 5).rounded())))
        return HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i < filled ? Theme.accent : Theme.textSecondary.opacity(0.2))
                    .frame(width: 4, height: 4)
            }
        }
    }
}

/// 简单的手绘折线图：X 轴是最近 24 小时，Y 轴 0~100
struct StateCurveChart: View {
    let points: [(date: Date, value: Double)]

    var body: some View {
        GeometryReader { geo in
            chart(size: geo.size)
        }
    }

    private func chart(size: CGSize) -> some View {
        let width = size.width
        let height = size.height
        let start = Date().addingTimeInterval(-24 * 3600)

        return ZStack(alignment: .topLeading) {
            // 横向参考线：0 / 50 / 100
            ForEach([0.0, 50.0, 100.0], id: \.self) { mark in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: yPos(mark, height: height)))
                    path.addLine(to: CGPoint(x: width, y: yPos(mark, height: height)))
                }
                .stroke(Theme.textSecondary.opacity(0.18), lineWidth: 1)
                Text("\(Int(mark))")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    .offset(x: 2, y: yPos(mark, height: height) - (mark > 90 ? 0 : 11))
            }

            // 曲线下面淡淡的填充
            Path { path in
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: xPos(first.date, width: width, start: start), y: height))
                for point in points {
                    path.addLine(to: CGPoint(x: xPos(point.date, width: width, start: start),
                                             y: yPos(point.value, height: height)))
                }
                if let last = points.last {
                    path.addLine(to: CGPoint(x: xPos(last.date, width: width, start: start), y: height))
                }
                path.closeSubpath()
            }
            .fill(Theme.accent.opacity(0.14))

            // 曲线本体
            Path { path in
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: xPos(first.date, width: width, start: start),
                                      y: yPos(first.value, height: height)))
                for point in points.dropFirst() {
                    path.addLine(to: CGPoint(x: xPos(point.date, width: width, start: start),
                                             y: yPos(point.value, height: height)))
                }
            }
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // 当下这个点
            if let last = points.last {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 6, height: 6)
                    .position(x: xPos(last.date, width: width, start: start),
                              y: yPos(last.value, height: height))
            }
        }
    }

    private func xPos(_ date: Date, width: CGFloat, start: Date) -> CGFloat {
        let ratio = date.timeIntervalSince(start) / (24 * 3600)
        return width * CGFloat(min(max(ratio, 0), 1))
    }

    private func yPos(_ value: Double, height: CGFloat) -> CGFloat {
        height * CGFloat(1 - min(max(value, 0), 100) / 100)
    }
}
