import SwiftUI

/// 请求日志：看每次**实际发出去了什么**。
///
/// 报错记录只记失败，可调人设时最需要的恰恰是成功那些——
/// 「我改的人设生效了没」「压缩之后历史剩下什么」「工具定义占了多少」，
/// 光看聊天界面全看不出来。
struct RequestLogView: View {
    @EnvironmentObject var store: ChatStore
    @ObservedObject private var log = RequestLog.shared
    @State private var copied: UUID?

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        Form {
            Section {
                Toggle(L.t("记录请求", lang), isOn: $log.isRecording)
                if !log.entries.isEmpty {
                    Button(L.t("清空", lang), role: .destructive) { log.clear() }
                }
            } footer: {
                Text(L.t("打开之后，每次发给模型的完整内容都会留一份在内存里：人设、记忆块、压缩后的历史、挂了哪些工具。默认是关的——这里面是最私密的那部分内容，不会落盘，关掉 App 就没了，也绝不会记 API Key。", lang))
            }

            if log.isRecording && log.entries.isEmpty {
                Section {
                    Text(L.t("还没有记录，去聊一句再回来看。", lang))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            ForEach(log.entries) { entry in
                Section {
                    header(entry)
                    block(L.t("system", lang), entry.systemPrompt.isEmpty
                          ? L.t("（空）", lang) : entry.systemPrompt)
                    block(L.count(entry.tools.count, "工具（%d）", "Tools (%d)", lang),
                          entry.tools.isEmpty ? L.t("（没挂工具）", lang)
                                              : entry.tools.joined(separator: "、"))
                    block(L.count(entry.messages.count, "messages（%d）", "Messages (%d)", lang),
                          entry.messages.joined(separator: "\n"))
                    if let reply = entry.reply {
                        block(entry.failed ? L.t("失败", lang) : L.t("回复", lang), reply)
                    }
                    Button {
                        UIPasteboard.general.string = log.exportText(entry)
                        copied = entry.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = nil }
                    } label: {
                        Label(copied == entry.id ? L.t("已复制到剪贴板", lang) : L.t("复制这一条", lang),
                              systemImage: copied == entry.id ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
    }

    private func header(_ entry: RequestLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(entry.provider) / \(entry.model)")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(entry.failed ? Theme.crabRed : Theme.textPrimary)
                Spacer()
                Text(entry.at, style: .time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                if let ms = entry.durationMs {
                    Text(UsageFormat.duration(ms))
                }
                if let usage = entry.usage, !usage.isEmpty {
                    Text("↑\(UsageFormat.tokens(usage.input + usage.cacheRead + usage.cacheWrite))"
                         + " ↓\(UsageFormat.tokens(usage.output))")
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
        }
    }

    /// 折叠起来的一段。默认收着——一次请求的内容展开能有好几屏
    private func block(_ title: String, _ body: String) -> some View {
        DisclosureGroup {
            Text(body)
                .font(.caption2.monospaced())
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
