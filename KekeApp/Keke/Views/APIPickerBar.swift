import SwiftUI

struct APIPickerBar: View {
    let moduleId: String
    @EnvironmentObject var toolAPIConfig: ToolAPIConfig
    @EnvironmentObject var customProviders: CustomProviderStore
    @EnvironmentObject var store: ChatStore

    @State private var showPicker = false

    private var lang: AppLanguage { store.appLanguage }

    private var entry: ToolAPIEntry {
        toolAPIConfig.entry(for: moduleId)
    }

    private var displayName: String {
        if let customId = entry.customProviderId,
           let cp = customProviders.provider(for: customId) {
            return cp.name
        }
        return entry.builtInProvider?.displayName ?? entry.providerRaw
    }

    private var modelName: String {
        let m = entry.model
        if m.isEmpty { return entry.builtInProvider?.defaultModel ?? "" }
        return m
    }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text(displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(shortenModel(modelName))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.textSecondary.opacity(0.15), lineWidth: 0.5))
        }
        .slideOverCover(isPresented: $showPicker) {
            ToolAPIPickerView(moduleId: moduleId)
                .environmentObject(toolAPIConfig)
                .environmentObject(customProviders)
                .environmentObject(store)
                .backButtonInset { showPicker = false }
        }
    }

    private func shortenModel(_ model: String) -> String {
        if model.count > 20 {
            return String(model.prefix(18)) + "…"
        }
        return model
    }
}

// MARK: - Full Picker View

struct ToolAPIPickerView: View {
    let moduleId: String
    @EnvironmentObject var toolAPIConfig: ToolAPIConfig
    @EnvironmentObject var customProviders: CustomProviderStore
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProviderRaw: String = ""
    @State private var selectedCustomId: String?
    @State private var model: String = ""
    @State private var apiKey: String = ""

    private var lang: AppLanguage { store.appLanguage }

    private var selectedBuiltIn: AIProvider? {
        guard selectedCustomId == nil else { return nil }
        return AIProvider(rawValue: selectedProviderRaw)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L.t("选择 API", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 4)
            Text(L.t("为这个工具单独选一个 API，不影响聊天主模型", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 10) {
                    VStack(spacing: 0) {
                        ForEach(AIProvider.allCases) { p in
                            providerRow(name: p.displayName, tag: p.rawValue, isCustom: false)
                        }
                    }
                    .glassCard(cornerRadius: 14)

                    if !customProviders.providers.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(customProviders.providers) { cp in
                                providerRow(name: cp.name, tag: cp.id, isCustom: true)
                            }
                        }
                        .glassCard(cornerRadius: 14)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t("模型", lang))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)

                        if let bi = selectedBuiltIn, let curated = bi.curatedModels {
                            ForEach(curated, id: \.id) { m in
                                curatedModelRow(id: m.id, name: m.name)
                            }
                        }

                        TextField(modelPlaceholder, text: $model)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(10)
                            .glassCard(cornerRadius: 10)
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        SecureField(keyPlaceholder, text: $apiKey)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(10)
                            .glassCard(cornerRadius: 10)
                        Text(L.t("留空则使用设置里对应提供方的 Key", lang))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 14)

                    Button {
                        saveAndDismiss()
                    } label: {
                        Text(L.t("保存", lang))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
        .onAppear {
            let entry = toolAPIConfig.entry(for: moduleId)
            selectedProviderRaw = entry.providerRaw
            selectedCustomId = entry.customProviderId
            model = entry.model
            let keys = UserDefaults.standard.dictionary(forKey: "ai_api_keys") as? [String: String] ?? [:]
            if let cid = entry.customProviderId {
                apiKey = keys["tool_\(moduleId)_\(cid)"] ?? ""
            } else {
                apiKey = keys["tool_\(moduleId)_\(entry.providerRaw)"] ?? ""
            }
        }
    }

    private var modelPlaceholder: String {
        if let bi = selectedBuiltIn {
            return bi.defaultModel
        }
        if let cid = selectedCustomId, let cp = customProviders.provider(for: cid) {
            return cp.defaultModel.isEmpty ? "model-name" : cp.defaultModel
        }
        return "model-name"
    }

    private var keyPlaceholder: String {
        if let bi = selectedBuiltIn { return bi.keyPlaceholder }
        if let cid = selectedCustomId, let cp = customProviders.provider(for: cid) {
            return cp.keyPlaceholder
        }
        return "sk-…"
    }

    private func providerRow(name: String, tag: String, isCustom: Bool) -> some View {
        let isSelected = isCustom ? (selectedCustomId == tag) : (selectedCustomId == nil && selectedProviderRaw == tag)
        return Button {
            if isCustom {
                selectedCustomId = tag
                selectedProviderRaw = tag
            } else {
                selectedCustomId = nil
                selectedProviderRaw = tag
            }
            if let bi = AIProvider(rawValue: tag), !isCustom {
                if model.isEmpty || AIProvider.allCases.contains(where: { $0.defaultModel == model }) {
                    model = bi.defaultModel
                }
            } else if isCustom, let cp = customProviders.provider(for: tag) {
                if model.isEmpty || AIProvider.allCases.contains(where: { $0.defaultModel == model }) {
                    model = cp.defaultModel
                }
            }
        } label: {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private func curatedModelRow(id: String, name: String) -> some View {
        let isSelected = model == id
        return Button {
            model = id
        } label: {
            HStack {
                Text(L.t(name, lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Theme.accent.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func saveAndDismiss() {
        let entry = ToolAPIEntry(
            providerRaw: selectedProviderRaw,
            customProviderId: selectedCustomId,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        toolAPIConfig.setEntry(entry, for: moduleId)

        if !apiKey.isEmpty {
            var keys = UserDefaults.standard.dictionary(forKey: "ai_api_keys") as? [String: String] ?? [:]
            if let cid = selectedCustomId {
                keys["tool_\(moduleId)_\(cid)"] = apiKey
            } else {
                keys["tool_\(moduleId)_\(selectedProviderRaw)"] = apiKey
            }
            UserDefaults.standard.set(keys, forKey: "ai_api_keys")
        }

        dismiss()
    }
}
