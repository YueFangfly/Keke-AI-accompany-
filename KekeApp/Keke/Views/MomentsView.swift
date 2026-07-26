import SwiftUI
import PhotosUI

/// 朋友圈/日记：我和克克都能发动态，互相点赞评论。
/// 克克的回应不是秒回——发出去之后要等她"刷到"才会回，时间是随机排的。
struct MomentsView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var moments: MomentsStore
    @EnvironmentObject var contacts: ContactsStore

    @State private var composeText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var composeImage: UIImage?
    @State private var kekePosting = false

    var body: some View {
        VStack(spacing: 0) {
            composeBar
            if moments.moments.isEmpty {
                emptyState
            } else {
                feed
            }
        }
        .background(Theme.background)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    composeImage = image
                }
                photoItem = nil
            }
        }
        .task {
            await moments.checkPendingReactions(store: store, friends: contacts.friends)
        }
    }

    private var composeBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                TextField(L.t("分享一件小事…", store.appLanguage), text: $composeText, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.subheadline)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 38)
                }
            }
            if let composeImage {
                HStack(spacing: 8) {
                    Image(uiImage: composeImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(L.t("照片准备好了", store.appLanguage))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button {
                        self.composeImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    kekePosting = true
                    Task {
                        await moments.postKeke(store: store)
                        kekePosting = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if kekePosting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("🐱")
                        }
                        Text(L.t(kekePosting ? "克克在想……" : "让克克也发一条", store.appLanguage))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentLight.opacity(0.55)))
                }
                .disabled(kekePosting || store.apiKey.isEmpty)

                Button {
                    moments.postMine(text: composeText, image: composeImage, friends: contacts.friends)
                    composeText = ""
                    composeImage = nil
                } label: {
                    Text(L.t("发布", store.appLanguage))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                }
                .disabled(composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && composeImage == nil)
            }
        }
        .padding(14)
        .background(Theme.backgroundDeep.opacity(0.6))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🐱🌙")
                .font(.system(size: 40))
            Text(L.t("还没有动态\n发一条小事，或者让克克先说说", store.appLanguage))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(moments.moments) { moment in
                    MomentCard(moment: moment)
                }
            }
            .padding(14)
        }
    }
}

private struct MomentCard: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var moments: MomentsStore
    @EnvironmentObject var contacts: ContactsStore
    let moment: Moment
    @State private var commentText = ""
    @State private var showCommentField = false
    @State private var replyTarget: MomentComment?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !moment.text.isEmpty {
                Text(moment.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
            if let path = moment.imagePath, let image = Attachments.loadImage(named: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .clipped()
            }
            actionRow
            if let likersLine {
                Text("❤️ " + likersLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !moment.comments.isEmpty {
                commentThread
            }
            if showCommentField {
                commentInput
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .contextMenu {
            if moment.author == .me {
                Button(role: .destructive) {
                    moments.delete(moment.id)
                } label: {
                    Label(L.t("删除", store.appLanguage), systemImage: "trash")
                }
            }
        }
    }

    /// 点赞行："克克、Claude 点赞了"；被删掉的联系人不显示
    private var likersLine: String? {
        var names: [String] = []
        if moment.likedByKeke { names.append(L.t("克克", store.appLanguage)) }
        for id in moment.likedByFriends ?? [] {
            if let friend = contacts.contact(id) { names.append(friend.name) }
        }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: "、") + " " + L.t("点赞了", store.appLanguage)
    }

    private var header: some View {
        HStack(spacing: 6) {
            authorAvatar
            Text(moment.author == .keke ? L.t("克克", store.appLanguage) : store.myName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(moment.date, style: .relative)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var authorAvatar: some View {
        if moment.author == .me, let path = store.myAvatarPath, let image = Attachments.loadImage(named: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 22)
                .clipShape(Circle())
        } else {
            Text(moment.author == .keke ? "🐱" : "🌙")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            Button {
                moments.toggleMyLike(moment.id)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: moment.likedByMe ? "heart.fill" : "heart")
                        .foregroundStyle(moment.likedByMe ? Theme.crabRed : Theme.textSecondary)
                    Text(L.t("赞", store.appLanguage))
                }
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showCommentField.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                    Text(L.t("评论", store.appLanguage))
                }
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.caption)
    }

    private var commentThread: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(moment.comments) { comment in
                commentLine(comment)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.backgroundDeep.opacity(0.5)))
    }

    /// 拆成单独的函数、把三元表达式先存成局部变量，
    /// 不然编译器在 ForEach 闭包里推断这种"三元+样式+拼接"的表达式会卡很久甚至报错
    private func commentLine(_ comment: MomentComment) -> some View {
        let prefix: String
        let prefixColor: Color
        switch comment.author {
        case .keke:
            prefix = L.t("克克：", store.appLanguage)
            prefixColor = Theme.crabRed
        case .me:
            prefix = L.t("我：", store.appLanguage)
            prefixColor = Theme.accent
        case .friend:
            prefix = (comment.friendName ?? "朋友") + "："
            prefixColor = Theme.textSecondary
        }

        // 注意：这里必须用 foregroundColor（Text 自己的版本，返回 Text），
        // 不能用 foregroundStyle（那是 View 通用版本，返回 some View，没法用 + 拼接）
        let prefixText: Text = Text(prefix)
            .foregroundColor(prefixColor)
            .fontWeight(.semibold)
        let bodyText: Text = Text(comment.text)
            .foregroundColor(Theme.textPrimary)
        let line = (prefixText + bodyText).font(.caption)

        return VStack(alignment: .leading, spacing: 2) {
            if let preview = comment.replyToPreview {
                Text("↩︎ " + preview)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                line
                Spacer()
                Button {
                    replyTarget = comment
                    withAnimation(.easeOut(duration: 0.15)) { showCommentField = true }
                } label: {
                    Text(L.t("回复", store.appLanguage))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var commentInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let target = replyTarget {
                let preview: String = String(target.text.prefix(20))
                HStack(spacing: 6) {
                    Text(L.t("回复", store.appLanguage) + " " + preview)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button {
                        replyTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(L.t("说句评论…", store.appLanguage), text: $commentText)
                    .font(.caption)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.backgroundDeep.opacity(0.5)))
                Button {
                    moments.addComment(to: moment.id, text: commentText, replyTo: replyTarget)
                    commentText = ""
                    showCommentField = false
                    replyTarget = nil
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.accent))
                }
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
