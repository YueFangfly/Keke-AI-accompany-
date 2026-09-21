import Foundation

/// 「这个工具要执行前问一句」的闸门。
///
/// 第三方服务器给什么工具事先不知道——会删文件的、会花钱的、会往外发东西的，
/// 都可能混在里面。标了 `needsApproval` 的工具在真正执行前停下来问一次。
///
/// 超时**默认拒绝**：宁可这次没调成，也不能因为界面没弹出来就自动放行。
@MainActor
final class MCPApprovalGate: ObservableObject {
    static let shared = MCPApprovalGate()

    struct Ask: Identifiable {
        let id = UUID()
        let server: String
        let tool: String
        /// 参数按 key 排序后展示——用户要看清楚它到底要干什么
        let arguments: String
    }

    /// 界面观察这个：非 nil 就弹确认框
    @Published private(set) var pending: Ask?

    /// 没人回应就当拒绝。60 秒足够看清楚一个弹窗了
    private let timeout: TimeInterval = 60
    private var answer: CheckedContinuation<Bool, Never>?

    private init() {}

    func request(server: String, tool: String, arguments: [String: Any]) async -> Bool {
        // 同一时间只处理一个：多个工具并行调用时排队问，不叠弹窗
        while pending != nil {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let ask = Ask(server: server, tool: tool, arguments: Self.describe(arguments))
        pending = ask

        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            answer = continuation
            // 超时自动拒绝：界面没弹出来或者用户走开了，不能就这么放行
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.timeout ?? 60) * 1_000_000_000)
                guard let self, self.pending?.id == ask.id else { return }
                self.resolve(false)
            }
        }
        return granted
    }

    func resolve(_ granted: Bool) {
        guard pending != nil else { return }
        pending = nil
        answer?.resume(returning: granted)
        answer = nil
    }

    private static func describe(_ arguments: [String: Any]) -> String {
        guard !arguments.isEmpty else { return "（没有参数）" }
        return arguments.keys.sorted().map { key in
            let value = arguments[key]
            let text = (value as? String) ?? String(describing: value ?? "")
            return "\(key)：\(text.prefix(120))"
        }.joined(separator: "\n")
    }
}
