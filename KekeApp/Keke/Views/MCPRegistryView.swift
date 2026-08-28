import SwiftUI

struct MCPRegistryView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var mcp: MCPRegistry
    @EnvironmentObject var toolAPIConfig: ToolAPIConfig
    @EnvironmentObject var customProviders: CustomProviderStore

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(spacing: 0) {
            Text(L.t("MCP 模块", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 4)
            Text(String(format: L.t("开启的模块会变成%@在聊天里能用的工具", lang), PersonaStore.persona(for: store.personaId).name))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(mcp.modules, id: \.id) { module in
                        moduleRow(module)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)
        }
        .background(Theme.background)
    }

    private func moduleRow(_ module: any MCPModule) -> some View {
        let enabled = mcp.isEnabled(module.id)
        return HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.system(size: 22))
                .foregroundStyle(enabled ? Theme.accent : Theme.textSecondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(module.localizedName(lang))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(module.localizedDescription(lang))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                if enabled {
                    APIPickerBar(moduleId: module.id)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { mcp.isEnabled(module.id) },
                set: { _ in mcp.toggle(module.id) }
            ))
            .labelsHidden()
            .tint(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 14)
    }
}
