import Foundation

/// 私密日记：我和克克各写各的，作者自己决定这一篇给不给对方看
struct DiaryEntry: Identifiable, Codable, Equatable {
    enum Author: String, Codable { case me, keke }

    var id = UUID()
    var author: Author
    var text: String
    var date: Date = Date()
    /// 作者本人决定要不要给对方看这一篇
    var sharedWithOther: Bool = false
    /// 对方（正常途径，不是偷看）有没有看过这篇分享的日记
    var readByOther: Bool = false
    /// 我有没有偷看过克克没公开的这篇
    var peeked: Bool = false
    /// 偷看的时候有没有被她"发现"
    var peekNoticed: Bool = false
    /// 对方看完（正常分享的，或者偷看被发现的）之后可能留的一句反应
    var reaction: String?
    /// 配图（attachments 目录里的文件名）。克克配的图大概率是当天朋友圈截图，不是她自己画的
    var imagePath: String?
    /// 这一篇下面的评论，我和她都能留
    var comments: [DiaryComment] = []
}

/// 日记条目下面的一条评论
struct DiaryComment: Identifiable, Codable, Equatable {
    var id = UUID()
    var author: DiaryEntry.Author
    var text: String
    var date: Date = Date()
}
