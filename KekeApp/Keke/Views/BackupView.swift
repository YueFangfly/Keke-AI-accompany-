import SwiftUI
import UniformTypeIdentifiers

/// 备份导出 / 恢复页。
///
/// 恢复分两步，中间隔一次启动：这里只负责把备份解出来放好，
/// 真正的替换在 `KekeApp.init()` 里做——早于任何 Store 的构造。
/// 不这样做的话，内存里还拿着旧数据的 Store 一存盘就把恢复的内容盖回去了。
struct BackupView: View {
    @EnvironmentObject var store: ChatStore

    @State private var includeMedia = true
    @State private var estimated: Int?
    @State private var working = false
    @State private var result: BackupService.Result?
    @State private var failure: String?

    @State private var showImporter = false
    @State private var pendingURL: URL?
    @State private var pendingManifest: BackupService.Manifest?
    @State private var restoreReport: BackupService.RestoreReport?
    @State private var restorePending = BackupService.hasPendingRestore

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        Form {
            optionsSection
            actionSection
            if let result { resultSection(result) }
            restoreSection
            scopeSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
        .task(id: includeMedia) { await refreshEstimate() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item]) { outcome in
            guard case .success(let url) = outcome else { return }
            do {
                pendingManifest = try BackupService.inspect(url)
                pendingURL = url
            } catch {
                failure = error.localizedDescription
            }
        }
        .confirmationDialog(restoreConfirmTitle,
                            isPresented: restoreConfirmBinding,
                            titleVisibility: .visible) {
            Button(L.t("覆盖并恢复", lang), role: .destructive) {
                Task { await applyRestore() }
            }
            Button(L.t("取消", lang), role: .cancel) { clearPending() }
        } message: {
            Text(L.t("恢复会用备份里的内容覆盖现在的聊天记录、记忆和设置。当前数据会先挪到一边保留一份，但强烈建议你先导出一次备份再恢复。", lang))
        }
    }

    // MARK: - 选项

    private var optionsSection: some View {
        Section {
            Toggle(L.t("包含图片和音频", lang), isOn: $includeMedia)
            HStack {
                Text(L.t("预计大小", lang))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let estimated {
                    Text(BackupService.humanSize(estimated))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ProgressView()
                }
            }
        } header: {
            Text(L.t("备份内容", lang))
        } footer: {
            Text(L.t("聊天记录、记忆、朋友圈、日记、经期、书、贴纸清单和全部偏好设置都会打包进去。图片和音频体积大得多，不需要的话可以关掉。", lang))
        }
    }

    // MARK: - 生成

    @ViewBuilder
    private var actionSection: some View {
        Section {
            Button {
                Task { await run() }
            } label: {
                HStack {
                    Text(L.t("生成备份文件", lang))
                        .foregroundStyle(working ? Theme.textSecondary : Theme.accent)
                    Spacer()
                    if working { ProgressView() }
                }
            }
            .disabled(working)

            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(Theme.crabRed)
            }
        }
    }

    private func resultSection(_ result: BackupService.Result) -> some View {
        Section {
            ShareLink(item: result.url) {
                Label(L.t("保存或分享备份", lang), systemImage: "square.and.arrow.up")
            }
            LabeledContent(L.t("文件名", lang)) {
                Text(result.url.lastPathComponent)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            LabeledContent(L.t("收进来的文件", lang)) {
                Text("\(result.manifest.fileCount)")
                    .font(.subheadline.monospacedDigit())
            }
            if !result.manifest.skipped.isEmpty {
                LabeledContent(L.t("跳过的文件", lang)) {
                    Text("\(result.manifest.skipped.count)")
                        .font(.subheadline.monospacedDigit())
                }
            }
        } header: {
            Text(L.t("已生成", lang))
        } footer: {
            Text(L.t("这个文件放在临时目录里，系统随时可能清掉。生成之后请马上「保存或分享」存到「文件」App 或者别的地方。单个超过 25 MB 的文件会被跳过。", lang))
        }
    }

    // MARK: - 恢复

    @ViewBuilder
    private var restoreSection: some View {
        Section {
            if restorePending {
                Label(L.t("已经准备好一份恢复，完全退出 App 再打开就会生效", lang),
                      systemImage: "arrow.clockwise.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                Button(L.t("取消这次恢复", lang), role: .destructive) {
                    BackupService.cancelPendingRestore()
                    restorePending = false
                    restoreReport = nil
                }
            } else {
                Button {
                    failure = nil
                    showImporter = true
                } label: {
                    Label(L.t("从备份恢复", lang), systemImage: "square.and.arrow.down")
                }
            }
            if let restoreReport, restorePending {
                LabeledContent(L.t("待恢复的文件", lang)) {
                    Text("\(restoreReport.staged)")
                        .font(.subheadline.monospacedDigit())
                }
                if !restoreReport.rejected.isEmpty {
                    LabeledContent(L.t("被拒绝的条目", lang)) {
                        Text("\(restoreReport.rejected.count)")
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
        } header: {
            Text(L.t("恢复", lang))
        } footer: {
            Text(L.t("恢复分两步：先把备份解出来放好，然后在下次启动时、任何数据被读进内存之前替换掉。不这样做的话，App 里还拿着旧数据的部分会立刻把刚恢复的内容盖回去。所以选完之后需要你把 App 从后台完全划掉再打开。", lang))
        }
    }

    private var restoreConfirmTitle: String {
        guard let m = pendingManifest else { return L.t("从备份恢复", lang) }
        let when = DateFormatter.localizedString(from: m.createdAt, dateStyle: .medium, timeStyle: .short)
        return "\(when) · \(m.fileCount) 个文件 · \(BackupService.humanSize(m.totalBytes))"
    }

    private var restoreConfirmBinding: Binding<Bool> {
        Binding(get: { pendingManifest != nil && pendingURL != nil },
                set: { if !$0 { clearPending() } })
    }

    private func clearPending() {
        pendingURL = nil
        pendingManifest = nil
    }

    private func applyRestore() async {
        guard let url = pendingURL else { return }
        working = true
        failure = nil
        do {
            restoreReport = try await Task.detached(priority: .userInitiated) {
                try BackupService.stageRestore(from: url)
            }.value
            restorePending = true
        } catch {
            failure = error.localizedDescription
        }
        clearPending()
        working = false
    }

    // MARK: - 说明

    private var scopeSection: some View {
        Section(L.t("说明", lang)) {
            Text(L.t("备份里不包含 API Key。Key 存在系统钥匙串里，备份读不到；偏好设置那部分也按名字过滤了一遍。换手机之后 Key 需要重新填。", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(L.t("恢复只认这个 App 导出的备份文件；格式版本比当前 App 新的读不了。", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - 动作

    private func refreshEstimate() async {
        estimated = nil
        let include = includeMedia
        estimated = await Task.detached(priority: .userInitiated) {
            BackupService.estimatedSize(includeMedia: include)
        }.value
    }

    private func run() async {
        working = true
        failure = nil
        result = nil
        let include = includeMedia
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try BackupService.export(includeMedia: include)
            }.value
        } catch {
            failure = error.localizedDescription
        }
        working = false
    }
}
