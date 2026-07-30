import SwiftUI

struct CustomProviderListView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var customProviders: CustomProviderStore
    @State private var showAdd = false
    @State private var editingProvider: CustomAIProvider?

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
                defaultModel = cp.defaultModel
                keyPlaceholder = cp.keyPlaceholder
                supportsVision = cp.supportsVision
                supportsFunctionCalling = cp.supportsFunctionCalling
                let keys = UserDefaults.standard.dictionary(forKey: "ai_api_keys") as? [String: String] ?? [:]
                apiKey = keys[cp.id] ?? ""
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
            customProviders.update(cp)
            if !apiKey.isEmpty {
                var keys = UserDefaults.standard.dictionary(forKey: "ai_api_keys") as? [String: String] ?? [:]
                keys[cp.id] = apiKey
                UserDefaults.standard.set(keys, forKey: "ai_api_keys")
            }
        } else {
            let cp = CustomAIProvider(name: trimmedName, baseURL: trimmedURL,
                                      defaultModel: defaultModel.trimmingCharacters(in: .whitespacesAndNewlines),
                                      keyPlaceholder: keyPlaceholder,
                                      supportsVision: supportsVision,
                                      supportsFunctionCalling: supportsFunctionCalling)
            customProviders.add(cp)
            if !apiKey.isEmpty {
                var keys = UserDefaults.standard.dictionary(forKey: "ai_api_keys") as? [String: String] ?? [:]
                keys[cp.id] = apiKey
                UserDefaults.standard.set(keys, forKey: "ai_api_keys")
            }
        }
        dismiss()
    }
}
