import SwiftUI

struct AnniversaryView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var anniversaries: AnniversaryStore
    @EnvironmentObject var activityLog: ActivityLog
    @State private var showAdd = false
    @State private var editingItem: Anniversary?

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(spacing: 0) {
            Text(L.t("纪念日", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 4)
            Text(L.t("记住每一个重要的日子", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 14)

            if anniversaries.items.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("📅")
                        .font(.system(size: 44))
                    Text(L.t("还没有纪念日", lang))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(anniversaries.upcoming) { item in
                            anniversaryRow(item)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
            }

            Button {
                showAdd = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Text(L.t("添加纪念日", lang))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                .padding(14)
                .glassCard(cornerRadius: 14)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .slideOverCover(isPresented: $showAdd) {
            AnniversaryEditView(mode: .add)
                .environmentObject(store)
                .environmentObject(anniversaries)
                .environmentObject(activityLog)
                .backButtonInset { showAdd = false }
        }
        .slideOverCover(isPresented: Binding(
            get: { editingItem != nil },
            set: { if !$0 { editingItem = nil } }
        )) {
            if let item = editingItem {
                AnniversaryEditView(mode: .edit(item))
                    .environmentObject(store)
                    .environmentObject(anniversaries)
                    .environmentObject(activityLog)
                    .backButtonInset { editingItem = nil }
            }
        }
    }

    private func anniversaryRow(_ item: Anniversary) -> some View {
        Button {
            editingItem = item
        } label: {
            HStack(spacing: 12) {
                Text(item.emoji)
                    .font(.system(size: 30))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        if item.isToday {
                            Text(L.t("今天！", lang))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text(dateString(item.date))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    if !item.note.isEmpty {
                        Text(item.note)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if item.isToday {
                        Text(lang == .en ? "Today" : "就是今天")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text("\(item.daysFromNow)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.accent)
                        Text(L.t("天后", lang))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if item.daysSince > 0 {
                        Text(lang == .en ? "\(item.daysSince)d" : "第\(item.daysSince)天")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(14)
            .glassCard(cornerRadius: 14)
        }
        .contextMenu {
            Button(role: .destructive) {
                anniversaries.remove(id: item.id)
            } label: {
                Label(L.t("删除", lang), systemImage: "trash")
            }
        }
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = lang == .en ? "MMM d, yyyy" : "yyyy年M月d日"
        return f.string(from: date)
    }
}

// MARK: - Add / Edit

struct AnniversaryEditView: View {
    enum Mode {
        case add
        case edit(Anniversary)
    }

    let mode: Mode
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var anniversaries: AnniversaryStore
    @EnvironmentObject var activityLog: ActivityLog
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var isRepeatYearly = true
    @State private var emoji = "🎉"

    private var lang: AppLanguage { store.appLanguage }
    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private let emojiOptions = ["🎉", "❤️", "🎂", "💍", "🌹", "🐱", "⭐️", "🎓", "✈️", "🏠"]

    var body: some View {
        VStack(spacing: 0) {
            Text(isEditing ? L.t("编辑纪念日", lang) : L.t("添加纪念日", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("名称", lang))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        TextField(L.t("比如：在一起的日子", lang), text: $title)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("日期", lang))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t("图标", lang))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                            ForEach(emojiOptions, id: \.self) { e in
                                Button {
                                    emoji = e
                                } label: {
                                    Text(e)
                                        .font(.system(size: 24))
                                        .frame(width: 44, height: 44)
                                        .background(emoji == e ? Theme.accent.opacity(0.2) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("备注", lang))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        TextField(L.t("可选的备注…", lang), text: $note, axis: .vertical)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(3)
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 12)

                    Toggle(L.t("每年重复", lang), isOn: $isRepeatYearly)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(12)
                        .glassCard(cornerRadius: 12)

                    Button {
                        saveItem()
                    } label: {
                        Text(L.t("保存", lang))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.accent : Theme.textSecondary.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if isEditing {
                        Button(role: .destructive) {
                            if case .edit(let item) = mode {
                                anniversaries.remove(id: item.id)
                            }
                            dismiss()
                        } label: {
                            Text(L.t("删除这个纪念日", lang))
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
        .onAppear {
            if case .edit(let item) = mode {
                title = item.title
                date = item.date
                note = item.note
                isRepeatYearly = item.isRepeatYearly
                emoji = item.emoji
            }
        }
    }

    private func saveItem() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if case .edit(var item) = mode {
            item.title = trimmed
            item.date = date
            item.note = note
            item.isRepeatYearly = isRepeatYearly
            item.emoji = emoji
            anniversaries.update(item)
            activityLog.log(.homepage, "编辑了纪念日「\(trimmed)」")
        } else {
            let item = Anniversary(title: trimmed, date: date, note: note, isRepeatYearly: isRepeatYearly, emoji: emoji)
            anniversaries.add(item)
            activityLog.log(.homepage, "添加了纪念日「\(trimmed)」")
        }
        dismiss()
    }
}
