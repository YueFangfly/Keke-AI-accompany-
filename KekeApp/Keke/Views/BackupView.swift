import SwiftUI

/// 备份导出页。
///
/// 只做导出，不做恢复——恢复要把十几个 Store 的内存状态一起换掉，
/// 弄不好会把现有数据覆盖没了，那是单独一件事。
/// 导出的文件格式是自描述的（第一行清单里写了版本），以后做恢复能直接读。
struct BackupView: View {
    @EnvironmentObject var store: ChatStore

    @State private var includeMedia = true
    @State private var estimated: Int?
    @State private var working = false
    @State private var result: BackupService.Result?
    @State private var failure: String?

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        Form {
            optionsSection
            actionSection
            if let result { resultSection(result) }
            scopeSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
        .task(id: includeMedia) { await refreshEstimate() }
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

    // MARK: - 说明

    private var scopeSection: some View {
        Section(L.t("说明", lang)) {
            Text(L.t("备份里不包含 API Key。Key 存在系统钥匙串里，备份读不到；偏好设置那部分也按名字过滤了一遍。换手机之后 Key 需要重新填。", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(L.t("目前只能导出，还不能从备份恢复。备份文件第一行写了格式版本，以后做恢复功能能直接读现在这份。", lang))
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
