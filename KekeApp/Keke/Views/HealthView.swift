import SwiftUI

/// 「心跳」页：读取健康数据，可以发给克克看
struct HealthView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var health: HealthService
    var switchToChat: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !HealthService.isAvailable {
                    infoCard(text: L.t("这台设备不支持健康数据", store.appLanguage))
                } else if !health.authorized {
                    authCard
                } else {
                    cards
                    sendButton
                    Text(L.t("下拉可以刷新数据", store.appLanguage))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .refreshable { await health.refresh() }
        .task {
            if health.authorized { await health.refresh() }
        }
    }

    private var authCard: some View {
        VStack(spacing: 14) {
            Text("🐱")
                .font(.system(size: 44))
            Text(L.t("让克克知道你的步数、睡眠和身体状态，\n更好地照顾你", store.appLanguage))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
            Button {
                Task { await health.requestAuthorization() }
            } label: {
                Text(L.t("允许克克读取健康数据", store.appLanguage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.accent))
            }
            Text(L.t("数据只在你自己的手机上，不会上传到别的地方", store.appLanguage))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
    }

    private var cards: some View {
        let lang = store.appLanguage
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            HealthCard(icon: "figure.walk", color: .orange, title: L.t("今日步数", lang),
                       value: health.steps.map { "\(Int($0))" } ?? "—", unit: L.t("步", lang))
            HealthCard(icon: "location.fill", color: Theme.accent, title: L.t("步行距离", lang),
                       value: health.distanceKM.map { String(format: "%.1f", $0) } ?? "—", unit: L.t("公里", lang))
            HealthCard(icon: "bed.double.fill", color: .purple, title: L.t("昨晚睡眠", lang),
                       value: health.sleepHours.map { String(format: "%.1f", $0) } ?? "—", unit: L.t("小时", lang))
            HealthCard(icon: "heart.fill", color: .red, title: L.t("最近心率", lang),
                       value: health.heartRate.map { "\(Int($0))" } ?? "—", unit: L.t("次/分", lang))
            HealthCard(icon: "drop.fill", color: .pink, title: L.t("月经记录", lang),
                       value: periodText, unit: "")
        }
    }

    private var periodText: String {
        guard let date = health.lastPeriodDate else { return L.t("无记录", store.appLanguage) }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        return days == 0 ? L.t("今天", store.appLanguage) : "\(days) \(L.t("天前", store.appLanguage))"
    }

    private var sendButton: some View {
        Button {
            store.send(health.summaryForKeke(userName: store.myName))
            switchToChat()
        } label: {
            HStack(spacing: 8) {
                Text("🐱")
                Text(L.t("发给克克看看", store.appLanguage))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent))
        }
        .disabled(store.isThinking || store.apiKey.isEmpty)
        .opacity(store.isThinking || store.apiKey.isEmpty ? 0.5 : 1)
    }

    private func infoCard(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
    }
}

struct HealthCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }
}
