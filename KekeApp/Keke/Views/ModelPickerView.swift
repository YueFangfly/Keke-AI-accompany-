import SwiftUI

struct ModelPickerView: View {
    @EnvironmentObject var store: ChatStore
    @Binding var hasEnteredApp: Bool

    private var lang: AppLanguage { store.appLanguage }

    private var cards: [ModelCard] {
        var list: [ModelCard] = [
            ModelCard(provider: .claude, icon: "sparkle", color: .purple,
                      title: "Claude", subtitle: L.t("Anthropic · 最聪明", lang)),
            ModelCard(provider: .deepseek, icon: "brain.head.profile", color: .cyan,
                      title: "DeepSeek", subtitle: L.t("深度求索 · 聪明又实惠", lang)),
            ModelCard(provider: .openai, icon: "bubble.left.and.text.bubble.right", color: .green,
                      title: "GPT", subtitle: L.t("OpenAI · 经典老牌", lang)),
            ModelCard(provider: .grok, icon: "bolt.fill", color: .orange,
                      title: "Grok", subtitle: L.t("xAI · 快又犀利", lang)),
        ]
        for custom in store.customProviders {
            list.append(ModelCard(provider: nil, customId: custom.id,
                                  icon: "plus.square.fill", color: .gray,
                                  title: custom.name, subtitle: custom.baseURL))
        }
        return list
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                header
                Spacer().frame(height: 28)
                modelGrid
                Spacer().frame(height: 20)
                addCustomButton
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(colorScheme(for: store.appearanceMode))
        .fontDesign(store.fontDesignValue)
    }

    private func colorScheme(for mode: String) -> ColorScheme? {
        if (AppTheme(rawValue: store.appTheme) ?? .mist).isAlwaysDark { return .dark }
        switch mode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("🦀")
                .font(.system(size: 48))
            Text(L.t("选择模型", lang))
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(L.t("选一个 AI 来陪你聊天", lang))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var modelGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(cards) { card in
                Button { select(card) } label: {
                    cardView(card)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cardView(_ card: ModelCard) -> some View {
        let isSelected = isCurrentlySelected(card)
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(card.color.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: card.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(card.color)
            }
            Text(card.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(card.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .glassCard(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? card.color : .clear, lineWidth: 2)
        )
    }

    private func isCurrentlySelected(_ card: ModelCard) -> Bool {
        if let p = card.provider {
            return store.provider == p && store.activeCustomProviderId == nil
        }
        return store.activeCustomProviderId == card.customId
    }

    private func select(_ card: ModelCard) {
        if let p = card.provider {
            store.activeCustomProviderId = nil
            store.provider = p
        } else if let cid = card.customId {
            store.activeCustomProviderId = cid
        }
        withAnimation(.easeOut(duration: 0.25)) {
            hasEnteredApp = true
        }
    }

    @State private var showAddCustom = false

    private var addCustomButton: some View {
        Button {
            showAddCustom = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                Text(L.t("添加自定义模型", lang))
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .glassCard(cornerRadius: 20)
        }
        .sheet(isPresented: $showAddCustom) {
            AddCustomProviderSheet(store: store)
        }
    }
}

private struct ModelCard: Identifiable {
    let id = UUID()
    var provider: AIProvider?
    var customId: String?
    var icon: String
    var color: Color
    var title: String
    var subtitle: String
}

struct AddCustomProviderSheet: View {
    @ObservedObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var modelName = ""

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.t("名称", lang), text: $name)
                    TextField(L.t("API 地址", lang), text: $baseURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("API Key", text: $apiKey)
                    TextField(L.t("模型名", lang), text: $modelName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text(L.t("自定义模型", lang))
                } footer: {
                    Text(L.t("填入兼容 OpenAI Chat Completions 格式的 API 地址", lang))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(L.t("添加自定义模型", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("取消", lang)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("添加", lang)) {
                        let custom = CustomProvider(
                            name: name.isEmpty ? "Custom" : name,
                            baseURL: baseURL,
                            apiKey: apiKey,
                            model: modelName
                        )
                        store.addCustomProvider(custom)
                        dismiss()
                    }
                    .disabled(baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
