import Foundation
import CoreGraphics

/// 一起画画：我和克克轮流在同一块画布上画，都是真的用"画笔"画线条——
/// 我手指拖动出线条，克克是 AI 根据画布快照直接生成一串坐标点连成线，不是挑现成的贴纸
enum DrawAuthor: String, Codable {
    case me, keke
}

/// 一笔画（一串连起来的点），坐标是相对画布的比例，0...1，左上角是 (0,0)
struct DrawStroke: Identifiable, Codable, Equatable {
    var id = UUID()
    var author: DrawAuthor
    var points: [CGPoint]
}
