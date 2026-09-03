import Foundation

/// 协议指令：跟人设无关的那部分 system prompt。
///
/// 人设（角色是谁、什么性格、怎么说话）完全由用户自己写，App 一个字都不塞。
/// 但有些功能需要模型知道特定的输出格式才能生效——比如选项按钮要靠 `<choices>` 标签
/// 才能变成可点的按钮。这类"怎么用这个 App 的功能"的说明放在这里，
/// 拼在用户人设后面一起发。
///
/// 这么分开是为了：换任何人设，功能都照样能用；改功能格式也不用去动用户写的人设。
enum ChatProtocolPrompt {

    /// 选项按钮的用法
    static let choices = """
    关于选项按钮（可选功能）：当你想让对方做选择时（比如"今天想做什么"、"吃什么"、"选一个"），
    可以在回复最末尾加上选项标签，格式如下：
    单选：正式回复文字\n<choices>选项A|选项B|选项C</choices>
    多选：正式回复文字\n<choices multi>选项A|选项B|选项C</choices>
    选项会变成可点击的按钮显示出来。只在真的有选择场景时才用，
    日常聊天不要用——不然会像客服机器人。选项文字要简短自然（2~8 个字）。
    """

    /// 「在聊天里改设置」的用法。只有那个开关打开、工具真的注入了才发这段
    static let settingsTools = """
    你有「改设置」的工具可以用：对方要求你调整设置时直接调用对应工具，
    改完简短说一句改成了什么，不用逐字确认工具细节。没被明确要求的时候不要主动去改。
    """

    /// 语音条的用法。**开关默认关着**，关着就一个字都不发——
    /// 模型很擅长模仿格式，多塞一种标记就多一分它到处乱用的风险
    static let voiceBar = """
    关于语音条（可选功能）：有些话说出来比打字自然（撒娇、哄人、念一段东西），
    这时可以把要"说"的那部分用标签圈起来：
    \(VoiceBar.openTag)这段会变成语音条\(VoiceBar.closeTag)其余照旧是文字。
    语音条会显示成一条可以点开听的气泡。一条回复里最多用一两次，
    正常聊天该打字还是打字——每句都发语音很烦人。
    标签里不要写动作和括号，那些念出来很怪。
    """

    /// 拼出这次要附加的协议说明。都不需要就返回空字符串
    static func block(settingsToolsEnabled: Bool, voiceBarEnabled: Bool = false) -> String {
        var parts = [choices]
        if settingsToolsEnabled { parts.append(settingsTools) }
        if voiceBarEnabled { parts.append(voiceBar) }
        return parts.joined(separator: "\n\n")
    }

    /// 跟用户写的人设拼在一起。人设为空就只发协议说明
    static func combined(persona: String, settingsToolsEnabled: Bool,
                         voiceBarEnabled: Bool = false) -> String {
        let persona = persona.trimmingCharacters(in: .whitespacesAndNewlines)
        let protocolBlock = block(settingsToolsEnabled: settingsToolsEnabled,
                                  voiceBarEnabled: voiceBarEnabled)
        if persona.isEmpty { return protocolBlock }
        if protocolBlock.isEmpty { return persona }
        return persona + "\n\n" + protocolBlock
    }
}
