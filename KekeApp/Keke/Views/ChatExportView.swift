import SwiftUI
import UIKit

/// 把一段聊天导出成一张长图，用来分享。
///
/// 跟备份是两件事：备份是给自己留的、能还原回来的**数据**；
/// 长图是给别人看的**样子**，不含任何能还原的东西。
///
/// 张数上限是刻意的：`ImageRenderer` 一次画一张完整位图，
/// 上千条渲出来是几百 MB，会被系统直接杀掉。宁可分两次导。
struct ChatExportView: View {
    @EnvironmentObject var store: ChatStore
    var onClose: () -> Void

    /// 一次最多画这么多条。再多就该分次导了
    static let maxCount = 240
    private static let choices = [30, 60, 120, maxCount]

    @State private var count = 60
    @State private var rendering = false
    @State private var rendered: URL?
    @State private var problem: String?

    private var lang: AppLanguage { store.appLanguage }

    /// 要导的那几条。系统提示不进长图——它是给自己看的排查信息，不是聊天
    private var picked: [ChatMessage] {
        Array(store.messages
            .filter { ($0.kind ?? .conversation) == .conversation && !$0.text.isEmpty }
            .suffix(count))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("导出长图")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 18)

                picker
                summary
                actions

                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(Theme.crabRed)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .backButtonInset(onBack: onClose)
    }

    private var picker: some View {
        Picker("", selection: $count) {
            ForEach(Self.choices, id: \.self) { n in
                Text("最近 \(n) 条").tag(n)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: count) { _ in rendered = nil }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("这次会画 \(picked.count) 条")
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Text("图里只有名字、文字和时间。API Key、记忆、trace 都不在里面")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var actions: some View {
        if rendering {
            ProgressView().padding(.vertical, 12)
        } else if let url = rendered {
            ShareLink(item: url) {
                Text("分享这张图")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
            }
            Button {
                rendered = nil
            } label: {
                Text("重新生成")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Button {
                render()
            } label: {
                Text("生成")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
            }
            .disabled(picked.isEmpty)
            .opacity(picked.isEmpty ? 0.4 : 1)
        }
    }

    private func render() {
        let messages = picked
        guard !messages.isEmpty else { return }
        rendering = true
        problem = nil

        let canvas = ChatExportCanvas(
            title: PersonaStore.persona(for: store.personaId).name,
            myName: store.myName.isEmpty ? "我" : store.myName,
            messages: messages)

        // ImageRenderer 在渲染一棵真的 SwiftUI 视图树，只能在主线程上跑。
        // 但要让上面的转圈先转起来，所以推到下一个调度周期再画
        Task { @MainActor in
            let renderer = ImageRenderer(content: canvas)
            renderer.scale = 2
            renderer.proposedSize = ProposedViewSize(width: 390, height: nil)
            defer { rendering = false }
            guard let image = renderer.uiImage, let data = image.pngData() else {
                problem = "画不出来。可能是这次条数太多了，换少一点试试"
                ErrorLog.shared.record(source: "导出长图", message: "ImageRenderer 没给出图")
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("keke-chat-\(Int(Date().timeIntervalSince1970)).png")
            do {
                try data.write(to: url, options: .atomic)
                rendered = url
            } catch {
                problem = error.localizedDescription
                ErrorLog.shared.record(source: "导出长图", message: error.localizedDescription)
            }
        }
    }
}

/// 长图本身。**不复用 `MessageBubble`**：那个要一堆 EnvironmentObject、
/// 还带按钮和手势，塞进 ImageRenderer 里既跑不起来也画不对
struct ChatExportCanvas: View {
    let title: String
    let myName: String
    let messages: [ChatMessage]

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)

            ForEach(messages) { message in
                row(message)
            }

            Text("由克克导出 · " + Self.stamp.string(from: Date()))
                .font(.system(size: 9))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .padding(16)
        .frame(width: 390)
        .background(Theme.background)
    }

    private func row(_ message: ChatMessage) -> some View {
        let mine = message.role == .user
        return HStack(alignment: .top, spacing: 0) {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                Text(mine ? myName : title)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textSecondary)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(mine ? Theme.bubbleUser : Theme.bubbleKeke))
                Text(Self.stamp.string(from: message.date))
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.textSecondary)
            }
            if !mine { Spacer(minLength: 48) }
        }
    }
}
