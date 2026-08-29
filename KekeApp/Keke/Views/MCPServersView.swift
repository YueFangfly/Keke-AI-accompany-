import SwiftUI

/// 自己加 MCP 服务器。
///
/// 内置的那 7 个模块（翻译/汇率/天气…）是写死在 App 里的，加不了新的。
/// 这一页填个地址就能挂任何第三方 MCP 服务器，它上报的工具会和内置的
/// 合成一份清单交给模型。
struct MCPServersView: View {
    @EnvironmentObject var store: ChatStore
    @ObservedObject private var registry = MCPServerRegistry.shared

    @State private var editing: MCPServerConfig?
    @State private var showAdd = false

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        Form {
            Section {
                Button {
                    showAdd = true
                } label: {
                    Label(L.t("添加服务器", lang), systemImage: "plus.circle")
                }
            } footer: {
                Text(L.t("填服务器地址就能用。它提供哪些工具由服务器决定——连上之后可以逐个开关，也可以设成「执行前问我一声」。请求头里如果要放 token，会存进钥匙串，不会进备份文件。", lang))
            }

            ForEach(registry.servers) { server in
                Section {
                    Button {
                        editing = server
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(server.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                statusBadge(registry.status[server.id] ?? .idle)
                            }
                            Text(server.url)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    if let tools = registry.discovered[server.id], !tools.isEmpty {
                        ForEach(tools, id: \.name) { tool in
                            toolRow(server: server, tool: tool)
                        }
                    }
                    Button(L.t("重新连接", lang)) {
                        Task { await registry.connect(server.id) }
                    }
                    .disabled((registry.status[server.id] ?? .idle).isBusy)
                    Button(L.t("删除这个服务器", lang), role: .destructive) {
                        registry.remove(server.id)
                    }
                } footer: {
                    if case .failed(let reason) = registry.status[server.id] ?? .idle {
                        Text(reason).font(.caption)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
        .slideOverCover(isPresented: $showAdd) {
            MCPServerEditor(existing: nil)
                .environmentObject(store)
                .backButtonInset { showAdd = false }
        }
        .slideOverCover(item: $editing) { server in
            MCPServerEditor(existing: server)
                .environmentObject(store)
                .backButtonInset { editing = nil }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: MCPStatus) -> some View {
        switch status {
        case .idle:
            Text(L.t("未启用", lang)).font(.caption2).foregroundStyle(Theme.textSecondary)
        case .connecting:
            ProgressView().controlSize(.small)
        case .connected(let count):
            Text(L.count(count, "%d 个工具", "%d tools", lang))
                .font(.caption2).foregroundStyle(.green)
        case .reconnecting(let attempt, let total):
            Text(L.t("重连中", lang) + " \(attempt)/\(total)")
                .font(.caption2).foregroundStyle(.orange)
        case .failed:
            Text(L.t("连不上", lang)).font(.caption2).foregroundStyle(Theme.crabRed)
        }
    }

    /// 每个工具一行：开关 + 「执行前问我」。
    /// 第三方服务器给什么工具事先不知道，得能逐个管
    private func toolRow(server: MCPServerConfig, tool: MCPProtocol.ToolDescriptor) -> some View {
        let setting = server.setting(for: tool.name)
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { setting.enabled },
                set: { newValue in
                    var updated = server
                    var s = updated.setting(for: tool.name)
                    s.enabled = newValue
                    updated.toolSettings[tool.name] = s
                    registry.update(updated, headers: nil)
                })) {
                Text(tool.name).font(.caption.monospaced())
            }
            if !tool.description.isEmpty {
                Text(tool.description)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if setting.enabled {
                Toggle(isOn: Binding(
                    get: { setting.needsApproval },
                    set: { newValue in
                        var updated = server
                        var s = updated.setting(for: tool.name)
                        s.needsApproval = newValue
                        updated.toolSettings[tool.name] = s
                        registry.update(updated, headers: nil)
                    })) {
                    Text(L.t("执行前问我一声", lang)).font(.caption2)
                }
            }
        }
        .padding(.vertical, 1)
    }
}

// MARK: - 增改

struct MCPServerEditor: View {
    @EnvironmentObject var store: ChatStore
    let existing: MCPServerConfig?

    @State private var name = ""
    @State private var url = ""
    @State private var transport: MCPServerConfig.Transport = .streamableHTTP
    @State private var enabled = true
    @State private var headerRows: [HeaderRow] = []
    @State private var loaded = false

    struct HeaderRow: Identifiable { let id = UUID(); var key = ""; var value = "" }

    private var lang: AppLanguage { store.appLanguage }
    private var registry: MCPServerRegistry { .shared }

    var body: some View {
        Form {
            Section {
                TextField(L.t("名字（自己认得就行）", lang), text: $name)
                TextField("https://example.com/mcp", text: $url)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.subheadline.monospaced())
                Picker(L.t("连接方式", lang), selection: $transport) {
                    ForEach(MCPServerConfig.Transport.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                Toggle(L.t("启用", lang), isOn: $enabled)
            } footer: {
                Text(L.t("不确定选哪种就先用 Streamable HTTP，那是现行协议。连不上再换成 SSE——不少早期服务器只支持它。", lang))
            }

            Section {
                ForEach($headerRows) { $row in
                    HStack {
                        TextField("Header", text: $row.key)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .frame(width: 120)
                        Divider()
                        SecureField(L.t("值", lang), text: $row.value)
                    }
                    .font(.caption.monospaced())
                }
                .onDelete { headerRows.remove(atOffsets: $0) }
                Button(L.t("加一行请求头", lang)) { headerRows.append(HeaderRow()) }
            } header: {
                Text(L.t("请求头（可选）", lang))
            } footer: {
                Text(L.t("需要鉴权的服务器在这里填，比如 Authorization / Bearer xxx。值存在系统钥匙串里，不会进备份文件。", lang))
            }

            Section {
                Button(existing == nil ? L.t("添加", lang) : L.t("保存", lang)) { save() }
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
        .onAppear(perform: loadOnce)
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        guard let existing else { return }
        name = existing.name
        url = existing.url
        transport = existing.transport
        enabled = existing.enabled
        headerRows = MCPServerStore.headers(for: existing.id)
            .sorted { $0.key < $1.key }
            .map { HeaderRow(key: $0.key, value: $0.value) }
    }

    private func save() {
        var config = existing ?? MCPServerConfig()
        config.name = name.trimmingCharacters(in: .whitespaces)
        config.url = url.trimmingCharacters(in: .whitespaces)
        config.transport = transport
        config.enabled = enabled
        var headers: [String: String] = [:]
        for row in headerRows {
            let key = row.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            headers[key] = row.value
        }
        if existing == nil {
            registry.add(config, headers: headers)
        } else {
            registry.update(config, headers: headers)
        }
    }
}
