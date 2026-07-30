import SwiftUI

struct ExchangeRateView: View {
    @EnvironmentObject var store: ChatStore
    @State private var baseCurrency = "CNY"
    @State private var amount = "100"
    @State private var rates: [String: Double] = [:]
    @State private var isLoading = false
    @State private var lastUpdate: Date?

    private var lang: AppLanguage { store.appLanguage }

    private let currencies: [(code: String, zh: String, en: String, flag: String)] = [
        ("CNY", "人民币", "Chinese Yuan", "🇨🇳"),
        ("GBP", "英镑", "British Pound", "🇬🇧"),
        ("USD", "美元", "US Dollar", "🇺🇸"),
        ("EUR", "欧元", "Euro", "🇪🇺"),
        ("JPY", "日元", "Japanese Yen", "🇯🇵"),
        ("KRW", "韩元", "Korean Won", "🇰🇷"),
        ("HKD", "港币", "Hong Kong Dollar", "🇭🇰"),
        ("SGD", "新加坡元", "Singapore Dollar", "🇸🇬"),
        ("AUD", "澳元", "Australian Dollar", "🇦🇺"),
        ("CAD", "加拿大元", "Canadian Dollar", "🇨🇦"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text(L.t("实时汇率", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)

            HStack(spacing: 10) {
                Menu {
                    ForEach(currencies, id: \.code) { c in
                        Button("\(c.flag) \(c.code)") { baseCurrency = c.code }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(flagFor(baseCurrency))
                        Text(baseCurrency)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassCard(cornerRadius: 10)
                }

                TextField("100", text: $amount)
                    .keyboardType(.decimalPad)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassCard(cornerRadius: 10)
                    .frame(width: 100)

                Button {
                    Task { await fetchRates() }
                } label: {
                    if isLoading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .disabled(isLoading)
            }
            .padding(.horizontal, 20)

            if let lastUpdate {
                let formatter = { () -> DateFormatter in
                    let f = DateFormatter()
                    f.dateFormat = "HH:mm"
                    return f
                }()
                Text(L.t("更新于", lang) + " \(formatter.string(from: lastUpdate))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }

            ScrollView {
                VStack(spacing: 8) {
                    let amountVal = Double(amount) ?? 1.0
                    ForEach(currencies.filter { $0.code != baseCurrency }, id: \.code) { c in
                        if let rate = rates[c.code] {
                            rateRow(currency: c, rate: rate, amount: amountVal)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)
        }
        .background(Theme.background)
        .task { await fetchRates() }
    }

    private func rateRow(currency: (code: String, zh: String, en: String, flag: String),
                         rate: Double, amount: Double) -> some View {
        let converted = amount * rate
        return HStack {
            Text(currency.flag)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(currency.code)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(lang == .en ? currency.en : currency.zh)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatNumber(converted))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("1 \(baseCurrency) = \(formatRate(rate)) \(currency.code)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 12)
    }

    private func flagFor(_ code: String) -> String {
        currencies.first(where: { $0.code == code })?.flag ?? "💱"
    }

    private func formatNumber(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.2f", value)
        } else if value >= 1 {
            return String(format: "%.4f", value)
        } else {
            return String(format: "%.6f", value)
        }
    }

    private func formatRate(_ rate: Double) -> String {
        if rate >= 100 { return String(format: "%.2f", rate) }
        if rate >= 1 { return String(format: "%.4f", rate) }
        return String(format: "%.6f", rate)
    }

    private func fetchRates() async {
        isLoading = true
        defer { isLoading = false }
        if let fetched = await ExchangeRateMCP.fetchRates(base: baseCurrency) {
            rates = fetched
            lastUpdate = Date()
        }
    }
}
