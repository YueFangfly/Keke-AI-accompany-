import Foundation
import UIKit

/// 碎片仓库。按人设分区，跟日记一样一个 JSON 文件。
///
/// 有意做得很薄：**记的时候不做任何判断**。要不要整理成卡片、该整理成什么，
/// 是后面阶段的事。这里只保证「扔进来的东西一条都不会丢」。
@MainActor
final class FragmentStore: ObservableObject {
    let personaId: String
    @Published private(set) var fragments: [Fragment] = []
    /// 正在分析的那几条。界面靠它显示一个小转圈
    @Published private(set) var analyzing: Set<UUID> = []

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_fragments.json")
    }

    init(personaId: String = "keke") {
        self.personaId = personaId
        load()
    }

    /// 按「这条讲的是什么时候的事」倒序，不是按记录时间——
    /// 昨天拍的照片今天补记，它该排在昨天
    var sorted: [Fragment] { fragments.sorted { $0.occurredAt > $1.occurredAt } }

    /// 分天。返回的是 [(那天的零点, 那天的碎片)]，已经按天倒序
    var byDay: [(day: Date, items: [Fragment])] {
        let calendar = Calendar.current
        var buckets: [Date: [Fragment]] = [:]
        for fragment in fragments {
            let day = calendar.startOfDay(for: fragment.occurredAt)
            buckets[day, default: []].append(fragment)
        }
        return buckets
            .map { (day: $0.key, items: $0.value.sorted { $0.occurredAt > $1.occurredAt }) }
            .sorted { $0.day > $1.day }
    }

    var todayCount: Int {
        fragments.filter { Calendar.current.isDateInToday($0.occurredAt) }.count
    }

    // MARK: - 记

    @discardableResult
    func addText(_ text: String) -> Fragment? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fragment = Fragment(kind: .text, text: trimmed)
        fragments.append(fragment)
        save()
        return fragment
    }

    /// 说出来的一句。转写已经在录的时候做完了，这里只负责存
    @discardableResult
    func addVoice(transcript: String) -> Fragment? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fragment = Fragment(kind: .voice, text: trimmed)
        fragments.append(fragment)
        save()
        return fragment
    }

    /// 存一张照片，然后**在后台把它读一遍**。
    ///
    /// `original` 是相册给的原始数据，不能省：`Attachments.saveImage` 重编码之后
    /// EXIF 就没了，拍摄时间和 GPS 必须在那之前读。
    ///
    /// 分析失败不影响碎片存在——照片先落地，读不读得懂是另一回事。
    func addPhoto(_ image: UIImage, original: Data?, text: String = "") {
        guard let path = Attachments.saveImage(image) else {
            ErrorLog.shared.record(source: "碎片", message: "照片存不下来，可能是空间满了")
            return
        }
        var fragment = Fragment(kind: .photo, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        fragment.imagePath = path
        fragments.append(fragment)
        save()

        let id = fragment.id
        analyzing.insert(id)
        Task { [weak self] in
            let analysis = await MediaUnderstanding.analyzePhoto(original: original, image: image)
            guard let self else { return }
            self.applyAnalysis(analysis, to: id)
        }
    }

    /// 补分析：老碎片、或者上次失败的，可以再来一次
    func reanalyze(_ fragment: Fragment) {
        guard let path = fragment.imagePath,
              let image = Attachments.loadImage(named: path) else { return }
        let id = fragment.id
        guard !analyzing.contains(id) else { return }
        analyzing.insert(id)
        Task { [weak self] in
            // 重来一次读不到 EXIF：原始数据早就没了，只剩下压缩过的那份。
            // 标签和文字还是能重新认的
            let analysis = await MediaUnderstanding.analyzePhoto(original: nil, image: image)
            guard let self else { return }
            self.applyAnalysis(analysis, to: id)
        }
    }

    private func applyAnalysis(_ analysis: MediaAnalysis, to id: UUID) {
        analyzing.remove(id)
        guard let index = fragments.firstIndex(where: { $0.id == id }) else { return }
        // 保住上一次读到的拍摄时间和 GPS：重新分析拿不到原始数据，
        // 直接覆盖会把已经读对的信息抹掉
        var merged = analysis
        if merged.capturedAt == nil { merged.capturedAt = fragments[index].analysis?.capturedAt }
        if merged.latitude == nil || merged.longitude == nil {
            merged.latitude = fragments[index].analysis?.latitude
            merged.longitude = fragments[index].analysis?.longitude
        }
        fragments[index].analysis = merged
        if let failure = merged.failure {
            ErrorLog.shared.record(source: "碎片·读图", message: failure)
        }
        save()
    }

    // MARK: - 改 / 删

    func updateText(_ text: String, for id: UUID) {
        guard let index = fragments.firstIndex(where: { $0.id == id }) else { return }
        fragments[index].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func delete(_ id: UUID) {
        guard let index = fragments.firstIndex(where: { $0.id == id }) else { return }
        // 图跟着碎片一起走。留在 attachments 里就是永远不会有人再看的死文件
        if let path = fragments[index].imagePath {
            try? FileManager.default.removeItem(at: Attachments.dir.appendingPathComponent(path))
        }
        fragments.remove(at: index)
        analyzing.remove(id)
        save()
    }

    // MARK: - 持久化

    private func save() {
        guard let data = try? JSONEncoder().encode(fragments) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([Fragment].self, from: data) else { return }
        fragments = saved
    }
}
