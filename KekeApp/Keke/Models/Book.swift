import Foundation

/// 一本导入的书；正文单独存成文本文件（见 BookService），这里只放元数据
struct Book: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var fileName: String
    var addedAt: Date = Date()
    var lastOpenedAt: Date?
    /// 我读到的段落下标（BookService 按段落切好正文）
    var myProgress: Int = 0
    /// 克克自己读到的段落下标
    var kekeProgress: Int = 0
    var totalParagraphs: Int = 0
    var bookmarks: [Bookmark] = []

    var progressPercent: Double {
        guard totalParagraphs > 0 else { return 0 }
        return Double(myProgress) / Double(totalParagraphs)
    }
}

/// 手动存的书签（跟自动记的"读到哪"是两回事，书签是自己特意想留住的位置）
struct Bookmark: Identifiable, Codable, Equatable {
    var id = UUID()
    var paragraphIndex: Int
    var preview: String
    var date: Date = Date()
}

/// 书里的一条批注/想法
struct BookNote: Identifiable, Codable, Equatable {
    enum Author: String, Codable { case me, keke }

    var id = UUID()
    var bookID: UUID
    var author: Author
    /// 批注挂在正文的第几段
    var paragraphIndex: Int
    var text: String
    var date: Date = Date()
    var replyToID: UUID?
}
