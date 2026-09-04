import Foundation

/// 卡片仓库。跟碎片、日记一样：按人设分区，一个 JSON 文件。
@MainActor
final class CardStore: ObservableObject {
    let personaId: String
    @Published private(set) var cards: [TimelineCard] = []
    /// 正在整理的碎片。界面靠它显示转圈
    @Published private(set) var working: Set<UUID> = []

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_cards.json")
    }

    init(personaId: String = "keke") {
        self.personaId = personaId
        load()
    }

    var sorted: [TimelineCard] { cards.sorted { $0.occurredAt > $1.occurredAt } }

    /// 已经被整理过的碎片。**一条碎片只整理一次**——
    /// 重复整理会在时间线上堆出一串一模一样的卡片
    var organizedFragmentIDs: Set<UUID> {
        Set(cards.flatMap(\.fragmentIDs))
    }

    func cards(forFragment id: UUID) -> [TimelineCard] {
        cards.filter { $0.fragmentIDs.contains(id) }
    }

    // MARK: - 增删改

    func add(_ card: TimelineCard) {
        // 同一条碎片已经有卡片了就不再加。并发点两下「整理」也不该出两张
        guard !card.fragmentIDs.isEmpty,
              organizedFragmentIDs.isDisjoint(with: card.fragmentIDs) else { return }
        cards.append(card)
        save()
    }

    func delete(_ id: UUID) {
        cards.removeAll { $0.id == id }
        save()
    }

    /// 卡片删掉不动碎片：碎片是原始记录，卡片只是它的一种整理方式。
    /// 删了卡片还能再整理一次，删了碎片就真没了
    func toggleDone(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].done.toggle()
        save()
    }

    func setWorking(_ id: UUID, _ busy: Bool) {
        if busy { working.insert(id) } else { working.remove(id) }
    }

    // MARK: - 持久化

    private func save() {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([TimelineCard].self, from: data) else { return }
        cards = saved
    }
}
