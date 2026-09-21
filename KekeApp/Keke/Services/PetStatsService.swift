import Foundation

/// 养克克：心情 / 元气 / 亲密度三条状态。摸摸她、跟她聊天会涨；
/// 长时间不理她会慢慢往下掉。不用常驻计时器——每次读取/打开 App 时
/// 按距离上次更新过了多久"懒惰结算"一次衰减，足够给出"活着"的感觉了
@MainActor
final class PetStatsService: ObservableObject {
    let personaId: String
    @Published private(set) var mood: Double
    @Published private(set) var energy: Double
    @Published private(set) var bond: Double

    private let defaults = UserDefaults.standard
    private func key(_ base: String) -> String { "\(personaId)_pet_\(base)" }

    init(personaId: String = "keke") {
        self.personaId = personaId
        mood = (UserDefaults.standard.object(forKey: "\(personaId)_pet_mood") as? Double) ?? 80
        energy = (UserDefaults.standard.object(forKey: "\(personaId)_pet_energy") as? Double) ?? 80
        bond = (UserDefaults.standard.object(forKey: "\(personaId)_pet_bond") as? Double) ?? 30
        applyDecay()
    }

    /// 摸摸/戳戳/陪她玩：心情和元气都涨一点
    func pet() {
        mood = clamp(mood + 4)
        energy = clamp(energy + 2)
        persist()
    }

    /// 每次她回完一句聊天调用：心情和亲密度慢慢涨
    func onChatReply() {
        mood = clamp(mood + 2)
        bond = clamp(bond + 0.6)
        persist()
    }

    private func applyDecay() {
        let lastTouch = defaults.double(forKey: key("last_touch"))
        guard lastTouch > 0 else { persist(); return }
        let hours = (Date().timeIntervalSince1970 - lastTouch) / 3600
        guard hours > 1 else { return }
        mood = clamp(mood - hours * 0.8)
        energy = clamp(energy - hours * 0.5)
        persist()
    }

    private func clamp(_ v: Double) -> Double { min(100, max(0, v)) }

    private func persist() {
        defaults.set(mood, forKey: key("mood"))
        defaults.set(energy, forKey: key("energy"))
        defaults.set(bond, forKey: key("bond"))
        defaults.set(Date().timeIntervalSince1970, forKey: key("last_touch"))
    }
}
