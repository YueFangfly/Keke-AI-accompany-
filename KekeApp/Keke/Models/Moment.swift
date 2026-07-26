import Foundation

/// 朋友圈/日记的一条评论（含往来盖楼）
struct MomentComment: Identifiable, Codable, Equatable {
    /// friend = 克克以外的联系人（多窗口改造后大家都是好友），名字存在 friendName 里
    enum Author: String, Codable { case me, keke, friend }

    var id = UUID()
    var author: Author
    var text: String
    var date: Date = Date()
    /// 这条是回复某条评论的：存一小段被回复内容的预览，纯展示用，不是严格的树状结构
    var replyToAuthor: Author?
    var replyToPreview: String?
    /// author == .friend 时：是哪个联系人（id + 当时的备注名）
    var friendID: String?
    var friendName: String?
}

/// 朋友圈/日记的一条动态，我和克克都可以发；其他联系人（好友）会刷到我发的动态，
/// 看到了可以点赞/评论（看没看到、回不回都是概率）
struct Moment: Identifiable, Codable, Equatable {
    enum Author: String, Codable { case me, keke }

    var id = UUID()
    var author: Author
    var text: String
    var date: Date = Date()
    var imagePath: String?
    var likedByMe = false
    var likedByKeke = false
    /// 点过赞的好友联系人 id（渲染时再换算成备注名）
    var likedByFriends: [String]?
    var comments: [MomentComment] = []
    /// 克克下次"刷到"这条动态该回应（点赞+评论，或者回复最新一条评论）的时间；
    /// nil 代表当下不需要她回应。时间是随机排的，不是固定延迟，模拟"刷到了才回"
    var pendingReplyAt: Date?
    /// 各个好友"刷到"这条的时间（联系人 id -> 时间）；没排进来的代表这条他压根没刷到
    var pendingFriendReactions: [String: Date]?
}
