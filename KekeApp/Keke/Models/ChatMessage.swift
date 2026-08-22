import Foundation

struct ChoiceOption: Codable, Equatable, Identifiable {
    var id: String { label }
    let label: String
}

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
    /// 可点击的选项按钮（AI 弹出让用户选择）
    var choices: [ChoiceOption]?
    var multiSelect: Bool?
    /// 关联的音频 ID（AI 调用播放工具时附带）
    var audioTrackId: String?

    init(role: Role, text: String, date: Date = Date(), isFavorite: Bool = false,
         imagePath: String? = nil, docName: String? = nil, docText: String? = nil,
         thinking: String? = nil, choices: [ChoiceOption]? = nil, multiSelect: Bool? = nil,
         audioTrackId: String? = nil) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.date = date
        self.isFavorite = isFavorite
        self.imagePath = imagePath
        self.docName = docName
        self.docText = docText
        self.thinking = thinking
        self.choices = choices
        self.multiSelect = multiSelect
        self.audioTrackId = audioTrackId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        isFavorite = try c.decode(Bool.self, forKey: .isFavorite)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        docName = try c.decodeIfPresent(String.self, forKey: .docName)
        docText = try c.decodeIfPresent(String.self, forKey: .docText)
        thinking = try c.decodeIfPresent(String.self, forKey: .thinking)
        localImageCaption = try c.decodeIfPresent(String.self, forKey: .localImageCaption)
        choices = try c.decodeIfPresent([ChoiceOption].self, forKey: .choices)
        multiSelect = try c.decodeIfPresent(Bool.self, forKey: .multiSelect)
        audioTrackId = try c.decodeIfPresent(String.self, forKey: .audioTrackId)
    }
}
