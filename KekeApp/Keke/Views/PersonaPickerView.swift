import SwiftUI

struct PersonaPickerView: View {
    @Binding var selectedPersonaId: String?
    @State private var personas: [Persona] = PersonaStore.allPersonas()
    @State private var showAddSheet = false

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

struct AddPersonaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "🤖"
    @State private var subtitle = ""
    @State private var systemPrompt = ""
    @State private var selectedColor = "purple"

    private let colorOptions = ["blue", "purple", "green", "orange", "pink", "cyan", "red"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("角色名", text: $name)
                    TextField("图标 emoji", text: $icon)
                    TextField("一句话介绍", text: $subtitle)
                } header: {
                    Text("基本信息")
                }

                Section {
                    HStack(spacing: 8) {
                        ForEach(colorOptions, id: \.self) { c in
                            Circle()
                                .fill(colorFor(c))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().stroke(.white, lineWidth: selectedColor == c ? 2 : 0)
                                )
                                .onTapGesture { selectedColor = c }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("主题色")
                }

                Section {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 120)
                } header: {
                    Text("人设 Prompt")
                } footer: {
                    Text("定义这个角色的性格、说话方式、背景设定。留空则不会有专属人设。")
                }
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
                    Button("添加") {
                        let persona = Persona(
                            id: UUID().uuidString,
                            name: name.isEmpty ? "新角色" : name,
                            icon: icon.isEmpty ? "🤖" : String(icon.prefix(2)),
                            color: selectedColor,
                            subtitle: subtitle.isEmpty ? "自定义角色" : subtitle,
                            systemPrompt: systemPrompt
                        )
                        PersonaStore.addCustom(persona)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
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
