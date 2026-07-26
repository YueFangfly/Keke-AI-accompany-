import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case keke
    }

    var id: UUID
    let role: Role
    var text: String
    let date: Date
    var isFavorite: Bool
    /// 附件图片（attachments 目录里的文件名）
    var imagePath: String?
    /// 附件文档名
    var docName: String?
    /// 从文档里提取的文字（发给克克用）
    var docText: String?
    /// 克克的心里话（第一人称碎碎念），默认折叠，只有克克自己选择写的时候才有
    var thinking: String?
    /// 本地识图（Vision 框架，不花钱）算出来的大致内容，缓存起来避免重复算。
    /// 只在当前用的模型不支持看图（比如 DeepSeek）时才会用到
    var localImageCaption: String?

    init(role: Role, text: String, date: Date = Date(), isFavorite: Bool = false,
         imagePath: String? = nil, docName: String? = nil, docText: String? = nil,
         thinking: String? = nil) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.date = date
        self.isFavorite = isFavorite
        self.imagePath = imagePath
        self.docName = docName
        self.docText = docText
        self.thinking = thinking
    }
}
