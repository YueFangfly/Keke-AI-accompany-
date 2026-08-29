import SwiftUI
import UniformTypeIdentifiers

struct FileItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String
    let size: Int64
    let modifiedDate: Date
    let isDirectory: Bool
    var suggestedCategory: String?
}

struct FileManagerView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var activityLog: ActivityLog
    @EnvironmentObject var toolAPIConfig: ToolAPIConfig
    @EnvironmentObject var customProviders: CustomProviderStore
    @State private var files: [FileItem] = []
    @State private var showPicker = false
    @State private var selectedFolder: URL?
    @State private var isCategorizing = false
    @State private var renameItem: FileItem?
    @State private var renameText = ""
    @State private var showRenameAlert = false

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(spacing: 0) {
            Text(L.t("文件管理", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 4)
            Text(L.t("查看和整理你的文件", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 14)

            if files.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("📁")
                        .font(.system(size: 44))
                    Text(L.t("选择一个文件夹开始", lang))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            } else {
                if isCategorizing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(L.t("AI 正在分析文件…", lang))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.bottom, 6)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(files) { item in
                            fileRow(item)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
            }

            HStack(spacing: 10) {
                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(Theme.accent)
                        Text(L.t("选择文件夹", lang))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .glassCard(cornerRadius: 14)
                }

                if !files.isEmpty {
                    Button {
                        categorizeFiles()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Theme.accent)
                            Text(L.t("AI 分类", lang))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .glassCard(cornerRadius: 14)
                    }
                    .disabled(isCategorizing)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .sheet(isPresented: $showPicker) {
            DocumentFolderPicker { url in
                loadFiles(from: url)
            }
        }
        .alert(L.t("重命名", lang), isPresented: $showRenameAlert) {
            TextField(L.t("新文件名", lang), text: $renameText)
            Button(L.t("取消", lang), role: .cancel) {}
            Button(L.t("确定", lang)) {
                performRename()
            }
        }
    }

    private func fileRow(_ item: FileItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(item.name))
                .font(.system(size: 22))
                .foregroundStyle(item.isDirectory ? .yellow : Theme.accent)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(formatSize(item.size))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(item.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let cat = item.suggestedCategory {
                    Text(cat)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
        .contextMenu {
            Button {
                renameItem = item
                renameText = item.name
                showRenameAlert = true
            } label: {
                Label(L.t("重命名", lang), systemImage: "pencil")
            }
        }
    }

    private func fileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "txt", "md": return "doc.text.fill"
        case "jpg", "jpeg", "png", "heic": return "photo.fill"
        case "mp4", "mov": return "film.fill"
        case "mp3", "m4a", "wav": return "music.note"
        case "swift", "py", "js", "ts": return "chevron.left.forwardslash.chevron.right"
        case "zip", "gz", "tar": return "archivebox.fill"
        default: return "doc.fill"
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    private func loadFiles(from url: URL) {
        selectedFolder = url
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]) else { return }

        files = contents.compactMap { fileURL in
            let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            return FileItem(
                url: fileURL,
                name: fileURL.lastPathComponent,
                size: Int64(resources?.fileSize ?? 0),
                modifiedDate: resources?.contentModificationDate ?? Date(),
                isDirectory: resources?.isDirectory ?? false
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        activityLog.log(.explore, "打开了文件夹，共\(files.count)个文件")
    }

    private func categorizeFiles() {
        guard !files.isEmpty else { return }
        isCategorizing = true
        let fileNames = files.map(\.name).joined(separator: "\n")
        Task {
            let instruction = """
            以下是一批文件名，请为每个文件建议一个分类标签（如"文档"、"图片"、"代码"、"音乐"、"视频"、"压缩包"、"笔记"、"其他"）。
            每行格式：文件名|分类
            不要多余的解释。

            \(fileNames)
            """
            let text = await GenerationFallback.attempt("文件助手", {
                try await ClaudeService.complete(
                instruction: instruction,
                provider: store.provider, apiKey: store.apiKey,
                model: store.model, systemPrompt: store.effectiveSystemPrompt, maxTokens: 500)
            })

            if let text {
                let lines = text.split(separator: "\n")
                for line in lines {
                    let parts = line.split(separator: "|", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let name = parts[0].trimmingCharacters(in: .whitespaces)
                    let category = parts[1].trimmingCharacters(in: .whitespaces)
                    if let idx = files.firstIndex(where: { $0.name == name }) {
                        files[idx].suggestedCategory = category
                    }
                }
            }
            isCategorizing = false
            activityLog.log(.explore, "AI 对\(files.count)个文件进行了分类")
        }
    }

    private func performRename() {
        guard let item = renameItem else { return }
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != item.name else { return }

        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        guard item.url.startAccessingSecurityScopedResource() else { return }
        defer { item.url.stopAccessingSecurityScopedResource() }

        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
            if let idx = files.firstIndex(where: { $0.id == item.id }) {
                files[idx] = FileItem(url: newURL, name: newName, size: item.size,
                                     modifiedDate: item.modifiedDate, isDirectory: item.isDirectory,
                                     suggestedCategory: item.suggestedCategory)
            }
            activityLog.log(.explore, "重命名了文件「\(item.name)」→「\(newName)」")
        } catch {}
    }
}

struct DocumentFolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
