import SwiftUI

/// 「经期」页：月历 + 状态卡片。点日期可以手动标记；健康 App 的记录自动同步进来
struct CycleView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var cycle: CycleService
    @State private var displayedMonth = Date()

    private let calendar = Calendar.current
    private let weekdaySymbolsZh = ["日", "一", "二", "三", "四", "五", "六"]
    private let weekdaySymbolsEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private var weekdaySymbols: [String] { store.appLanguage == .en ? weekdaySymbolsEn : weekdaySymbolsZh }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                calendarCard
                legend
            }
            .padding(16)
        }
        .background(Theme.background)
        .refreshable { await cycle.refreshFromHealth() }
        .task { await cycle.refreshFromHealth() }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Color.pink)
                Text(L.t("经期", store.appLanguage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            ForEach(cycle.statusLines(lang: store.appLanguage), id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }

    private var calendarCard: some View {
        VStack(spacing: 10) {
            // 月份切换
            HStack {
                Button {
                    if let previous = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
                        displayedMonth = previous
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                }
                Spacer()
                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                        displayedMonth = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                }
            }

            // 星期表头
            HStack {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // 日期格子
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }

    private func dayCell(_ day: Date) -> some View {
        let dayStart = calendar.startOfDay(for: day)
        let isPeriod = cycle.allDays.contains(dayStart)
        let isPredicted = cycle.predictedDays.contains(dayStart)
        let isToday = calendar.isDateInToday(day)

        return Button {
            cycle.toggle(day)
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 14, weight: isToday ? .bold : .regular))
                .foregroundStyle(isPeriod ? .white : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    ZStack {
                        if isPeriod {
                            Circle().fill(Color.pink)
                        } else if isPredicted {
                            Circle().fill(Color.pink.opacity(0.22))
                        }
                        if isToday {
                            Circle().stroke(Theme.accent, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 34, height: 34)
                )
        }
    }

    private var legend: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Circle().fill(Color.pink).frame(width: 10, height: 10)
                    Text(L.t("经期", store.appLanguage)).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 5) {
                    Circle().fill(Color.pink.opacity(0.22)).frame(width: 10, height: 10)
                    Text(L.t("预测", store.appLanguage)).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 5) {
                    Circle().stroke(Theme.accent, lineWidth: 1.5).frame(width: 10, height: 10)
                    Text(L.t("今天", store.appLanguage)).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Text(L.t("点日期可以标记/取消。健康 App 里的记录会自动同步进来（只读）；在这里点的只存在这台手机上。", store.appLanguage))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 2)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        if store.appLanguage == .en {
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMMM yyyy"
        } else {
            formatter.dateFormat = "yyyy年M月"
        }
        return formatter.string(from: displayedMonth)
    }

    private var monthCells: [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let first = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let leadingBlanks = calendar.component(.weekday, from: first) - 1
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: first))
        }
        return cells
    }
}
