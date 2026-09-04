import SwiftUI
import PhotosUI

// MARK: - 捕捉栏

/// 记碎片的那一条。**默认动作是「扔一句」，不是「写一篇」**——
/// 写成篇的按钮在旁边，小一号，因为那本来就是少数时候才做的事。
struct FragmentCaptureBar: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var fragments: FragmentStore
    @EnvironmentObject var voiceCall: VoiceCallService
    @ObservedObject private var dictation = VoiceFragment.shared

    /// 点「写成篇」时调用
    var onWriteEntry: () -> Void

    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if dictation.recording {
                dictationRow
            } else {
                inputRow
            }
            if let problem = dictation.problem {
                Text(problem)
                    .font(.caption2)
                    .foregroundStyle(Theme.crabRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onWriteEntry) {
                Text("想写长一点 · 写成一篇日记")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.backgroundDeep)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await attach(item) }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            TextField("记一句…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.subheadline)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.background))

            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
            }

            Button {
                Task { await dictation.start(callState: voiceCall.state) }
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
            }

            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    fragments.addText(text)
                    text = ""
                    focused = false
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    /// 正在听的时候：把听到的字实时显示出来，让人知道它没在装样子
    private var dictationRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.crabRed)
                .frame(width: 8, height: 8)
            Text(dictation.transcript.isEmpty ? "在听……" : dictation.transcript)
                .font(.subheadline)
                .foregroundStyle(dictation.transcript.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                dictation.cancel()
            } label: {
                Text("取消")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Button {
                if let said = dictation.stop() { fragments.addVoice(transcript: said) }
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.crabRed)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.background))
    }

    /// 拿**原始数据**给 EXIF 用：`Attachments.saveImage` 重编码之后拍摄时间和 GPS 就没了
    private func attach(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            ErrorLog.shared.record(source: "碎片", message: "这张照片读不出来，换一张试试")
            return
        }
        fragments.addPhoto(image, original: data, text: text)
        text = ""
    }
}

// MARK: - 碎片流

/// 攒着的碎片，按天分组。整理成什么是后面阶段的事，这里只负责让它看得见
struct FragmentStreamSection: View {
    @EnvironmentObject var fragments: FragmentStore
    @EnvironmentObject var cards: CardStore
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var pipeline: DiaryPipeline
    /// 折叠时只显示最近这么多天
    private static let collapsedDays = 2

    @State private var expanded = false
    @State private var organizingAll = false

    /// 还没整理成卡片的那些
    private var pending: [Fragment] {
        let done = cards.organizedFragmentIDs
        return fragments.sorted.filter { !done.contains($0.id) }
    }

    private var days: [(day: Date, items: [Fragment])] {
        let all = fragments.byDay
        return expanded ? all : Array(all.prefix(Self.collapsedDays))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if fragments.fragments.isEmpty {
                Text("还没有碎片。下面那行随手记一句，不用组织语言")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(days, id: \.day) { group in
                    dayBlock(group.day, group.items)
                }
                if fragments.byDay.count > Self.collapsedDays {
                    Button {
                        withAnimation { expanded.toggle() }
                    } label: {
                        Text(expanded ? "收起" : "更早的碎片（\(fragments.byDay.count - Self.collapsedDays) 天）")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // 打开日记页也算一次「到期任务处理」的时机
        .task { pipeline.kick() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("碎片")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            if fragments.todayCount > 0 {
                Text("今天 \(fragments.todayCount)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if organizingAll {
                ProgressView().controlSize(.mini)
            } else if !pending.isEmpty {
                Button {
                    let todo = pending
                    organizingAll = true
                    Task {
                        await CardGenerator.organizeAll(todo, into: cards, store: store)
                        organizingAll = false
                    }
                } label: {
                    Text("整理 \(pending.count) 条")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dayBlock(_ day: Date, _ items: [Fragment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(FragmentFormat.day(day))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            ForEach(items) { fragment in
                FragmentRow(fragment: fragment)
            }
        }
    }
}

/// 一条碎片。刻意做得很轻——它不是卡片，只是一条随手记
struct FragmentRow: View {
    @EnvironmentObject var fragments: FragmentStore
    @EnvironmentObject var cards: CardStore
    @EnvironmentObject var store: ChatStore
    let fragment: Fragment

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                if let path = fragment.imagePath, let image = Attachments.loadImage(named: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if !fragment.summary.isEmpty {
                    Text(fragment.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                }
                metaLine
                cardStrip
            }
        }
        .padding(11)
        .glassCard(cornerRadius: 13)
        .contextMenu {
            if fragment.imagePath != nil {
                Button("重新读一遍这张图") { fragments.reanalyze(fragment) }
            }
            if let card = cards.cards(forFragment: fragment.id).first {
                // 删卡片不动碎片：碎片是原始记录，卡片只是它的一种整理方式
                Button("重新整理") {
                    cards.delete(card.id)
                    Task { await CardGenerator.organize(fragment, into: cards, store: store) }
                }
            }
            Button(role: .destructive) {
                fragments.delete(fragment.id)
            } label: {
                Text("删掉")
            }
        }
    }

    /// 这条碎片被整理成了什么。卡片就挂在碎片下面——
    /// **来源链是看得见的**，而不是变成另一个页面里一张来路不明的卡片
    @ViewBuilder
    private var cardStrip: some View {
        if let card = cards.cards(forFragment: fragment.id).first {
            CardChip(card: card)
        } else if cards.working.contains(fragment.id) {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("整理中…")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Button {
                Task { await CardGenerator.organize(fragment, into: cards, store: store) }
            } label: {
                Text("整理成卡片")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var icon: String {
        switch fragment.kind {
        case .text: return "text.alignleft"
        case .photo: return "photo"
        case .voice: return "waveform"
        }
    }

    @ViewBuilder
    private var metaLine: some View {
        HStack(spacing: 8) {
            Text(FragmentFormat.time(fragment.occurredAt))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)

            if fragments.analyzing.contains(fragment.id) {
                ProgressView().controlSize(.mini)
            } else if let analysis = fragment.analysis {
                if analysis.failure != nil {
                    Text("没读懂这张图")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.crabRed)
                }
                if analysis.capturedAt != nil {
                    Label("拍摄时间", systemImage: "clock")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
                if analysis.hasLocation {
                    Label("有位置", systemImage: "mappin")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// 碎片列表用的日期文字。固定用中文格式，跟日记那边的 `.formatted` 分开——
/// 碎片要的是「今天 / 昨天」这种口语感，不是完整日期
enum FragmentFormat {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return dayFormatter.string(from: date)
    }

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
}

// MARK: - 卡片

/// 挂在碎片下面的那张卡片。做得比碎片重一点点——它是**整理过**的东西
struct CardChip: View {
    @EnvironmentObject var cards: CardStore
    let card: TimelineCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: card.kind.icon)
                    .font(.system(size: 9))
                Text(card.kind.displayName)
                    .font(.system(size: 9))
                if card.byRule {
                    // 用户有权知道这张是「没调通模型时凑合出来的」
                    Text("规则整理")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                if card.kind == .todo {
                    Button {
                        cards.toggleDone(card.id)
                    } label: {
                        Image(systemName: card.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(card.done ? Theme.accent : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(Theme.accent)

            Text(card.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .strikethrough(card.done)

            if !card.detail.isEmpty, card.detail != card.title {
                Text(card.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
            }
            if !card.orderedFields.isEmpty {
                Text(card.orderedFields.map { "\($0.label)：\($0.value)" }.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            if !card.tags.isEmpty {
                Text(card.tags.map { "#" + $0 }.joined(separator: " "))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent.opacity(0.8))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.background))
    }
}
