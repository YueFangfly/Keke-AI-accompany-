import Foundation

/// 一条碎片。
///
/// 日记要求你**坐下来写一段话**，所以没人写。碎片的门槛是「随手扔一句」——
/// 一句话、一张图、一段说出来的话，都算。整理是后面的事，记的时候不用管。
///
/// 碎片和 `DiaryEntry` 是两种东西，互不干涉：日记是**写好的**，碎片是**攒着的**。
struct Fragment: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case text, photo, voice }

    var id = UUID()
    var kind: Kind
    /// 打的字 / 说的话转出来的字。纯照片碎片可以是空的
    var text: String = ""
    var date: Date = Date()
    /// attachments 目录里的文件名
    var imagePath: String? = nil
    /// 媒体理解的结果。为 nil = 还没分析（或者这条根本没有媒体）
    var analysis: MediaAnalysis? = nil

    /// 这条碎片在时间线上应该落在什么时候。
    ///
    /// 照片优先用**拍摄时间**：昨天拍的照片今天才扔进来，它讲的是昨天的事。
    /// 拿不到拍摄时间就退回记录时间
    var occurredAt: Date { analysis?.capturedAt ?? date }

    /// 摘要：列表里显示一行用。照片没配文字时退回它自己「看」到的东西
    var summary: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let analysis, let seen = analysis.shortDescription { return seen }
        switch kind {
        case .photo: return "一张照片"
        case .voice: return "一段没听清的话"
        case .text: return ""
        }
    }
}

/// 本地媒体理解的结果。
///
/// **全部在设备上算**：EXIF 走 ImageIO，标签和图里的文字走 Vision，
/// 说的话走 Speech 框架。一个字节都不上传，也不花一分钱。
struct MediaAnalysis: Codable, Equatable {
    /// EXIF 里的拍摄时间。跟碎片的记录时间不是一回事
    var capturedAt: Date? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// Vision 认出来的场景 / 物体标签
    var labels: [String] = []
    /// 图里的文字
    var ocr: String = ""
    /// 分析完成的时间。这个字段的存在本身就说明「跑过了」
    var analyzedAt: Date = Date()
    /// 跑失败了的话，失败原因。**碎片本身照样留着**——
    /// 读不懂这张图不是丢掉用户输入的理由
    var failure: String? = nil

    var hasLocation: Bool { latitude != nil && longitude != nil }

    /// 一句话说清这张图里有什么。没看出任何东西就返回 nil
    var shortDescription: String? {
        var parts: [String] = []
        if !labels.isEmpty { parts.append(labels.prefix(3).joined(separator: "、")) }
        let text = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { parts.append("「" + String(text.prefix(20)) + "」") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
