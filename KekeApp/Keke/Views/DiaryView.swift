import SwiftUI
import PhotosUI

/// 主页 → 日记：我和克克各写各的私密日记。作者自己决定这一篇给不给对方看；
/// 克克没公开的可以偷看，有概率被她发现；我分享给她的，她看完会留个反应；
/// 两人都能配图、都能在下面留评论
struct DiaryListView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var diary: DiaryService

    @State private var tab: Tab = .mine
    @State private var composeText = ""
    @State private var composeShared = false
    @State private var composePhotoItem: PhotosPickerItem?
    @State private var composeImage: UIImage?
    @State private var showCompose = false
    @State private var reactionBubble: String?
    @State private var peekingID: UUID?
    @State private var commentDrafts: [UUID: String] = [:]

    private var lang: AppLanguage { store.appLanguage }
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }

    enum Tab { case mine, keke }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(L.t("我的日记", lang)).tag(Tab.mine)
                Text(String(format: L.t("%@的日记", lang), personaName)).tag(Tab.keke)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)

            if tab == .mine {
                mineList
            } else {
                kekeList
            }
        }
        .background(Theme.background)
        .overlay(alignment: .top) {
            if let reactionBubble {
                Text(reactionBubble)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal, 30)
                    .padding(.top, 54)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if tab == .mine {
                if showCompose {
                    composeBar
                } else {
                    composeToggleButton
                }
            }
        }
        .onChange(of: composePhotoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    composeImage = image
                }
                composePhotoItem = nil
            }
        }
    }

    // MARK: - 我的日记

    private var mineList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if diary.myEntries.isEmpty {
                    emptyState(L.t("还没写过日记，点下面写一篇吧", lang))
                } else {
                    ForEach(diary.myEntries) { entry in
                        mineCard(entry)
                    }
                }
            }
            .padding(14)
        }
    }

    private func mineCard(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                statusBadge(entry)
            }
            Text(entry.text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            entryImage(entry)
            if let reaction = entry.reaction, entry.readByOther {
                HStack(alignment: .top, spacing: 5) {
                    Text("🐱")
                    Text(reaction)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Toggle(isOn: Binding(
                get: { entry.sharedWithOther },
                set: { diary.setShared($0, for: entry.id) }
            )) {
                Text(String(format: L.t("分享给%@", lang), personaName))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(Theme.accent)
            commentSection(entry)
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
        .contextMenu {
            Button(role: .destructive) {
                diary.delete(entry.id)
            } label: {
                Label(L.t("删除", lang), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func entryImage(_ entry: DiaryEntry) -> some View {
        if let path = entry.imagePath, let image = Attachments.loadImage(named: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func commentSection(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !entry.comments.isEmpty {
                Divider().opacity(0.3)
                ForEach(entry.comments) { comment in
                    HStack(alignment: .top, spacing: 5) {
                        Text(comment.author == .me ? "🌙" : "🐱")
                            .font(.caption2)
                        Text(comment.text)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            HStack(spacing: 6) {
                TextField(L.t("留句评论…", lang), text: Binding(
                    get: { commentDrafts[entry.id] ?? "" },
                    set: { commentDrafts[entry.id] = $0 }
                ))
                .font(.caption2)
                Button {
                    diary.addComment(to: entry.id, text: commentDrafts[entry.id] ?? "")
                    commentDrafts[entry.id] = ""
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
                .disabled((commentDrafts[entry.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.top, 2)
    }

    private func statusBadge(_ entry: DiaryEntry) -> some View {
        Group {
            if !entry.sharedWithOther {
                Text(L.t("仅自己可见", lang))
            } else if entry.readByOther {
                Text(String(format: L.t("%@看过了", lang), personaName))
            } else {
                Text(String(format: L.t("已分享给%@", lang), personaName))
            }
        }
        .font(.caption2)
        .foregroundStyle(Theme.textSecondary)
    }

    private var composeToggleButton: some View {
        Button {
            withAnimation { showCompose = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                Text(L.t("写今天的日记", lang))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
        }
        .padding(14)
        .background(Theme.backgroundDeep)
    }

    private var composeBar: some View {
        VStack(spacing: 8) {
            TextEditor(text: $composeText)
                .frame(height: 90)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.backgroundDeep.opacity(0.6)))
            if let composeImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: composeImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Button {
                        self.composeImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding(6)
                }
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $composePhotoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                Toggle(isOn: $composeShared) {
                    Text(String(format: L.t("分享给%@", lang), personaName))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .fixedSize()
            }
            HStack(spacing: 10) {
                Button {
                    showCompose = false
                    composeText = ""
                    composeShared = false
                    composeImage = nil
                } label: {
                    Text(L.t("取消", lang))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                Button {
                    let imagePath = composeImage.flatMap { Attachments.saveImage($0) }
                    diary.postMine(text: composeText, shared: composeShared, imagePath: imagePath)
                    composeText = ""
                    composeShared = false
                    composeImage = nil
                    showCompose = false
                } label: {
                    Text(L.t("保存", lang))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
                }
                .disabled(composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(Theme.backgroundDeep)
    }

    // MARK: - 克克的日记

    private var kekeList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if diary.kekeEntries.isEmpty {
                    emptyState(String(format: L.t("%@还没写日记", lang), personaName))
                } else {
                    ForEach(diary.kekeEntries) { entry in
                        kekeCard(entry)
                    }
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func kekeCard(_ entry: DiaryEntry) -> some View {
        if entry.sharedWithOther || entry.peeked {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if !entry.sharedWithOther && entry.peeked {
                        Text(L.t("偷看的", lang))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text(entry.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                entryImage(entry)
                if let reaction = entry.reaction {
                    HStack(alignment: .top, spacing: 5) {
                        Text("🐱")
                        Text(reaction)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                commentSection(entry)
            }
            .padding(12)
            .glassCard(cornerRadius: 14)
        } else {
            Button {
                peek(entry)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                        Text(String(format: L.t("%@这篇没有公开……要不要偷看一下？", lang), personaName))
                            .font(.caption)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    if peekingID == entry.id {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                .padding(12)
                .glassCard(cornerRadius: 14)
            }
            .disabled(peekingID == entry.id)
        }
    }

    private func peek(_ entry: DiaryEntry) {
        peekingID = entry.id
        Task {
            let line = await diary.peek(entry, store: store)
            peekingID = nil
            guard let line else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { reactionBubble = line }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation { reactionBubble = nil }
            }
        }
    }

    // MARK: - 通用

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 12) {
            Text("📔")
                .font(.system(size: 40))
            Text(text)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
