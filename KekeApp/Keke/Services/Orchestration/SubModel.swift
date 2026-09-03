import Foundation

/// 脏活用的便宜模型。
///
/// 压缩历史、提炼记忆、把关、去重判定、生成日摘要——这些活**不需要人格，
/// 也不需要多聪明**，但目前全跑在主对话模型上。用户挑最贵的模型聊天，
/// 结果每十条消息就用它跑一次几千 token 的记忆提炼。
///
/// 换一个便宜模型干这些，对用户看得见的那部分（聊天本身）零影响。
/// **不开的话行为跟以前完全一样**——这是加一层可选的省钱开关，不是改默认行为。
struct SubModelConfig: Equatable {
    var enabled: Bool
    var provider: AIProvider
    var model: String

    private static let enabledKey = "submodel_enabled"
    private static let providerKey = "submodel_provider"
    private static let modelKey = "submodel_model"

    static var current: SubModelConfig {
        get {
            let ud = UserDefaults.standard
            let provider = AIProvider(rawValue: ud.string(forKey: providerKey) ?? "") ?? .deepseek
            let model = ud.string(forKey: modelKey) ?? provider.defaultModel
            return SubModelConfig(enabled: ud.bool(forKey: enabledKey),
                                  provider: provider,
                                  model: model.isEmpty ? provider.defaultModel : model)
        }
        set {
            let ud = UserDefaults.standard
            ud.set(newValue.enabled, forKey: enabledKey)
            ud.set(newValue.provider.rawValue, forKey: providerKey)
            ud.set(newValue.model, forKey: modelKey)
        }
    }

    /// 真的能用吗：开了、而且那家的 Key 填了。
    /// 没填 Key 就当没开——否则每次脏活都失败，用户还以为是记忆功能坏了
    var isUsable: Bool {
        enabled && APIKeyStore.hasKey(for: provider.id)
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 这次脏活该用谁。没配好就退回主模型，行为跟以前一样
    static func resolve(fallbackProvider: AIProvider, fallbackKey: String,
                        fallbackModel: String) -> (provider: AIProvider, key: String, model: String) {
        let config = current
        guard config.isUsable else { return (fallbackProvider, fallbackKey, fallbackModel) }
        return (config.provider, APIKeyStore.key(for: config.provider.id), config.model)
    }
}
