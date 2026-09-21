import SwiftUI

/// 存储空间：哪些东西占地方，可以单独删。
///
/// `attachments/` 这类目录**只进不出**——发过的每张图都留着，聊久了会悄悄涨到几个 G，
/// 而 iOS 的「App 存储」只给一个总数，看不出是什么占的。
struct StorageView: View {
    @EnvironmentObject var store: ChatStore

    @State private var groups: [StorageScanner.Group] = []
    @State private var scanning = true
    @State private var pendingDelete: StorageScanner.Group?

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        Group {
            if scanning {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .background(Theme.background)
        .tint(Theme.accent)
        .task { await rescan() }
        .confirmationDialog(
            pendingDelete.map {
                String(format: L.t("确定删掉「%@」吗？这个操作撤不回来。", lang), $0.name)
            } ?? "",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible) {
            Button(L.t("删除", lang), role: .destructive) {
                if let group = pendingDelete { StorageScanner.delete(group) }
                pendingDelete = nil
                Task { await rescan() }
            }
        }
    }

    private var list: some View {
        Form {
            Section {
                HStack {
                    Text(L.t("合计", lang)).font(.subheadline.weight(.medium))
                    Spacer()
                    Text(BackupService.humanSize(groups.reduce(0) { $0 + $1.bytes }))
                        .font(.subheadline.monospacedDigit())
                }
            } footer: {
                Text(L.t("只统计 App 自己存的东西。聊天记录和记忆通常很小，占地方的基本都是图片和音频。删之前建议先导出一次备份。", lang))
            }

            ForEach(groups) { group in
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name).font(.subheadline)
                            Text(L.count(group.fileCount, "%d 个文件", "%d files", lang))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text(BackupService.humanSize(group.bytes))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if group.deletable && group.bytes > 0 {
                        Button(L.t("清掉这些", lang), role: .destructive) { pendingDelete = group }
                    }
                } footer: {
                    Text(L.t(group.note, lang)).font(.caption2)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func rescan() async {
        scanning = true
        groups = await Task.detached(priority: .userInitiated) { StorageScanner.scan() }.value
        scanning = false
    }
}

/// 扫目录算体积。跟备份那边共用同一套「哪些文件属于 App」的认知——
/// `BackupService.inventory()` 已经把这件事想清楚了，不再重复一遍
enum StorageScanner {
    struct Group: Identifiable, Equatable {
        let id: String
        let name: String
        let note: String
        let bytes: Int
        let fileCount: Int
        /// 能不能删。聊天记录和记忆不给删——那是数据不是缓存，
        /// 要删也该走「清空聊天记录」那种带确认的正经入口
        let deletable: Bool
        let paths: [String]
    }

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func scan() -> [Group] {
        let all = BackupService.inventory(includeMedia: true)
        var buckets: [(id: String, name: String, note: String, deletable: Bool, match: (String) -> Bool)] = [
            ("attachments", "聊天图片和文件", "发过的图片和文件。删了聊天记录里那些图会显示不出来，文字还在。", true,
             { $0.hasPrefix("attachments/") }),
            ("audio", "音频", "录音和合成的语音。删了不影响聊天记录。", true,
             { $0.hasPrefix("Audio/") }),
            ("stickers", "自定义表情", "自己加的表情图。", true,
             { $0.hasPrefix("Stickers/") }),
            ("chat", "聊天记录", "对话本身。要清请走「设置 → 聊天记录 → 清空」，那里有确认。", false,
             { $0.hasSuffix("_chat.jsonl") || $0.hasSuffix("_chat.json") || $0.hasPrefix("chat_") }),
            ("memory", "记忆", "记忆库。要清请走「设置 → 清空所有记忆」。", false,
             { $0.contains("_memory") }),
        ]
        // 剩下的（朋友圈、日记、经期、书、偏好…）归一类，都很小，不单独给删除入口
        buckets.append(("other", "其它数据", "朋友圈、日记、经期、书这些。通常只有几百 KB。", false, { _ in true }))

        var used = Set<String>()
        var groups: [Group] = []
        for bucket in buckets {
            let paths = all.filter { !used.contains($0) && bucket.match($0) }
            used.formUnion(paths)
            let bytes = paths.reduce(0) { sum, path in
                let url = documents.appendingPathComponent(path)
                return sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            guard bytes > 0 || !paths.isEmpty else { continue }
            groups.append(Group(id: bucket.id, name: bucket.name, note: bucket.note,
                                bytes: bytes, fileCount: paths.count,
                                deletable: bucket.deletable, paths: paths))
        }
        return groups.sorted { $0.bytes > $1.bytes }
    }

    static func delete(_ group: Group) {
        guard group.deletable else { return }
        let fm = FileManager.default
        for path in group.paths {
            try? fm.removeItem(at: documents.appendingPathComponent(path))
        }
    }
}
