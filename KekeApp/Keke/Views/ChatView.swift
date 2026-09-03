import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var store: ChatStore
    @ObservedObject private var approval = MCPApprovalGate.shared
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
    @State private var showKaomoji = false
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
                if showKaomoji {
                    KaomojiPickerView(lang: store.appLanguage) { kaomoji in
                        input += kaomoji
                    }
                }

                inputBar
            }
            .padding(.bottom, max(0, keyboard.height - bottomSafeInset))
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // 标了「执行前问我一声」的 MCP 工具，真正调用前在这里停一下。
        // 超时会自动按拒绝处理（见 MCPApprovalGate）
        .alert(L.t("要执行这个工具吗？", store.appLanguage),
               isPresented: Binding(get: { approval.pending != nil },
                                    set: { if !$0 { approval.resolve(false) } })) {
            Button(L.t("允许", store.appLanguage)) { approval.resolve(true) }
            Button(L.t("不要", store.appLanguage), role: .cancel) { approval.resolve(false) }
        } message: {
            if let ask = approval.pending {
                Text("\(ask.server) · \(ask.tool)\n\n\(ask.arguments)")
            }
        }
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

    /// 当前实际渲染的消息（最近 displayLimit 条）。
    /// store.visibleMessages 已经把重新生成产生的旧版本挡掉了
    private var visibleMessages: [ChatMessage] {
        let all = store.visibleMessages
        return all.count > displayLimit ? Array(all.suffix(displayLimit)) : all
    }

    /// 流式气泡的固定 id，用来往下滚。消息用的是 UUID，不会跟它撞上
    private static let streamingBubbleID = "streaming-bubble"

    /// 正在流的这段里，能给用户看的部分（选项标签只出来一半的要挡掉）
    private var streamingBody: String {
        ClaudeService.visibleStreamingText(store.streamingText)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.visibleMessages.count > displayLimit {
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
                        Group {
                            if streamingBody.isEmpty {
                                // 还没开口：转圈 + 当前在干嘛（搜索中/调工具中…）
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
                            } else {
                                // 已经开口了：用跟真实气泡一样的样式，收完之后原地变成一条消息，
                                // 视觉上不会跳一下
                                HStack {
                                    // 跟落地后的气泡用同一套渲染，收完的瞬间不会重排
                                    MarkdownText(text: streamingBody)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 9)
                                        .background(
                                            RoundedRectangle(cornerRadius: 17)
                                                .fill(Theme.bubbleKeke)
                                        )
                                    Spacer(minLength: 48)
                                }
                                .padding(.horizontal, 14)
                            }
                        }
                        .id(Self.streamingBubbleID)
                    }
                }
                .padding(.vertical, 12)
            }
            .onTapGesture { inputFocused = false }
            // 触发条件用原始条数而不是显示条数：重新生成是「藏一条 + 加一条」，
            // 显示条数前后没变，拿它当触发的话这次滚动就不会发生
            .onChange(of: store.messages.count) { _ in
                // 滚到当前显示的最后一条。重新生成产生的旧版本是隐藏的，
                // 滚过去等于什么也没做
                if let last = visibleMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: store.streamingText) { _ in
                // 字往外冒的时候跟着往下滚，不然新出来的字会跑到屏幕外面。
                // 这里不加动画：每几十毫秒一次，加了动画会互相打架变成抖动
                proxy.scrollTo(Self.streamingBubbleID, anchor: .bottom)
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
                } else if let last = visibleMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    /// 从搜索跳转过来时，如果目标比当前窗口更早，就把窗口撑到能显示它
    private func ensureVisible(_ id: UUID) {
        let shown = store.visibleMessages
        guard let index = shown.firstIndex(where: { $0.id == id }) else { return }
        let fromEnd = shown.count - index
        if fromEnd > displayLimit { displayLimit = shown.count }
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
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 12)
                                .frame(minWidth: 38, minHeight: 38)
                                .background(Capsule().fill(Theme.card))
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
                withAnimation(.easeOut(duration: 0.15)) {
                    showStickers.toggle()
                    if showStickers { showKaomoji = false }
                }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 18))
                    .foregroundStyle(showStickers ? Theme.accent : Theme.textSecondary)
                    .frame(width: 24, height: 38)
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    showKaomoji.toggle()
                    if showKaomoji { showStickers = false }
                }
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 14))
                    .foregroundStyle(showKaomoji ? Theme.accent : Theme.textSecondary)
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
    @EnvironmentObject var voiceCall: VoiceCallService
    @ObservedObject private var speech = ChatSpeech.shared
    let message: ChatMessage
    @State private var showThinking = false
    @State private var showReasoning = false
    @State private var multiSelections: Set<String> = []
    @State private var showEditor = false
    @State private var editDraft = ""

    private var isLatestKekeMessage: Bool {
        guard message.role == .keke else { return false }
        return store.visibleMessages.last(where: { $0.role == .keke })?.id == message.id
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
                if let reasoning = message.reasoning, !reasoning.isEmpty {
                    reasoningDisclosure(reasoning)
                }
                if !displayText.isEmpty {
                    Group {
                        if message.role == .user {
                            // 用户自己打的字原样显示：把 **xx** 渲染成加粗会很意外
                            Text(displayText)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                        } else {
                            MarkdownText(text: displayText)
                        }
                    }
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
                if versionCount > 1 {
                    versionSwitcher
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
                    if message.role == .keke, !message.text.isEmpty,
                       (message.kind ?? .conversation) == .conversation {
                        Button {
                            Task { await speech.toggle(message, voiceCall: voiceCall) }
                        } label: {
                            if speech.preparing == message.id {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: speech.speakingID == message.id
                                      ? "stop.circle" : "speaker.wave.2")
                                    .font(.system(size: 11))
                                    .foregroundStyle(speech.speakingID == message.id
                                                     ? Theme.accent : Theme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if store.showUsage, let line = usageLine {
                    Text(line)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
                if store.showUsage, let trace = traceLine {
                    Text(trace)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary.opacity(0.8))
                        .textSelection(.enabled)
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
            if store.canRegenerate(message) {
                Button {
                    store.regenerate(message.id)
                } label: {
                    Label(L.t("重新生成", store.appLanguage), systemImage: "arrow.clockwise")
                }
            }
            if message.role == .user, !store.isThinking {
                Button {
                    editDraft = message.text
                    showEditor = true
                } label: {
                    Label(L.t("改一下重发", store.appLanguage), systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                store.deleteMessage(message.id)
            } label: {
                Label(L.t("删除", store.appLanguage), systemImage: "trash")
            }
        }
        .alert(L.t("改一下重发", store.appLanguage), isPresented: $showEditor) {
            TextField("", text: $editDraft)
            Button(L.t("取消", store.appLanguage), role: .cancel) {}
            Button(L.t("重发", store.appLanguage)) {
                store.editAndResend(message.id, newText: editDraft)
            }
        } message: {
            Text(L.t("这条之后的消息会被删掉，重新问一遍", store.appLanguage))
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

    /// 这条消息所在组的所有版本（重新生成过才会多于一个）
    private var siblingVersions: [ChatMessage] { store.versions(of: message) }
    private var versionCount: Int { siblingVersions.count }

    /// ‹ 2/3 › 版本切换。只有重新生成过的消息才会出现
    private var versionSwitcher: some View {
        let index = siblingVersions.firstIndex { $0.id == message.id } ?? 0
        return HStack(spacing: 10) {
            Button {
                step(to: index - 1)
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
            }
            .disabled(index == 0)

            Text("\(index + 1)/\(versionCount)")
                .font(.caption2.monospacedDigit())

            Button {
                step(to: index + 1)
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .disabled(index == versionCount - 1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.card.opacity(0.7)))
    }

    private func step(to index: Int) {
        guard siblingVersions.indices.contains(index),
              let groupId = message.groupId else { return }
        store.selectVersion(groupId: groupId, version: siblingVersions[index].versionIndex)
    }

    /// 模型的思考过程：默认折叠，点一下展开。
    /// 排在正文气泡上面，跟 API 返回的顺序一致——先想，后说
    /// 路由这轮做了什么、真跑了哪些工具。
    ///
    /// **这些字段只在界面上出现，永远不会进 messages**——
    /// `ChatMessage.Payload` 里根本没有 trace，结构上就发不出去。
    /// 会有这条硬约束是因为：模型看多了这种格式会学着自己编工具调用
    private var traceLine: String? {
        guard message.role == .keke, let trace = message.trace else { return nil }
        var parts: [String] = []
        if trace.routedOnDevice {
            parts.append("端上路由 \(trace.routeMs)ms")
            if !trace.needsMemory { parts.append("未注入记忆") }
            if let suggested = trace.suggestedTool { parts.append("建议 \(suggested)") }
        }
        if !trace.toolsRun.isEmpty {
            parts.append("调用 " + trace.toolsRun.joined(separator: "、"))
        }
        return parts.isEmpty ? nil : "⚙︎ " + parts.joined(separator: "  ·  ")
    }

    /// 界面上显示的正文。正则规则在这里再走一遍——
    /// 这一遍**包括 visualOnly 的规则**（发给模型那一遍会跳过它们）。
    /// 这正是 visualOnly 的意义：藏起来只给自己看，不改真正进历史的内容
    private var displayText: String {
        PersonaTuningEngine.applyRegex(message.text, rules: store.tuning.regexRules,
                                       isUser: message.role == .user, visual: true)
    }

    /// 气泡下面那行小字：模型 · token · 耗时。
    /// 只有 AI 的回复、且真的记了用量的才有；老消息和用户消息返回 nil，不占位置
    private var usageLine: String? {
        guard message.role == .keke else { return nil }
        var parts: [String] = []
        if let model = message.model, !model.isEmpty { parts.append(model) }
        if let usage = message.usage, !usage.isEmpty {
            parts.append("↑\(UsageFormat.tokens(usage.input + usage.cacheRead + usage.cacheWrite))"
                         + " ↓\(UsageFormat.tokens(usage.output))")
            // 缓存命中了才提，没命中时显示"缓存 0%"只是噪音
            if usage.cacheRead > 0, let share = UsageStats.cacheReadShare(usage) {
                parts.append("⚡︎" + UsageFormat.percent(share))
            }
        }
        if let ms = message.durationMs, ms > 0 { parts.append(UsageFormat.duration(ms)) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private func reasoningDisclosure(_ reasoning: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showReasoning.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text(L.t("思考过程", store.appLanguage))
                        .font(.caption2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(showReasoning ? 90 : 0))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            if showReasoning {
                Text(reasoning)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.95))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card.opacity(0.6)))
        .overlay(
            // 描一圈浅边，跟正文气泡区分开——这段不是她说的话，是她想的
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.textSecondary.opacity(0.15), lineWidth: 1)
        )
    }

    /// 通话记录的完整转写：默认折叠，字体比正文浅小。
    /// 心里话功能已经去掉了，现在这个字段只装通话转写
    private func thinkingDisclosure(_ thinking: String) -> some View {
        DisclosureGroup(isExpanded: $showThinking) {
            Text(thinking)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.9))
                .padding(.top, 3)
                .padding(.horizontal, 2)
        } label: {
            Text(L.t("📞 通话转写", store.appLanguage))
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
