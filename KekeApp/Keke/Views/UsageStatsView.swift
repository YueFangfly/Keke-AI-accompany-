import SwiftUI

/// Token 用量统计页。
///
/// 数据 08-28 就落库了但一直没地方看。这一页是纯读的：不改任何东西，
/// 关掉再打开重新算一遍就是了。
struct UsageStatsView: View {
    @EnvironmentObject var store: ChatStore

    @State private var stats: UsageStats?
    @State private var loading = true

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        Group {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let stats, stats.hasData {
                content(stats)
            } else {
                empty
            }
        }
        .background(Theme.background)
        .task { await reload() }
    }

    // MARK: - 加载

    /// 整个扫描扔到后台去——聊到几万条时在主线程解 JSON 会卡出可见的白屏
    private func reload() async {
        loading = true
        let result = await Task.detached(priority: .userInitiated) {
            UsageStats.collect()
        }.value
        stats = result
        loading = false
    }

    // MARK: - 空态

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 34))
                .foregroundStyle(Theme.textSecondary)
            Text(L.t("还没有用量数据", lang))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Text(L.t("聊几句之后再回来看。更早的老消息没有记录用量，不会出现在这里。", lang))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 正文

    @ViewBuilder
    private func content(_ stats: UsageStats) -> some View {
        Form {
            totalsSection(stats)
            cacheSection(stats)
            if !stats.byModel.isEmpty { modelSection(stats) }
            if stats.byConversation.count > 1 { conversationSection(stats) }
            coverageSection(stats)
        }
        .scrollContentBackground(.hidden)
    }

    private func totalsSection(_ stats: UsageStats) -> some View {
        Section {
            row(L.t("输入", lang), UsageFormat.tokens(stats.overall.usage.input))
            row(L.t("输出", lang), UsageFormat.tokens(stats.overall.usage.output))
            row(L.t("缓存读取", lang), UsageFormat.tokens(stats.overall.usage.cacheRead))
            row(L.t("缓存写入", lang), UsageFormat.tokens(stats.overall.usage.cacheWrite))
            row(L.t("合计", lang), UsageFormat.tokens(stats.overall.usage.total), emphasized: true)
        } header: {
            Text(L.t("Token 总量", lang))
        } footer: {
            Text(L.t("四项互不重叠，加起来就是合计。缓存读取比普通输入便宜得多，缓存写入比普通输入略贵。", lang))
        }
    }

    @ViewBuilder
    private func cacheSection(_ stats: UsageStats) -> some View {
        Section {
            if let share = UsageStats.cacheReadShare(stats.overall.usage) {
                row(L.t("输入里来自缓存的比例", lang), UsageFormat.percent(share), emphasized: true)
            } else {
                row(L.t("输入里来自缓存的比例", lang), "—")
            }
            if let avg = stats.overall.averageDurationMs {
                row(L.t("平均每条耗时", lang), UsageFormat.duration(avg))
            }
            if let avg = stats.overall.averageOutput {
                row(L.t("平均每条输出", lang), "\(avg) tok")
            }
        } header: {
            Text(L.t("缓存与速度", lang))
        } footer: {
            Text(L.t("这个比例是判断 prompt caching 有没有生效的直接证据。长期是 0% 说明缓存一直没命中——通常是人设或工具列表每次都在变，把前缀弄脏了。只有 Claude 会返回缓存用量。", lang))
        }
    }

    private func modelSection(_ stats: UsageStats) -> some View {
        Section(L.t("按模型", lang)) {
            ForEach(stats.byModel) { item in
                breakdownRow(name: item.name, bucket: item.bucket)
            }
        }
    }

    private func conversationSection(_ stats: UsageStats) -> some View {
        Section(L.t("按会话", lang)) {
            ForEach(stats.byConversation) { item in
                breakdownRow(name: item.name, bucket: item.bucket)
            }
        }
    }

    private func coverageSection(_ stats: UsageStats) -> some View {
        Section {
            row(L.t("统计到的回复", lang), "\(stats.overall.replies)")
            if stats.repliesWithoutUsage > 0 {
                row(L.t("没有用量数据的回复", lang), "\(stats.repliesWithoutUsage)")
            }
        } header: {
            Text(L.t("统计范围", lang))
        } footer: {
            Text(L.t("只统计 AI 的回复。2026-08-28 之前的消息、报错的那些、以及不返回用量的中转站，都没有数据可统计，所以上面的数字是下限而不是全部。", lang))
        }
    }

    // MARK: - 行

    private func row(_ title: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(emphasized ? .subheadline.weight(.semibold).monospacedDigit()
                                 : .subheadline.monospacedDigit())
                .foregroundStyle(emphasized ? Theme.textPrimary : Theme.textSecondary)
        }
    }

    private func breakdownRow(name: String, bucket: UsageStats.Bucket) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(UsageFormat.tokens(bucket.usage.total))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(detail(for: bucket))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 1)
    }

    private func detail(for bucket: UsageStats.Bucket) -> String {
        var parts = [
            L.count(bucket.replies, "%d 条", "%d msgs", lang),
            "↑\(UsageFormat.tokens(bucket.usage.input)) ↓\(UsageFormat.tokens(bucket.usage.output))",
        ]
        if let share = UsageStats.cacheReadShare(bucket.usage), share > 0 {
            parts.append(L.t("缓存 ", lang) + UsageFormat.percent(share))
        }
        if let avg = bucket.averageDurationMs {
            parts.append(UsageFormat.duration(avg))
        }
        return parts.joined(separator: "  ·  ")
    }
}
