import SwiftUI

struct CustomProviderListView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var customProviders: CustomProviderStore
    @State private var showAdd = false
    @State private var editingProvider: CustomAIProvider?
    @State private var sharingProvider: CustomAIProvider?
    @State private var showScan = false

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(spacing: 0) {
            Text(L.t("自定义 API", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 4)
            Text(L.t("添加兼容 OpenAI 格式的自定义 API 接入点", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(customProviders.providers) { cp in
                        customProviderRow(cp)
                    }

                    Button {
                        showAdd = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Theme.accent)
                            Text(L.t("添加自定义 API", lang))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .padding(14)
                        .glassCard(cornerRadius: 14)
                    }

                    // 换手机时用。备份文件刻意不含 Key，扫码补的就是那一环
                    Button {
                        showScan = true
                    } label: {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundStyle(Theme.accent)
                            Text("扫码导入")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .padding(14)
                        .glassCard(cornerRadius: 14)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)
        }
        .background(Theme.background)
        .slideOverCover(isPresented: $showAdd) {
            CustomProviderEditView(mode: .add)
                .environmentObject(store)
                .environmentObject(customProviders)
                .backButtonInset { showAdd = false }
        }
        .slideOverCover(isPresented: Binding(
            get: { editingProvider != nil },
            set: { if !$0 { editingProvider = nil } }
        )) {
            if let cp = editingProvider {
                CustomProviderEditView(mode: .edit(cp))
                    .environmentObject(store)
                    .environmentObject(customProviders)
                    .backButtonInset { editingProvider = nil }
            }
        }
        .slideOverCover(isPresented: Binding(
            get: { sharingProvider != nil },
            set: { if !$0 { sharingProvider = nil } }
        )) {
            if let cp = sharingProvider {
                ProviderQRSheet(provider: cp) { sharingProvider = nil }
                    .environmentObject(store)
            }
        }
        .slideOverCover(isPresented: $showScan) {
            ProviderScanSheet { showScan = false }
                .environmentObject(store)
                .environmentObject(customProviders)
        }
    }

    private func customProviderRow(_ cp: CustomAIProvider) -> some View {
        let isSelected = store.customProviderId == cp.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cp.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    if isSelected {
                        Text(L.t("使用中", lang))
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                }
                Text(cp.baseURL)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if cp.supportsFunctionCalling {
                        Label(L.t("工具调用", lang), systemImage: "wrench.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                    if cp.supportsVision {
                        Label(L.t("看图", lang), systemImage: "eye.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            Spacer()
            Button {
                editingProvider = cp
            } label: {
                Image(systemName: "pencil.circle")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
        .contextMenu {
            Button {
                if isSelected {
                    store.customProviderId = nil
                } else {
                    store.customProviderId = cp.id
                }
            } label: {
                Text(isSelected ? L.t("取消使用", lang) : L.t("切换到这个 API", lang))
            }
            Button {
                sharingProvider = cp
            } label: {
                Text("生成二维码")
            }
            Button(role: .destructive) {
                if store.customProviderId == cp.id { store.customProviderId = nil }
                customProviders.remove(id: cp.id)
            } label: {
                Text(L.t("删除", lang))
            }
        }
    }
}

// MARK: - Add / Edit

struct CustomProviderEditView: View {
    enum Mode {
        case add
        case edit(CustomAIProvider)
    }

    let mode: Mode
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var customProviders: CustomProviderStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var baseURL = ""
    /// 额外请求头。有的中转站要 HTTP-Referer / X-Title 之类，不给就 401 或者被限速
    @State private var headerRows: [HeaderRow] = []
    /// 额外请求体字段，JSON 文本
    @State private var extraBodyJSON = ""
    @State private var defaultModel = ""
    @State private var keyPlaceholder = "sk-…"
    @State private var supportsVision = false
    @State private var supportsFunctionCalling = true
    @State private var apiKey = ""

    private var lang: AppLanguage { store.appLanguage }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isEditing ? L.t("编辑自定义 API", lang) : L.t("添加自定义 API", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 12) {
                    field(label: L.t("名称", lang), placeholder: "My API", text: $name)
                    field(label: "API URL", placeholder: "https://api.example.com/v1/chat/completions", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    field(label: L.t("默认模型", lang), placeholder: "gpt-4o", text: $defaultModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    field(label: "API Key", placeholder: keyPlaceholder, text: $apiKey, isSecure: true)
                    advancedFields

                    VStack(spacing: 8) {
                        Toggle(L.t("支持工具调用（Function Calling）", lang), isOn: $supportsFunctionCalling)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        Toggle(L.t("支持看图（Vision）", lang), isOn: $supportsVision)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 14)

                    Text(L.t("自定义 API 使用 OpenAI 兼容格式（Chat Completions）。大多数国产模型（如通义千问、百川、零一万物等）都兼容这个格式。", lang))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 4)

                    Button {
                        saveProvider()
                    } label: {
                        Text(L.t("保存", lang))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(canSave ? Theme.accent : Theme.textSecondary.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canSave)

                    if isEditing {
                        Button(role: .destructive) {
                            if case .edit(let cp) = mode {
                                if store.customProviderId == cp.id { store.customProviderId = nil }
                                customProviders.remove(id: cp.id)
                            }
                            dismiss()
                        } label: {
                            Text(L.t("删除这个 API", lang))
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
        .onAppear {
            if case .edit(let cp) = mode {
                name = cp.name
                baseURL = cp.baseURL
                extraBodyJSON = cp.extraBodyJSON
                let stored = CustomProviderStore.headers(for: cp.id, names: cp.headerNames)
                headerRows = cp.headerNames.sorted().map { HeaderRow(key: $0, value: stored[$0] ?? "") }
                defaultModel = cp.defaultModel
                keyPlaceholder = cp.keyPlaceholder
                supportsVision = cp.supportsVision
                supportsFunctionCalling = cp.supportsFunctionCalling
                apiKey = APIKeyStore.key(for: cp.id)
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func field(label: String, placeholder: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if isSecure {
                SecureField(placeholder, text: text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            } else {
                TextField(placeholder, text: text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    struct HeaderRow: Identifiable { let id = UUID(); var key = ""; var value = "" }

    /// JSON 填对了没。空的算对；错的当场标出来，别等聊天时才发现
    private var extraBodyProblem: String? {
        let trimmed = extraBodyJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] != nil else {
            return L.t("这段 JSON 有问题，会被忽略", lang)
        }
        return nil
    }

    @ViewBuilder
    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("额外请求头（可选）", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            ForEach($headerRows) { $row in
                HStack(spacing: 6) {
                    TextField("Header", text: $row.key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(width: 110)
                    SecureField(L.t("值", lang), text: $row.value)
                }
                .font(.caption.monospaced())
                .padding(8)
                .glassCard(cornerRadius: 8)
            }
            Button(L.t("加一行请求头", lang)) { headerRows.append(HeaderRow()) }
                .font(.caption)

            Text(L.t("额外请求体字段（可选，JSON）", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            TextEditor(text: $extraBodyJSON)
                .font(.caption.monospaced())
                .frame(minHeight: 60)
                .scrollContentBackground(.hidden)
                .padding(6)
                .glassCard(cornerRadius: 8)
            if let extraBodyProblem {
                Text(extraBodyProblem).font(.caption2).foregroundStyle(.orange)
            }
            Text(L.t("这两样都是接中转站用的。请求头的值存在钥匙串里，不会进备份文件；请求体字段会并进每次请求，同名的会覆盖默认值。", lang))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func saveProvider() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }

        if case .edit(var cp) = mode {
            cp.name = trimmedName
            cp.baseURL = trimmedURL
            cp.defaultModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
            cp.keyPlaceholder = keyPlaceholder
            cp.supportsVision = supportsVision
            cp.supportsFunctionCalling = supportsFunctionCalling
            cp.headerNames = persistHeaders(for: cp.id)
            cp.extraBodyJSON = extraBodyJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            customProviders.update(cp)
            if !apiKey.isEmpty {
                APIKeyStore.setKey(apiKey, for: cp.id)
            }
        } else {
            let cp = CustomAIProvider(name: trimmedName, baseURL: trimmedURL,
                                      defaultModel: defaultModel.trimmingCharacters(in: .whitespacesAndNewlines),
                                      keyPlaceholder: keyPlaceholder,
                                      supportsVision: supportsVision,
                                      supportsFunctionCalling: supportsFunctionCalling)
            var created = cp
            created.headerNames = persistHeaders(for: cp.id)
            created.extraBodyJSON = extraBodyJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            customProviders.add(created)
            if !apiKey.isEmpty {
                APIKeyStore.setKey(apiKey, for: cp.id)
            }
        }
        dismiss()
    }

    /// 把 header 的值写进 Keychain，返回键名列表（键名才进配置）
    private func persistHeaders(for providerID: String) -> [String] {
        var names: [String] = []
        for row in headerRows {
            let key = row.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            CustomProviderStore.setHeader(row.value, name: key, for: providerID)
            names.append(key)
        }
        return names
    }
}
