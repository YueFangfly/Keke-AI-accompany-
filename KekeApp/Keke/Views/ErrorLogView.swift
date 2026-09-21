import SwiftUI

/// 报错记录页。
///
/// 全 App 的报错都汇到这里：聊天报错、后台生成失败、各页面上的失败。
/// 三件事是这一页存在的理由——
/// **看得见**（后台失败原本一声不吭）、
/// **删得掉**（长按删单条，解决了的清掉，剩下的才是问题）、
/// **抄得走**（整份复制，报问题时直接粘贴，不用照着屏幕手打）。
struct ErrorLogView: View {
    @EnvironmentObject var store: ChatStore
    @ObservedObject private var log = ErrorLog.shared

    @State private var copied = false
    @State private var showClearConfirm = false

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        Group {
            if log.entries.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(Theme.background)
        .tint(Theme.accent)
        .confirmationDialog(L.t("确定要清空所有报错记录吗？", lang),
                            isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(L.t("清空", lang), role: .destructive) { log.clear() }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 34))
                .foregroundStyle(Theme.textSecondary)
            Text(L.t("目前没有报错", lang))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Text(L.t("出问题的时候会自动记到这里——包括那些在后台悄悄失败、界面上看不见的。", lang))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            Section {
                Button {
                    UIPasteboard.general.string = log.exportText()
                    copied = true
                    // 提示两秒后自己收回去，不用再点一下
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? L.t("已复制到剪贴板", lang)
                                 : L.count(log.entries.count, "复制全部 %d 条", "Copy all %d entries", lang),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button(L.t("清空全部", lang), role: .destructive) { showClearConfirm = true }
            } footer: {
                Text(L.t("复制出来是纯文本，直接粘贴就能看。长按某一条可以单独删掉，左滑也行。", lang))
            }

            Section {
                ForEach(log.entries) { entry in
                    row(entry)
                        // 长按删单条：解决掉的清走，剩下的才是还没解决的
                        .contextMenu {
                            Button(role: .destructive) {
                                log.delete(entry.id)
                            } label: {
                                Label(L.t("删掉这条", lang), systemImage: "trash")
                            }
                            Button {
                                UIPasteboard.general.string = singleText(entry)
                            } label: {
                                Label(L.t("只复制这条", lang), systemImage: "doc.on.doc")
                            }
                        }
                }
                .onDelete { log.delete(atOffsets: $0) }
            } header: {
                Text(L.count(log.entries.count, "共 %d 条", "%d entries", lang))
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ entry: AppErrorEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.source)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(entry.at, format: .dateTime.month().day().hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(entry.message)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let context = entry.context, !context.isEmpty {
                Text(context)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
        }
        .padding(.vertical, 2)
        // 单条也能选中复制，不想长按的时候直接划词
        .textSelection(.enabled)
    }

    private func singleText(_ entry: AppErrorEntry) -> String {
        var parts = ["\(entry.source)：\(entry.message)"]
        if let context = entry.context, !context.isEmpty { parts.append("上下文：\(context)") }
        return parts.joined(separator: "\n")
    }
}
