import SwiftUI

/// 人设调教：按深度注入、正则、预设开场、世界书。
///
/// 这四样都是**给已经写好的人设加杠杆**的，不是替代人设本身。
/// 人设写什么在「人设」那一页，这里管的是「怎么让它在长对话里不飘」。
struct PersonaTuningView: View {
    @EnvironmentObject var store: ChatStore

    private var lang: AppLanguage { store.appLanguage }
    private var tuning: Binding<PersonaTuning> { $store.tuning }

    var body: some View {
        Form {
            basicSection
            injectionSection
            worldBookSection
            regexSection
            presetSection
            variableHelp
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
    }

    // MARK: - 基础

    private var basicSection: some View {
        Section {
            Stepper(value: tuning.contextMessageSize, in: 0...200, step: 5) {
                HStack {
                    Text(L.t("历史条数上限", lang))
                    Spacer()
                    Text(store.tuning.contextMessageSize == 0
                         ? L.t("不限", lang) : "\(store.tuning.contextMessageSize)")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.subheadline)
            }
            Toggle(L.t("在我的消息后附上当前时间", lang), isOn: tuning.appendCurrentTime)
        } footer: {
            Text(L.t("历史条数设成「不限」就交给上下文压缩管（推荐）。设了具体数字之后，每次只发最近这么多条——压缩仍然照常工作，这只是又加了一道硬上限。", lang))
        }
    }

    // MARK: - 按深度注入

    private var injectionSection: some View {
        Section {
            ForEach(tuning.injections) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $item.enabled) {
                        TextField(L.t("要注入的文字", lang), text: $item.text, axis: .vertical)
                            .font(.caption)
                            .lineLimit(1...4)
                    }
                    Picker(L.t("位置", lang), selection: $item.position) {
                        ForEach(InjectionPosition.allCases) { p in
                            Text(L.t(p.displayName, lang)).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    if item.position == .atDepth {
                        Stepper(value: $item.depth, in: 1...30) {
                            Text(L.count(item.depth, "从最新往前数第 %d 条之前",
                                         "%d messages back from the newest", lang))
                                .font(.caption2)
                        }
                    }
                    Toggle(L.t("以我的身份注入", lang), isOn: $item.asUser)
                        .font(.caption2)
                }
                .padding(.vertical, 2)
            }
            .onDelete { store.tuning.injections.remove(atOffsets: $0) }
            Button(L.t("加一条注入", lang)) { store.tuning.injections.append(PromptInjection()) }
        } header: {
            Text(L.t("按深度注入", lang))
        } footer: {
            Text(L.t("长对话里 system prompt 离最新消息越来越远，人设容易飘。往最近几条中间插一句提醒，比一直往 system prompt 后面加有效得多。深度 4 大概就是「最近两个来回之前」。", lang))
        }
    }

    // MARK: - 世界书

    private var worldBookSection: some View {
        Section {
            ForEach(tuning.worldBook) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $item.enabled) {
                        TextField(L.t("条目名", lang), text: $item.name).font(.subheadline)
                    }
                    TextField(L.t("触发词，用逗号隔开", lang), text: Binding(
                        get: { item.keywords.joined(separator: "，") },
                        set: { item.keywords = $0.split(whereSeparator: { ",，".contains($0) })
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty } }))
                        .font(.caption)
                        .disabled(item.constantActive)
                    TextField(L.t("设定内容", lang), text: $item.content, axis: .vertical)
                        .font(.caption)
                        .lineLimit(1...6)
                    Toggle(L.t("常驻（不看触发词，每轮都注入）", lang), isOn: $item.constantActive)
                        .font(.caption2)
                    if !item.constantActive {
                        Stepper(value: $item.scanDepth, in: 1...30) {
                            Text(L.count(item.scanDepth, "往前扫 %d 条找触发词",
                                         "Scan %d messages back", lang)).font(.caption2)
                        }
                        Toggle(L.t("区分大小写", lang), isOn: $item.caseSensitive).font(.caption2)
                    }
                    Stepper(value: $item.priority, in: -10...10) {
                        Text(L.t("优先级", lang) + " \(item.priority)").font(.caption2)
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { store.tuning.worldBook.remove(atOffsets: $0) }
            Button(L.t("加一条设定", lang)) { store.tuning.worldBook.append(WorldBookEntry()) }
        } header: {
            Text(L.t("世界书", lang))
        } footer: {
            Text(L.t("命中触发词才注入的设定。一百条设定里每轮通常只用得上两三条，比全塞进人设省得多。命中的条目会跟记忆块一起发过去，不会混进对话历史。", lang))
        }
    }

    // MARK: - 正则

    private var regexSection: some View {
        Section {
            ForEach(tuning.regexRules) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $item.enabled) {
                        TextField(L.t("规则名", lang), text: $item.name).font(.subheadline)
                    }
                    TextField(L.t("匹配（正则）", lang), text: $item.pattern)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField(L.t("替换成", lang), text: $item.replacement)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack {
                        Toggle(L.t("我发的", lang), isOn: $item.onInput).font(.caption2)
                        Toggle(L.t("TA 回的", lang), isOn: $item.onOutput).font(.caption2)
                    }
                    Toggle(L.t("只改显示", lang), isOn: $item.visualOnly).font(.caption2)
                }
                .padding(.vertical, 2)
            }
            .onDelete { store.tuning.regexRules.remove(atOffsets: $0) }
            Button(L.t("加一条规则", lang)) { store.tuning.regexRules.append(RegexRule()) }
        } header: {
            Text(L.t("正则处理", lang))
        } footer: {
            Text(L.t("「只改显示」是关键：打开时只影响你看到的样子，发给模型的和存进记录的还是原文；关掉才会真的改内容。想把某些标记藏起来又不想动历史，就用它。写错的正则会被跳过，不会让聊天出错。", lang))
        }
    }

    // MARK: - 预设开场

    private var presetSection: some View {
        Section {
            ForEach(tuning.presetMessages) { $item in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $item.enabled) {
                        TextField(L.t("内容", lang), text: $item.text, axis: .vertical)
                            .font(.caption)
                            .lineLimit(1...4)
                    }
                    Picker("", selection: $item.isUser) {
                        Text(L.t("我说的", lang)).tag(true)
                        Text(L.t("TA 说的", lang)).tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 2)
            }
            .onDelete { store.tuning.presetMessages.remove(atOffsets: $0) }
            Button(L.t("加一句开场", lang)) { store.tuning.presetMessages.append(PresetMessage()) }
        } header: {
            Text(L.t("预设开场", lang))
        } footer: {
            Text(L.t("排在所有真实对话之前发给模型，用来给语气定调。不会显示在聊天里，也不占聊天记录。", lang))
        }
    }

    private var variableHelp: some View {
        Section(L.t("可用变量", lang)) {
            Text("{{user}} {{char}} {{time}} {{date}}")
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textSecondary)
            Text(L.t("人设、注入、世界书、预设开场里都能用。认不出来的变量会原样留着，方便看出是不是写错了。", lang))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
