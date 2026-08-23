import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var typingRhythm: TypingRhythm
    @EnvironmentObject var stickerStore: StickerStore
    @StateObject private var keyboard = KeyboardObserver()
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    // 附件
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var pendingDocName: String?
    @State private var pendingDocText: String?
    @State private var showFileImporter = false
    @State private var importError: String?
    @State private var showStickers = false
    @State private var stickerPickerItem: PhotosPickerItem?
    /// 聊天页只渲染最近这么多条，老的折叠成「查看更早」按需展开——
    /// 这样聊到几万条，打开和滑动都还是秒开（完整记录都在内存和档案里，一条不少）
    @State private var displayLimit = 400

    private let stickers = ["🐱", "🐱💕", "🐱😴", "🐱☕️", "*挥爪*", "*戳戳你*", "*躲起来*",
                             "*爪子捂脸*", "在！", "嗯……", "😳", "🥹", "😭", "🫡", "👀", "💤"]

    var body: some View {
        ZStack {
            chatBackground
            VStack(spacing: 0) {
                messagesList

                if let importError {
                    Text(importError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.vertical, 3)
                }
                if pendingImage != nil || pendingDocName != nil {
                    pendingBar
                }
                if showStickers {
                    stickerBar
                }

                inputBar
            }
            .padding(.bottom, max(0, keyboard.height - bottomSafeInset))
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pendingImage = image
                    pendingDocName = nil
                    pendingDocText = nil
                    importError = nil
                }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .plainText, .html, .text]) { result in
            if case .success(let url) = result {
                if let text = Attachments.extractText(from: url) {
                    pendingDocName = url.lastPathComponent
                    pendingDocText = text
                    pendingImage = nil
                    importError = nil
                } else {
                    importError = L.t("这个文件读不出文字", store.appLanguage)
                }
            }
        }
    }

    /// 键盘弹起后要补的高度 = 键盘高度 - 屏幕本身的底部安全区（不然会多留一截空白）
    private var bottomSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first }
            .first?.safeAreaInsets.bottom ?? 0
    }

    /// 自己设置的聊天背景图；没设置就用默认的玻璃拟态渐变
    @ViewBuilder
    private var chatBackground: some View {
        if let path = store.chatBackgroundPath, let image = Attachments.loadImage(named: path) {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .overlay(Color.black.opacity(0.12))
            .ignoresSafeArea()
        } else {
            Theme.background
        }
    }

    /// 当前实际渲染的消息（最近 displayLimit 条）
    private var visibleMessages: [ChatMessage] {
        let all = store.messages
        return all.count > displayLimit ? Array(all.suffix(displayLimit)) : all
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.messages.count > displayLimit {
                        Button {
                            displayLimit += 400
                        } label: {
                            Text(L.t("查看更早的消息", store.appLanguage))
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                                .padding(.vertical, 8)
                        }
                    }
                    ForEach(visibleMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if store.isThinking {
                        HStack(spacing: 8) {
                            TypingIndicator()
                            if !store.thinkingStatus.isEmpty {
                                Text(store.thinkingStatus)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.card.opacity(0.85))
                        )
                        .padding(.horizontal, 14)
                        .animation(.easeInOut(duration: 0.2), value: store.thinkingStatus)
                    }
                }
                .padding(.vertical, 12)
            }
            .onTapGesture { inputFocused = false }
            .onChange(of: store.messages.count) { _ in
                if let last = store.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: store.scrollTarget) { target in
                if let target {
                    ensureVisible(target)
                    withAnimation { proxy.scrollTo(target, anchor: .center) }
                    store.scrollTarget = nil
                }
            }
            .onAppear {
                if let target = store.scrollTarget {
                    ensureVisible(target)
                    proxy.scrollTo(target, anchor: .center)
                    store.scrollTarget = nil
                } else if let last = store.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    /// 从搜索跳转过来时，如果目标比当前窗口更早，就把窗口撑到能显示它
    private func ensureVisible(_ id: UUID) {
        guard let index = store.messages.firstIndex(where: { $0.id == id }) else { return }
        let fromEnd = store.messages.count - index
        if fromEnd > displayLimit { displayLimit = store.messages.count }
    }

    private var pendingBar: some View {
        HStack(spacing: 8) {
            if let image = pendingImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(L.t("图片准备好了，想说什么一起发～", store.appLanguage))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else if let name = pendingDocName {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Theme.accent)
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Button {
                pendingImage = nil
                pendingDocName = nil
                pendingDocText = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.backgroundDeep.opacity(0.6))
    }

    private var stickerBar: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(stickers, id: \.self) { sticker in
                        Button {
                            store.send(sticker)
                            showStickers = false
                        } label: {
                            Text(sticker)
                                .font(.title3)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Theme.card))
                        }
                    }
                }
                .padding(.horizontal, 14)
            }

            if !stickerStore.stickers.isEmpty || true {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PhotosPicker(selection: $stickerPickerItem, matching: .images) {
                            VStack(spacing: 2) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18))
                                Text(L.t("添加", store.appLanguage))
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(Theme.accent)
                            .frame(width: 56, height: 56)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                        }
                        ForEach(stickerStore.stickers) { sticker in
                            if let img = stickerStore.loadImage(for: sticker) {
                                Button {
                                    store.send("", image: img)
                                    showStickers = false
                                } label: {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        stickerStore.deleteSticker(sticker)
                                    } label: {
                                        Label(L.t("删除", store.appLanguage), systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .padding(.vertical, 6)
        .background(Theme.backgroundDeep.opacity(0.6))
        .onChange(of: stickerPickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    stickerStore.addSticker(image: image)
                }
                stickerPickerItem = nil
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 38)
            }
            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24, height: 38)
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showStickers.toggle() }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 18))
                    .foregroundStyle(showStickers ? Theme.accent : Theme.textSecondary)
                    .frame(width: 24, height: 38)
            }

            TextField(String(format: L.t("和%@说点什么…", store.appLanguage), PersonaStore.persona(for: store.personaId).name), text: $input, axis: .vertical)
                .lineLimit(1...4)
                .font(.subheadline)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
                .focused($inputFocused)
                .onChange(of: input) { newValue in
                    typingRhythm.textChanged(newValue)
                }

            if store.isThinking {
                Button {
                    store.cancelSend()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.red.opacity(0.82)))
                }
            } else {
                Button {
                    var doc: (name: String, text: String)?
                    if let name = pendingDocName, let text = pendingDocText {
                        doc = (name: name, text: text)
                    }
                    store.send(input, image: pendingImage, doc: doc)
                    input = ""
                    pendingImage = nil
                    pendingDocName = nil
                    pendingDocText = nil
                    importError = nil
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.accent))
                }
                .disabled(sendDisabled)
                .opacity(sendDisabled ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            VStack(spacing: 0) {
                Divider()
                Spacer()
            }
        )
        .background(Theme.backgroundDeep)
    }

    private var sendDisabled: Bool {
        let noText = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (noText && pendingImage == nil && pendingDocText == nil) || store.isThinking
    }
}

struct MessageBubble: View {
    @EnvironmentObject var store: ChatStore
    let message: ChatMessage
    @State private var showThinking = false
    @State private var multiSelections: Set<String> = []

    private var isLatestKekeMessage: Bool {
        guard message.role == .keke else { return false }
        return store.messages.last(where: { $0.role == .keke })?.id == message.id
    }

    private var choicesActive: Bool {
        message.choices != nil && !message.choices!.isEmpty && isLatestKekeMessage && !store.isThinking
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 56) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if let path = message.imagePath, let image = Attachments.loadImage(named: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 200, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if let docName = message.docName {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.accent)
                        Text(docName)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 11).fill(Theme.card))
                }
                if let thinking = message.thinking {
                    thinkingDisclosure(thinking)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 17)
                                .fill(message.role == .user ? Theme.bubbleUser : Theme.bubbleKeke)
                        )
                }
                if let audioId = message.audioTrackId {
                    AudioBubble(trackId: audioId)
                }
                if choicesActive, let choices = message.choices {
                    choiceChips(choices, multi: message.multiSelect ?? false)
                }
                HStack(spacing: 4) {
                    if message.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                    Text(message.date, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if message.role == .keke { Spacer(minLength: 56) }
        }
        .padding(.horizontal, 16)
        .contextMenu {
            Button {
                store.toggleFavorite(message.id)
            } label: {
                Label(L.t(message.isFavorite ? "取消收藏" : "收藏", store.appLanguage),
                      systemImage: message.isFavorite ? "star.slash" : "star")
            }
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label(L.t("复制", store.appLanguage), systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                store.deleteMessage(message.id)
            } label: {
                Label(L.t("删除", store.appLanguage), systemImage: "trash")
            }
        }
    }

    // MARK: - 选项按钮

    private func choiceChips(_ choices: [ChoiceOption], multi: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(choices) { option in
                    let selected = multiSelections.contains(option.label)
                    Button {
                        if multi {
                            if selected {
                                multiSelections.remove(option.label)
                            } else {
                                multiSelections.insert(option.label)
                            }
                        } else {
                            store.send(option.label)
                        }
                    } label: {
                        Text(option.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selected ? .white : Theme.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(selected ? Theme.accent : Theme.accent.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            if multi && !multiSelections.isEmpty {
                Button {
                    let reply = multiSelections.sorted().joined(separator: "、")
                    multiSelections = []
                    store.send(reply)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text(L.t("确认选择", store.appLanguage))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    /// 克克的心里话：默认折叠，字体比正文浅小
    private func thinkingDisclosure(_ thinking: String) -> some View {
        DisclosureGroup(isExpanded: $showThinking) {
            Text(thinking)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.9))
                .padding(.top, 3)
                .padding(.horizontal, 2)
        } label: {
            Text(String(format: L.t("👀 %@的心里话", store.appLanguage), PersonaStore.persona(for: store.personaId).name))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .tint(Theme.textSecondary)
        .padding(.horizontal, 4)
    }
}

/// 自动换行布局（选项多时自动折行）
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let maxH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += maxH
            if i > 0 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for (i, row) in rows.enumerated() {
            if i > 0 { y += spacing }
            var x = bounds.minX
            let maxH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for sub in row {
                let size = sub.sizeThatFits(.unspecified)
                sub.place(at: CGPoint(x: x, y: y + (maxH - size.height) / 2),
                          proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += maxH
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var x: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(sub)
            x += size.width + spacing
        }
        return rows
    }
}

/// 克克正在输入的三个点
struct TypingIndicator: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate * 3) % 3
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.textSecondary.opacity(index == phase ? 1 : 0.35))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.bubbleKeke))
        }
    }
}
