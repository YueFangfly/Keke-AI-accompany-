import Foundation

/// 一条报错记录
struct AppErrorEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var at = Date()
    /// 哪儿出的错。用中文功能名，比如「聊天」「发朋友圈」「提炼记忆」
    var source: String
    /// 给人看的原因。APIFailure 那边已经把「Key 不对」「断网」「限流」写成人话了
    var message: String
    /// 排查用的上下文：提供方 / 模型 / 角色。没有就不显示
    var context: String?
}

/// 全 App 的报错都汇到这里。
///
/// 为什么要有这么个东西：报错原本散在各处——聊天里是一条气泡（会被后面的对话
/// 冲走）、后台任务干脆一声不吭。想把问题描述清楚给别人看的时候，
/// 只能凭记忆复述「好像说了个什么 Key 不对」。
///
/// 所以：**落盘**（App 重开还在，不然崩一次记录就没了）、**能整份复制**
/// （报问题时直接粘贴，不用手抄）、**能单条删**（清掉已经解决的，剩下的才是问题）。
final class ErrorLog: ObservableObject {
    static let shared = ErrorLog()

    @Published private(set) var entries: [AppErrorEntry] = []

    /// 最多留这么多条。够翻一阵子，又不至于把文件撑大
    private let limit = 200

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keke_error_log.json")
    }

    private init() { load() }

    // MARK: - 写

    /// 记一条。可以在任意线程调，内部会跳回主线程改数据
    func record(source: String, message: String, context: String? = nil) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 同一个来源连着报同一个错就只更新时间，不再堆一条。
            // 后台任务几分钟触发一次，一个配置错误能瞬间刷满整个列表
            if let first = self.entries.first,
               first.source == source, first.message == message {
                self.entries[0].at = Date()
                self.save()
                return
            }
            self.entries.insert(AppErrorEntry(source: source, message: message,
                                              context: context), at: 0)
            if self.entries.count > self.limit {
                self.entries.removeLast(self.entries.count - self.limit)
            }
            self.save()
        }
    }

    @MainActor
    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    @MainActor
    func delete(atOffsets offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    @MainActor
    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - 导出

    /// 整份导成纯文本，直接粘出去就能看。
    /// 时间用固定格式而不是本地化的——贴给别人时不该跟着手机区域设置变
    func exportText() -> String {
        guard !entries.isEmpty else { return "（没有报错记录）" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines = ["共 \(entries.count) 条报错记录（新的在前）", ""]
        for entry in entries {
            lines.append("[\(formatter.string(from: entry.at))] \(entry.source)")
            lines.append("  \(entry.message)")
            if let context = entry.context, !context.isEmpty {
                lines.append("  上下文：\(context)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 存取

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([AppErrorEntry].self, from: data) else { return }
        entries = saved
    }
}
