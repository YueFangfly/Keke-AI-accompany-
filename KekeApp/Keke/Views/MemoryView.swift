import SwiftUI
import UniformTypeIdentifiers

struct MemoryView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var memory: MemoryService
    @State private var newMemory = ""
    @State private var extracting = false
    @State private var resultText: String?
    @State private var showImporter = false
    @State private var showPromptEditor = false
    @State private var showFavorites = false
    @State private var showProfileImporter = false
    @State private var synthesizing = false
    @State private var synthesizeProgress = ""

    private var currentContact: String { memory.personaId }
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }
    private var personaIcon: String { PersonaStore.persona(for: store.personaId).icon }

    private var partitionMemories: [MemoryEntry] {
        memory.memories.filter { $0.contact == currentContact }
    }

    var body: some View {
        VStack(spacing: 0) {
            topLinks
            addBar
            HStack(spacing: 10) {
                extractButton
                importButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            profileSynthesizeButton
                .padding(.horizontal, 14)
                .padding(.top, 6)

            if let resultText {
                Text(resultText)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 6)
            }

            if partitionMemories.isEmpty {
                emptyState
            } else {
                memoryList
            }
        }
        .background(Theme.background)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.plainText, .text, .json, .item]) { result in
            guard case .success(let url) = result else { return }
            let added = memory.importFile(at: url, contact: currentContact)
            resultText = added > 0
                ? L.count(added, "从文件里导入了 %d 条", "Imported %d from the file", store.appLanguage)
                : L.t("没找到能导入的内容", store.appLanguage)
        }
        .fileImporter(isPresented: $showProfileImporter,
                      allowedContentTypes: [.plainText, .text, .json, .item]) { result in
            guard case .success(let url) = result else { return }
            synthesizing = true
            synthesizeProgress = ""
            resultText = nil
            Task {
                let profile = await memory.synthesizeProfile(
                    from: url, userName: store.myName,
                    provider: store.provider, apiKey: store.apiKey, model: store.model
                ) { progress in
                    synthesizeProgress = progress
                }
                synthesizing = false
                synthesizeProgress = ""
                resultText = profile != nil
                    ? L.t("性格画像已写入记忆", store.appLanguage)
                    : L.t("没能从文件中提炼出性格画像", store.appLanguage)
            }
        }
        .sheet(isPresented: $showPromptEditor) {
            PromptEditorView().environmentObject(store)
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesView().environmentObject(store)
        }
    }

    private var topLinks: some View {
        HStack(spacing: 10) {
            Button {
                showPromptEditor = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                    Text(String(format: L.t("%@的人设", store.appLanguage), personaName))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .glassCard(cornerRadius: 12)
            }
            Button {
                showFavorites = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                    Text(L.t("收藏", store.appLanguage))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .glassCard(cornerRadius: 12)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            TextField(String(format: L.t("直接告诉%@要记住的事…", store.appLanguage), personaName), text: $newMemory)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            Button {
                memory.add(newMemory, contact: currentContact)
                newMemory = ""
            } label: {
                Text(L.t("记住", store.appLanguage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
            }
            .disabled(newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var extractButton: some View {
        Button {
            extracting = true
            resultText = nil
            Task {
                let added = await store.extractMemoriesNow()
                resultText = added > 0
                    ? L.count(added, "记住了 %d 件新的事", "Remembered %d new thing(s)", store.appLanguage)
                    : String(format: L.t("最近聊的%@都记得啦", store.appLanguage), personaName)
                extracting = false
            }
        } label: {
            HStack(spacing: 8) {
                if extracting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(personaIcon)
                }
                Text(extracting
                    ? String(format: L.t("%@在回忆……", store.appLanguage), personaName)
                    : String(format: L.t("让%@整理最近的聊天", store.appLanguage), personaName))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentLight.opacity(0.55)))
        }
        .disabled(extracting || store.apiKey.isEmpty)
    }

    private var importButton: some View {
        Button {
            showImporter = true
        } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentLight.opacity(0.55)))
        }
    }

    private var profileSynthesizeButton: some View {
        Button {
            showProfileImporter = true
        } label: {
            HStack(spacing: 8) {
                if synthesizing {
                    ProgressView()
                        .controlSize(.small)
                    Text(synthesizeProgress.isEmpty
                        ? L.t("正在提炼性格画像…", store.appLanguage)
                        : String(format: L.t("正在分析第 %@ 块…", store.appLanguage), synthesizeProgress))
                } else {
                    Image(systemName: "person.text.rectangle")
                    Text(L.t("从聊天记录提炼性格画像", store.appLanguage))
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        }
        .disabled(synthesizing || store.apiKey.isEmpty)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(personaIcon)
                .font(.system(size: 44))
            Text(String(format: L.t("%@还没有长期记忆\n多聊聊TA会自己记住重要的事，\n也可以在上面直接告诉TA", store.appLanguage), personaName))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var memoryList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                HStack {
                    Text(L.count(partitionMemories.count, "记住的事 · %d 条",
                                 "Memories · %d", store.appLanguage))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(L.t("长按可以删除", store.appLanguage))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 4)

                ForEach(partitionMemories) { entry in
                    memoryRow(entry)
                }
            }
            .padding(14)
        }
    }

    private func memoryRow(_ entry: MemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(importanceMark(entry.importance))
                .font(.headline)
                .foregroundStyle(entry.importance == .pinned ? Theme.crabRed : Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                    if entry.status == .open {
                        Text("⏳ " + L.t("还惦记着", store.appLanguage))
                            .foregroundStyle(.orange)
                    } else if entry.status == .resolved {
                        Text("✓ " + L.t("已经了结", store.appLanguage))
                    }
                    if entry.recallCount > 0 {
                        Text(L.count(entry.recallCount, "想起过 %d 次", "recalled %d time(s)", store.appLanguage))
                    }
                    if entry.archived {
                        Text("🗄 " + L.t("已归档", store.appLanguage))
                    }
                    if entry.arousal >= 0.5 {
                        Text(entry.valence >= 0 ? "💗" : "💧")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .opacity(entry.archived ? 0.55 : 1)
        .contextMenu {
            Button {
                memory.setImportance(.pinned, for: entry)
            } label: {
                Label(L.t("标为置顶", store.appLanguage), systemImage: "pin.fill")
            }
            Button {
                memory.setImportance(.important, for: entry)
            } label: {
                Label(L.t("标为重要", store.appLanguage), systemImage: "star.fill")
            }
            Button {
                memory.setImportance(.normal, for: entry)
            } label: {
                Label(L.t("标为普通", store.appLanguage), systemImage: "circle")
            }
            Divider()
            if entry.status == .open {
                Button {
                    memory.setStatus(.resolved, for: entry)
                } label: {
                    Label(L.t("这事了结啦", store.appLanguage), systemImage: "checkmark.circle")
                }
            } else {
                Button {
                    memory.setStatus(.open, for: entry)
                } label: {
                    Label(String(format: L.t("让%@惦记着这事", store.appLanguage), personaName), systemImage: "hourglass")
                }
            }
            if entry.archived {
                Button {
                    memory.setArchived(false, for: entry)
                } label: {
                    Label(L.t("从归档里拿回来", store.appLanguage), systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    memory.setArchived(true, for: entry)
                } label: {
                    Label(L.t("收进归档", store.appLanguage), systemImage: "archivebox")
                }
            }
            Button(role: .destructive) {
                memory.delete(entry)
            } label: {
                Label(String(format: L.t("让%@忘掉这条", store.appLanguage), personaName), systemImage: "trash")
            }
        }
    }

    private func importanceMark(_ importance: MemoryDatabase.Importance) -> String {
        switch importance {
        case .pinned: return "📌"
        case .important: return "⭐️"
        case .normal: return "·"
        }
    }
}
