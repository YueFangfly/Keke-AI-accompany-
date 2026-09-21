import SwiftUI

/// 选一家搜索服务。
///
/// Claude 有官方的 `web_search`，但**换到 DeepSeek / GPT 就完全没有搜索了**。
/// 在这里配一家之后，用哪个模型都能搜；配好了官方那个就不再重复挂。
struct SearchSettingsView: View {
    @EnvironmentObject var store: ChatStore

    @State private var selectedID: String?
    @State private var enabled = true
    @State private var keyDraft = ""
    @State private var baseURLDraft = ""
    /// 试搜的结果：nil 是没试过
    @State private var testResult: String?
    @State private var testing = false

    private var lang: AppLanguage { store.appLanguage }
    private var selectedType: (any SearchProvider.Type)? {
        selectedID.flatMap { SearchSettings.provider(for: $0) }
    }

    var body: some View {
        Form {
            Section {
                Toggle(L.t("启用外部搜索", lang), isOn: $enabled)
                    .onChange(of: enabled) { SearchSettings.enabled = $0 }
            } footer: {
                Text(L.t("Claude 自带搜索，别的模型没有。在这里配一家之后，用哪个模型都能搜。配好了就用你选的这家，不再重复挂 Claude 官方那个。", lang))
            }

            Section(L.t("用哪家", lang)) {
                ForEach(SearchSettings.all.indices, id: \.self) { index in
                    let type = SearchSettings.all[index]
                    Button {
                        pick(type.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.displayName)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(type.keyHint)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if selectedID == type.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }

            if let type = selectedType {
                Section {
                    if type.needsKey {
                        SecureField(L.t("API Key", lang), text: $keyDraft)
                            .onChange(of: keyDraft) { SearchSettings.setKey($0, for: type.id) }
                    }
                    if type.needsBaseURL {
                        TextField("https://searx.example.com", text: $baseURLDraft)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.subheadline.monospaced())
                            .onChange(of: baseURLDraft) { SearchSettings.setBaseURL($0, for: type.id) }
                    }
                    Button {
                        Task { await runTest(type) }
                    } label: {
                        HStack {
                            Text(L.t("试搜一下", lang))
                            Spacer()
                            if testing { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(testing || !SearchSettings.isReady)
                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(type.displayName)
                } footer: {
                    Text(L.t("Key 存在系统钥匙串里，跟模型的 API Key 一个待遇，不会进备份文件。「试搜一下」会真的发一次请求，确认配置能用。", lang))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
        .onAppear(perform: load)
    }

    private func load() {
        selectedID = SearchSettings.selectedID
        enabled = SearchSettings.enabled
        if let id = selectedID {
            keyDraft = SearchSettings.key(for: id)
            baseURLDraft = SearchSettings.baseURL(for: id)
        }
    }

    private func pick(_ id: String) {
        selectedID = id
        SearchSettings.selectedID = id
        // 换一家就把草稿换成那家自己的，别把上一家的 key 显示在这儿
        keyDraft = SearchSettings.key(for: id)
        baseURLDraft = SearchSettings.baseURL(for: id)
        testResult = nil
    }

    /// 真发一次请求。配置对不对，只有试过才知道——
    /// 不试的话要等到聊天里模型调搜索失败才发现
    private func runTest(_ type: any SearchProvider.Type) async {
        testing = true
        testResult = nil
        do {
            let results = try await type.init().search(
                "hello", limit: 3,
                key: SearchSettings.key(for: type.id),
                baseURL: SearchSettings.baseURL(for: type.id))
            testResult = results.isEmpty
                ? L.t("能连上，但没搜到结果", lang)
                : L.count(results.count, "好了，搜到 %d 条", "Works — %d results", lang)
        } catch {
            testResult = error.localizedDescription
        }
        testing = false
    }
}
