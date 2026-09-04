import SwiftUI

/// 记忆导出页。
///
/// 之前只有两个极端：资料页那个「导出记忆」只吐正文，元数据全丢；
/// 完整备份倒是什么都有，但那是个 SQLite 库，能恢复不能读。
/// 这一页补中间那一档，而且**一次导所有人**。
struct MemoryExportView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var memory: MemoryService
    @EnvironmentObject var contacts: ContactsStore
    var onClose: () -> Void

    enum Format: String, CaseIterable, Identifiable {
        case markdown, json
        var id: String { rawValue }
        var title: String { self == .markdown ? "Markdown" : "JSON" }
        var ext: String { self == .markdown ? "md" : "json" }
        var blurb: String {
            switch self {
            case .markdown: return "给人看的。按人分组、按重要度分段，时间和分类跟在每条下面"
            case .json: return "给机器读的。带完整元数据，能从这个 App 导回去"
            }
        }
    }

    @State private var format: Format = .markdown
    @State private var file: URL?
    @State private var problem: String?

    private var entries: [MemoryEntry] { memory.memories }
    private var names: [String: String] {
        Dictionary(contacts.contacts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("导出记忆")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 18)

                summary
                picker
                actions

                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(Theme.crabRed)
                        .multilineTextAlignment(.center)
                }

                footnote
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .backButtonInset(onBack: onClose)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("共 \(entries.count) 条")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            ForEach(MemoryExport.grouped(entries), id: \.contact) { group in
                Text("\(names[group.contact] ?? group.contact)：\(group.items.count) 条")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $format) {
                ForEach(Format.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: format) { _ in file = nil }

            Text(format.blurb)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let file {
            ShareLink(item: file) {
                Text("分享这份导出")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
            }
            Text(file.lastPathComponent)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        } else {
            Button(action: build) {
                Text("生成")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
            }
            .disabled(entries.isEmpty)
            .opacity(entries.isEmpty ? 0.4 : 1)
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("JSON 这份可以从「聊天列表 → 点头像 → 导入记忆」读回来，分类、重要度、情绪值、还悬着没有都会一起还原。文件里写的那个人当前还在就还给他，不在了就落到你导入的那个人身上。")
            Text("「被想起过几次」和「已归档」只写进文件给你看，不还原——那两个该由这台设备自己攒。")
            Text("这份导出不含 API Key，跟完整备份一样。")
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.caption2)
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func build() {
        problem = nil
        let now = Date()
        let data: Data?
        switch format {
        case .markdown:
            data = MemoryExport.markdown(entries, names: names, exportedAt: now).data(using: .utf8)
        case .json:
            data = MemoryExport.jsonData(entries, exportedAt: now)
        }
        guard let data else {
            problem = "生成不出来，记忆里可能有读不了的内容"
            ErrorLog.shared.record(source: "导出记忆", message: "序列化失败（\(format.ext)）")
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(MemoryExport.fileName(format.ext, at: now))
        do {
            try data.write(to: url, options: .atomic)
            file = url
        } catch {
            problem = error.localizedDescription
            ErrorLog.shared.record(source: "导出记忆", message: error.localizedDescription)
        }
    }
}
