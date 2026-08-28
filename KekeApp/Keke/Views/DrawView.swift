import SwiftUI

/// 探索 → 一起画画：我手指手绘，画完点"轮到克克"，她读一下已有笔画的坐标猜画面，
/// 自己用"画笔"生成几笔线条加上去（不需要看图能力，任何模型都能玩；也不是图片生成，是坐标连成线）
struct DrawTogetherView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var draw: DrawService

    @State private var currentPoints: [CGPoint] = []
    @State private var canvasSize = CGSize(width: 320, height: 320)

    private var lang: AppLanguage { store.appLanguage }
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }
    private let myColor = Theme.crabRed
    private let kekeColor = Theme.accent

    var body: some View {
        VStack(spacing: 12) {
            legend
            canvasArea
            controls
            if store.apiKey.isEmpty {
                Text(String(format: L.t("先在设置里填好 API Key，%@才能一起画", lang), personaName))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.background)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Circle().fill(myColor).frame(width: 9, height: 9)
                Text(store.myName).font(.caption).foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: 5) {
                Circle().fill(kekeColor).frame(width: 9, height: 9)
                Text(personaName).font(.caption).foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            if draw.isKekeThinking {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text(String(format: L.t("%@在想画什么…", lang), personaName))
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var canvasArea: some View {
        GeometryReader { geo in
            drawingLayer(size: geo.size)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            guard draw.turn == .me, !draw.isKekeThinking else { return }
                            currentPoints.append(value.location)
                        }
                        .onEnded { _ in
                            defer { currentPoints = [] }
                            guard !currentPoints.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return }
                            let normalized = currentPoints.map {
                                CGPoint(x: $0.x / canvasSize.width, y: $0.y / canvasSize.height)
                            }
                            draw.addStroke(normalized)
                        }
                )
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { canvasSize = $0 }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    @ViewBuilder
    private func drawingLayer(size: CGSize) -> some View {
        ZStack {
            scaledPath(author: .keke, size: size)
                .stroke(kekeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            scaledPath(author: .me, size: size)
                .stroke(myColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            rawPath(currentPoints)
                .stroke(myColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }

    private func scaledPath(author: DrawAuthor, size: CGSize) -> Path {
        var path = Path()
        for stroke in draw.strokes where stroke.author == author {
            let scaled = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            appendStroke(scaled, to: &path)
        }
        return path
    }

    private func rawPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        appendStroke(points, to: &path)
        return path
    }

    private func appendStroke(_ points: [CGPoint], to path: inout Path) {
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                draw.undoLastMyStroke()
            } label: {
                Label(L.t("撤销我这笔", lang), systemImage: "arrow.uturn.backward")
                    .font(.caption)
            }
            .disabled(draw.turn != .me || !draw.strokes.contains(where: { $0.author == .me }))

            Button(role: .destructive) {
                draw.clear()
            } label: {
                Label(L.t("清空", lang), systemImage: "trash")
                    .font(.caption)
            }

            Spacer()

            Button {
                Task { await draw.requestKekeMove(store: store) }
            } label: {
                Text(String(format: L.t("轮到%@", lang), personaName))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.accent))
            }
            .disabled(draw.turn != .me || draw.isKekeThinking || store.apiKey.isEmpty)
        }
    }
}
