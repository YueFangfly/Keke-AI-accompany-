import SwiftUI

/// 「闹钟」页：克克在固定时间来叫你（本地通知实现）
struct AlarmView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var alarmService: AlarmService

    @State private var showAdd = false
    @State private var newHour = 8
    @State private var newMinute = 0
    @State private var newLabel = ""
    @State private var newRepeats = true
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            addButton

            if alarmService.alarms.isEmpty {
                emptyState
            } else {
                alarmList
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $showAdd) {
            addSheet
        }
    }

    private var addButton: some View {
        Button {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
            newHour = comps.hour ?? 8
            newMinute = comps.minute ?? 0
            showAdd = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text(L.t("加一个克克闹钟", store.appLanguage))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("⏰🐱")
                .font(.system(size: 40))
            Text(L.t("还没有闹钟\n设一个，到点克克会来叫你\n（叫你的那句话是它自己写的）", store.appLanguage))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var alarmList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(alarmService.alarms) { alarm in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(alarm.timeText)
                                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                                    .foregroundStyle(alarm.enabled ? Theme.textPrimary : Theme.textSecondary)
                                Text(L.t(alarm.repeatsDaily ? "每天" : "响一次", store.appLanguage))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if !alarm.label.isEmpty {
                                Text(alarm.label)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            Text("“\(alarm.kekeText)”")
                                .font(.caption2)
                                .lineLimit(2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { alarm.enabled },
                            set: { _ in Task { await alarmService.toggle(alarm) } }
                        ))
                        .labelsHidden()
                        .tint(Theme.accent)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 15).fill(Theme.card))
                    .contextMenu {
                        Button(role: .destructive) {
                            alarmService.delete(alarm)
                        } label: {
                            Label(L.t("删除这个闹钟", store.appLanguage), systemImage: "trash")
                        }
                    }
                }

                Text(L.t("闹钟用通知实现：到点会弹出克克写的一句话。\n声音是通知声，不会像系统闹钟一直响；静音模式下可能只亮屏。", store.appLanguage))
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 6)
            }
            .padding(14)
        }
    }

    /// 时间选择：用两列独立的"时/分"滚轮，比 DatePicker(.wheel) 更稳，
    /// 在部分 Xcode/iOS 组合下 DatePicker 的滚轮会卡住划不动
    private var timePicker: some View {
        HStack(spacing: 4) {
            Picker(L.t("时", store.appLanguage), selection: $newHour) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d", hour)).tag(hour)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Text(":")
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)

            Picker(L.t("分", store.appLanguage), selection: $newMinute) {
                ForEach(0..<60, id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 150)
        .clipped()
        .padding(.horizontal, 30)
    }

    private var addSheet: some View {
        VStack(spacing: 18) {
            Text(L.t("克克闹钟", store.appLanguage))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)

            timePicker

            TextField(L.t("备注：要干嘛（可以不填）", store.appLanguage), text: $newLabel)
                .font(.subheadline)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.background))
                .padding(.horizontal, 18)

            Toggle(L.t("每天重复", store.appLanguage), isOn: $newRepeats)
                .tint(Theme.accent)
                .padding(.horizontal, 18)

            Button {
                saving = true
                Task {
                    await alarmService.add(
                        hour: newHour,
                        minute: newMinute,
                        label: newLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                        repeatsDaily: newRepeats,
                        store: store
                    )
                    saving = false
                    showAdd = false
                    newLabel = ""
                }
            } label: {
                HStack(spacing: 8) {
                    if saving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(L.t(saving ? "克克在想叫你的话…" : "保存", store.appLanguage))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
            }
            .disabled(saving)
            .padding(.horizontal, 18)

            Spacer()
        }
        .presentationDetents([.medium])
        .background(Theme.card)
    }
}
