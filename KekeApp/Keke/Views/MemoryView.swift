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

    private var currentContact: String { memory.personaId }

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
                    Text(L.t("克克的人设", store.appLanguage))
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
            TextField(L.t("直接告诉克克要记住的事…", store.appLanguage), text: $newMemory)
                .font(.subheadline)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
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
                    : L.t("最近聊的克克都记得啦", store.appLanguage)
                extracting = false
            }
        } label: {
            HStack(spacing: 8) {
                if extracting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("🐱")
                }
                Text(L.t(extracting ? "克克在回忆……" : "让克克整理最近的聊天", store.appLanguage))
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🐱")
                .font(.system(size: 44))
            Text(L.t("克克还没有长期记忆\n多聊聊它会自己记住重要的事，\n也可以在上面直接告诉它", store.appLanguage))
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
                    Label(L.t("让克克惦记着这事", store.appLanguage), systemImage: "hourglass")
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
                Label(L.t("让克克忘掉这条", store.appLanguage), systemImage: "trash")
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
