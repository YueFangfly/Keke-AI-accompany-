import Foundation
import CoreGraphics

/// 一起画画：我手绘 + 克克自己用"画笔"画几笔，轮流进行。
/// 克克不是靠"看"画布——是读已有笔画的坐标猜画面，所以任何模型（包括不支持看图的 DeepSeek）都能玩
@MainActor
final class DrawService: ObservableObject {
    let personaId: String
    @Published var strokes: [DrawStroke] = []
    @Published var turn: DrawAuthor = .me
    @Published var isKekeThinking = false

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_drawing.json")
    }

    init(personaId: String = "keke") {
        self.personaId = personaId
        load()
    }

    func addStroke(_ points: [CGPoint]) {
        guard points.count > 1 else { return }
        strokes.append(DrawStroke(author: .me, points: points))
        save()
    }

    func undoLastMyStroke() {
        guard let index = strokes.lastIndex(where: { $0.author == .me }) else { return }
        strokes.remove(at: index)
        save()
    }

    func clear() {
        strokes = []
        turn = .me
        save()
    }

    /// 我画完点"轮到克克"：把已有笔画的坐标描述给她，让她自己画几笔加上去
    func requestKekeMove(store: ChatStore) async {
        guard !store.apiKey.isEmpty else {
            turn = .me
            return
        }
        turn = .keke
        isKekeThinking = true
        defer { isKekeThinking = false; turn = .me }

        guard let newStrokes = try? await ClaudeService.generateDrawingStrokes(
            existingStrokesDescription: strokesDescription(userName: store.myName), userName: store.myName,
            provider: store.provider, apiKey: store.apiKey, model: store.model,
            systemPrompt: store.effectiveSystemPrompt
        ) else { return }

        for points in newStrokes {
            strokes.append(DrawStroke(author: .keke, points: points))
        }
        save()
    }

    /// 把现有笔画编码成跟她自己输出一样的坐标格式，喂回去当上下文
    private func strokesDescription(userName: String) -> String {
        strokes.enumerated().map { index, stroke in
            let authorTag = stroke.author == .me ? userName : "克克"
            let pointsText = stroke.points.map { String(format: "%.2f,%.2f", $0.x, $0.y) }.joined(separator: ";")
            return "笔\(index + 1)(\(authorTag)): \(pointsText)"
        }.joined(separator: "\n")
    }

    // MARK: - 持久化

    private func save() {
        guard let data = try? JSONEncoder().encode(strokes) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([DrawStroke].self, from: data) else { return }
        strokes = saved
    }
}
