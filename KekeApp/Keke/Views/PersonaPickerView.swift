import SwiftUI
import UniformTypeIdentifiers

struct PersonaPickerView: View {
    @Binding var selectedPersonaId: String?
    @State private var personas: [Persona] = PersonaStore.allPersonas()
    @State private var showAddSheet = false
    @State private var editingPersona: Persona?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                header
                Spacer().frame(height: 28)
                personaGrid
                Spacer().frame(height: 20)
                addButton
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showAddSheet, onDismiss: {
            personas = PersonaStore.allPersonas()
        }) {
            AddPersonaSheet()
        }
        .sheet(item: $editingPersona, onDismiss: {
            personas = PersonaStore.allPersonas()
        }) { persona in
            EditPersonaSheet(persona: persona)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("🦀")
                .font(.system(size: 48))
            Text(L.t("选择角色", .zh))
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(L.t("每个角色有自己的聊天和记忆", .zh))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var personaGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(personas) { persona in
                Button { select(persona) } label: {
                    personaCard(persona)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        editingPersona = persona
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    if !PersonaStore.builtIn.contains(where: { $0.id == persona.id }) {
                        Button(role: .destructive) {
                            PersonaStore.removeCustom(id: persona.id)
                            personas = PersonaStore.allPersonas()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func personaCard(_ persona: Persona) -> some View {
        VStack(spacing: 8) {
            Text(persona.icon)
                .font(.system(size: 36))
            Text(persona.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(persona.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .glassCard(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(persona.displayColor.opacity(0.6), lineWidth: 2)
        )
    }

    private func select(_ persona: Persona) {
        PersonaStore.setActivePersonaId(persona.id)
        withAnimation(.easeOut(duration: 0.25)) {
            selectedPersonaId = persona.id
        }
    }

    private var addButton: some View {
        Button { showAddSheet = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                Text(L.t("添加新角色", .zh))
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .glassCard(cornerRadius: 20)
        }
    }
}

// MARK: - 添加新角色

struct AddPersonaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "🤖"
    @State private var subtitle = ""
    @State private var selectedColor = "purple"
    @State private var selectedCharacter = "clawd"
    @State private var dimConfigs = StateDimConfig.genericDefaults()
    @FocusState private var focusedField: AddField?

    private let colorOptions = ["blue", "purple", "green", "orange", "pink", "cyan", "red"]
    private enum AddField: Hashable { case name, icon, subtitle }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("角色名", text: $name)
                        .focused($focusedField, equals: .name)
                    TextField("图标 emoji", text: $icon)
                        .focused($focusedField, equals: .icon)
                    TextField("一句话介绍", text: $subtitle)
                        .focused($focusedField, equals: .subtitle)
                } header: {
                    Text("基本信息")
                }

                Section {
                    HStack(spacing: 8) {
                        ForEach(colorOptions, id: \.self) { c in
                            Circle()
                                .fill(colorFor(c))
                                .frame(width: 28, height: 28)
                                .padding(3)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == c ? colorFor(c) : Color.clear, lineWidth: 1.5)
                                )
                                .onTapGesture { selectedColor = c }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("主题色")
                }

                characterSection

                dimConfigSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("添加新角色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 角色形象

    private var characterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(BuiltInCharacter.allCases) { char in
                        VStack(spacing: 4) {
                            char.preview
                                .frame(width: 60, height: 60)
                            Text(char.displayName)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedCharacter == char.rawValue
                                      ? Theme.accent.opacity(0.15) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selectedCharacter == char.rawValue
                                        ? Theme.accent : Color.clear, lineWidth: 1.5)
                        )
                        .onTapGesture { selectedCharacter = char.rawValue }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("角色形象")
        } footer: {
            Text("更多像素画角色即将推出")
        }
    }

    // MARK: - 状态面板配置

    private var dimConfigSection: some View {
        Section {
            let states = dimConfigs.filter { $0.category == .state }
            let drives = dimConfigs.filter { $0.category == .drive }
            if !states.isEmpty {
                Text("状态")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Color.clear)
            }
            ForEach($dimConfigs) { $config in
                if config.category == .state {
                    dimConfigRow(config: $config)
                }
            }
            if !drives.isEmpty {
                Text("驱力")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Color.clear)
            }
            ForEach($dimConfigs) { $config in
                if config.category == .drive {
                    dimConfigRow(config: $config)
                }
            }
        } header: {
            HStack {
                Text("状态面板")
                Spacer()
                let pinnedCount = dimConfigs.filter { $0.pinned && $0.enabled }.count
                let totalCount = dimConfigs.filter(\.enabled).count
                Text("置顶 \(pinnedCount) / 共 \(totalCount)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        } footer: {
            Text("开关控制是否启用；📌 控制是否在首页置顶显示。可以自定义名称。")
        }
    }

    private func dimConfigRow(config: Binding<StateDimConfig>) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: config.enabled) {
                TextField("名称", text: config.label)
                    .font(.system(size: 14))
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
            Button {
                config.wrappedValue.pinned.toggle()
            } label: {
                Image(systemName: config.wrappedValue.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundStyle(config.wrappedValue.pinned ? Theme.accent : Theme.textSecondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!config.wrappedValue.enabled)
        }
    }

    // MARK: - 保存

    private func save() {
        let personaId = UUID().uuidString
        let persona = Persona(
            id: personaId,
            name: name.isEmpty ? "新角色" : name,
            icon: icon.isEmpty ? "🤖" : String(icon.prefix(2)),
            color: selectedColor,
            subtitle: subtitle.isEmpty ? "自定义角色" : subtitle,
            systemPrompt: "",
            characterType: selectedCharacter
        )
        PersonaStore.addCustom(persona)
        UserDefaults.standard.set(selectedCharacter, forKey: "\(personaId)_character_type")
        let enabledConfigs = dimConfigs.filter(\.enabled)
        let finalConfigs = enabledConfigs.isEmpty ? [dimConfigs[0]] : dimConfigs
        if let data = try? JSONEncoder().encode(finalConfigs) {
            UserDefaults.standard.set(data, forKey: "\(personaId)_state_dim_configs")
        }
        dismiss()
    }

    private func colorFor(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "cyan": return .cyan
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - 编辑角色

struct EditPersonaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var diary: DiaryService
    @EnvironmentObject var memory: MemoryService
    let persona: Persona
    @State private var name: String
    @State private var icon: String
    @State private var subtitle: String
    @State private var selectedColor: String
    @State private var selectedCharacter: String
    @State private var dimConfigs: [StateDimConfig]
    @State private var showMemoryImporter = false
    @State private var importResult: String?
    @FocusState private var focusedField: EditField?

    private let isBuiltIn: Bool
    private let colorOptions = ["blue", "purple", "green", "orange", "pink", "cyan", "red"]
    private enum EditField: Hashable { case name, icon, subtitle }

    private var lang: AppLanguage { store.appLanguage }

    private var memoriesText: String {
        memory.memories.filter { $0.contact == persona.id }.map(\.text).joined(separator: "\n")
    }

    init(persona: Persona) {
        self.persona = persona
        _name = State(initialValue: persona.name)
        _icon = State(initialValue: persona.icon)
        _subtitle = State(initialValue: persona.subtitle)
        _selectedColor = State(initialValue: persona.color)
        _selectedCharacter = State(initialValue: persona.characterType)
        isBuiltIn = PersonaStore.builtIn.contains { $0.id == persona.id }

        if let data = UserDefaults.standard.data(forKey: "\(persona.id)_state_dim_configs"),
           let saved = try? JSONDecoder().decode([StateDimConfig].self, from: data) {
            _dimConfigs = State(initialValue: saved)
        } else {
            _dimConfigs = State(initialValue: KekeStateService.defaultDimConfigs(for: persona.id))
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Group {
                    if !isBuiltIn {
                        basicInfoSection
                        colorSection
                    }
                    characterSection
                    diarySection
                }
                Group {
                    memorySection
                    dimConfigSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(L.t("编辑角色", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("取消", lang)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("保存", lang)) { save() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L.t("完成", lang)) { focusedField = nil }
                }
            }
            .fileImporter(isPresented: $showMemoryImporter,
                          allowedContentTypes: [.plainText, .text, .json, .item]) { result in
                guard case .success(let url) = result else { return }
                let added = memory.importFile(at: url, contact: persona.id)
                importResult = added > 0
                    ? L.count(added, "导入了 %d 条记忆", "Imported %d memories", lang)
                    : L.t("没找到能导入的内容", lang)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var basicInfoSection: some View {
        Section {
            TextField(L.t("角色名", lang), text: $name)
                .focused($focusedField, equals: .name)
            TextField(L.t("图标 emoji", lang), text: $icon)
                .focused($focusedField, equals: .icon)
            TextField(L.t("一句话介绍", lang), text: $subtitle)
                .focused($focusedField, equals: .subtitle)
        } header: {
            Text(L.t("基本信息", lang))
        }
    }

    private var colorSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(colorOptions, id: \.self) { c in
                    Circle()
                        .fill(colorFor(c))
                        .frame(width: 28, height: 28)
                        .padding(3)
                        .overlay(
                            Circle()
                                .stroke(selectedColor == c ? colorFor(c) : Color.clear, lineWidth: 1.5)
                        )
                        .onTapGesture { selectedColor = c }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(L.t("主题色", lang))
        }
    }

    private var characterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(BuiltInCharacter.allCases) { char in
                        VStack(spacing: 4) {
                            char.preview
                                .frame(width: 60, height: 60)
                            Text(char.displayName)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedCharacter == char.rawValue
                                      ? Theme.accent.opacity(0.15) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selectedCharacter == char.rawValue
                                        ? Theme.accent : Color.clear, lineWidth: 1.5)
                        )
                        .onTapGesture { selectedCharacter = char.rawValue }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(L.t("角色形象", lang))
        }
    }

    private var diarySection: some View {
        Section {
            probabilityRow(L.t("每天写日记的概率", lang), value: $diary.writeProbability)
            probabilityRow(L.t("偷看被发现的概率", lang), value: $diary.peekNoticeProbability)
            probabilityRow(L.t("读到分享日记的概率", lang), value: $diary.readProbability)
        } header: {
            Text(L.t("日记", lang))
        } footer: {
            Text(L.t("这三个都是概率，不是每次一定发生；调到 0 就相当于关掉这个行为。", lang))
        }
    }

    private var memorySection: some View {
        Section {
            Button {
                showMemoryImporter = true
            } label: {
                Label(L.t("导入记忆（md / txt / json）", lang), systemImage: "square.and.arrow.down")
            }
            if let importResult {
                Text(importResult)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            ShareLink(item: memoriesText) {
                Label(L.t("导出记忆", lang), systemImage: "square.and.arrow.up")
            }
            .disabled(memoriesText.isEmpty)
        } header: {
            Text(L.t("记忆", lang))
        } footer: {
            Text(L.t("md/txt 按行导入（一行一条）；json 认 claude.ai 和 ChatGPT 的官方导出文件。", lang))
        }
    }

    private var dimConfigSection: some View {
        Section {
            let states = dimConfigs.filter { $0.category == .state }
            let drives = dimConfigs.filter { $0.category == .drive }
            if !states.isEmpty {
                Text(L.t("状态", lang))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Color.clear)
            }
            ForEach($dimConfigs) { $config in
                if config.category == .state {
                    editDimRow(config: $config)
                }
            }
            if !drives.isEmpty {
                Text(L.t("驱力", lang))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Color.clear)
            }
            ForEach($dimConfigs) { $config in
                if config.category == .drive {
                    editDimRow(config: $config)
                }
            }
        } header: {
            HStack {
                Text(L.t("状态面板", lang))
                Spacer()
                let pinnedCount = dimConfigs.filter { $0.pinned && $0.enabled }.count
                let totalCount = dimConfigs.filter(\.enabled).count
                Text(L.t("置顶", lang) + " \(pinnedCount) / " + L.t("共", lang) + " \(totalCount)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        } footer: {
            Text(L.t("开关控制是否启用；📌 控制是否在首页置顶显示。可以自定义名称。", lang))
        }
    }

    private func save() {
        if !isBuiltIn {
            var updated = persona
            updated.name = name.isEmpty ? persona.name : name
            updated.icon = icon.isEmpty ? persona.icon : String(icon.prefix(2))
            updated.color = selectedColor
            updated.subtitle = subtitle.isEmpty ? persona.subtitle : subtitle
            updated.characterType = selectedCharacter
            var list = PersonaStore.loadCustom()
            if let idx = list.firstIndex(where: { $0.id == persona.id }) {
                list[idx] = updated
                PersonaStore.saveCustom(list)
            }
        }

        UserDefaults.standard.set(selectedCharacter, forKey: "\(persona.id)_character_type")

        let enabledConfigs = dimConfigs.filter(\.enabled)
        let finalConfigs = enabledConfigs.isEmpty ? [dimConfigs[0]] : dimConfigs
        if let data = try? JSONEncoder().encode(finalConfigs) {
            UserDefaults.standard.set(data, forKey: "\(persona.id)_state_dim_configs")
        }
        dismiss()
    }

    private func probabilityRow(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(value: value, in: 0...1, step: 0.05)
        }
    }

    private func editDimRow(config: Binding<StateDimConfig>) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: config.enabled) {
                TextField(L.t("名称", lang), text: config.label)
                    .font(.system(size: 14))
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
            Button {
                config.wrappedValue.pinned.toggle()
            } label: {
                Image(systemName: config.wrappedValue.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundStyle(config.wrappedValue.pinned ? Theme.accent : Theme.textSecondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!config.wrappedValue.enabled)
        }
    }

    private func colorFor(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "cyan": return .cyan
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - 内置角色形象

enum BuiltInCharacter: String, CaseIterable, Identifiable {
    case clawd
    case octo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clawd: return "Clawd 小螃蟹"
        case .octo: return "Octo 小章鱼"
        }
    }

    @ViewBuilder
    var preview: some View {
        switch self {
        case .clawd:
            ClawdMiniPreview()
        case .octo:
            OctoMiniPreview()
        }
    }
}

/// 角色选择器里的 Clawd 缩略图（简化版像素画）
struct ClawdMiniPreview: View {
    private static let shell = Color(red: 0.816, green: 0.502, blue: 0.376)
    private static let ink = Color(red: 0.08, green: 0.07, blue: 0.06)

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let scale = s / 50
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale))
            }
            context.fill(rect(5, 6, 40, 26), with: .color(Self.shell))
            context.fill(rect(0, 12, 7, 8), with: .color(Self.shell))
            context.fill(rect(43, 12, 7, 8), with: .color(Self.shell))
            context.fill(rect(10, 32, 5, 10), with: .color(Self.shell))
            context.fill(rect(20, 32, 5, 10), with: .color(Self.shell))
            context.fill(rect(30, 32, 5, 10), with: .color(Self.shell))
            context.fill(rect(36, 32, 5, 10), with: .color(Self.shell))
            context.fill(rect(13, 14, 5, 9), with: .color(Self.ink))
            context.fill(rect(32, 14, 5, 9), with: .color(Self.ink))
        }
    }
}
