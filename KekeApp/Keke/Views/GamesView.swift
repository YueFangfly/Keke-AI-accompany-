import SwiftUI

/// 探索 → 游戏：目前两个小游戏，石头剪刀布 + 今日小签
struct GamesHubView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var activityLog: ActivityLog
    @State private var showRPS = false
    @State private var showFortune = false

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(spacing: 16) {
            Text("🎮")
                .font(.system(size: 40))
                .padding(.top, 26)
            Text(L.t("小游戏", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                gameTile(icon: "hand.raised.fill", label: "石头剪刀布") { withAnimation { showRPS = true } }
                gameTile(icon: "sparkles", label: "今日小签") { withAnimation { showFortune = true } }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .slideOverCover(isPresented: $showRPS) {
            RockPaperScissorsView()
                .environmentObject(store)
                .environmentObject(activityLog)
                .backButtonInset { withAnimation { showRPS = false } }
        }
        .slideOverCover(isPresented: $showFortune) {
            DailyFortuneView()
                .environmentObject(store)
                .environmentObject(activityLog)
                .backButtonInset { withAnimation { showFortune = false } }
        }
    }

    private func gameTile(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(L.t(label, lang))
                    .font(.caption2)
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .glassCard(cornerRadius: 16)
        }
    }
}

/// 每一局石头剪刀布的记录，本地存成历史战绩
struct RPSRound: Identifiable, Codable, Equatable {
    enum Outcome: String, Codable { case tie, meWin, kekeWin }

    var id = UUID()
    var date: Date = Date()
    var myMoveEmoji: String
    var herMoveEmoji: String
    var outcome: Outcome
    var resultText: String
}

/// 石头剪刀布：本地随机出克克的招（秒出结果），AI 现生成她的一句反应
struct RockPaperScissorsView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var activityLog: ActivityLog
    @State private var myMove: Move?
    @State private var herMove: Move?
    @State private var resultText: String?
    @State private var isThinking = false
    @State private var history: [RPSRound] = []
    @State private var showHistory = false

    private var lang: AppLanguage { store.appLanguage }
    private let historyKey = "keke_rps_history"

    enum Move: String, CaseIterable {
        case rock, scissors, paper

        var emoji: String {
            switch self {
            case .rock: return "✊"
            case .scissors: return "✌️"
            case .paper: return "✋"
            }
        }

        var zhName: String {
            switch self {
            case .rock: return "石头"
            case .scissors: return "剪刀"
            case .paper: return "布"
            }
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            Text("🐱")
                .font(.system(size: 50))
            Text(L.t("石头剪刀布", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 30) {
                VStack(spacing: 4) {
                    Text(L.t("我", lang)).font(.caption2).foregroundStyle(Theme.textSecondary)
                    Text(myMove?.emoji ?? "❔").font(.system(size: 44))
                }
                Text("VS").font(.caption2).foregroundStyle(Theme.textSecondary)
                VStack(spacing: 4) {
                    Text(L.t("克克", lang)).font(.caption2).foregroundStyle(Theme.textSecondary)
                    Text(herMove?.emoji ?? "❔").font(.system(size: 44))
                }
            }

            Group {
                if isThinking {
                    ProgressView()
                } else if let resultText {
                    Text(resultText)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 30)
                }
            }
            .frame(minHeight: 40)

            HStack(spacing: 16) {
                ForEach(Move.allCases, id: \.self) { move in
                    Button {
                        play(move)
                    } label: {
                        Text(move.emoji)
                            .font(.system(size: 28))
                            .frame(width: 58, height: 58)
                            .glassCard(cornerRadius: 29)
                    }
                    .disabled(isThinking)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .slideOverCover(isPresented: $showHistory) {
            RPSHistoryView(history: history)
                .environmentObject(store)
                .backButtonInset { withAnimation { showHistory = false } }
        }
        .onAppear { history = loadHistory() }
    }

    private func play(_ move: Move) {
        myMove = move
        let her = Move.allCases.randomElement() ?? .rock
        herMove = her
        resultText = nil
        isThinking = true

        let outcome = outcomeText(my: move, her: her)
        Task {
            let line = try? await ClaudeService.generateRPSLine(
                myMove: move.zhName, herMove: her.zhName, outcome: outcome,
                userName: store.myName,
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt
            )
            let final = line ?? fallbackLine(my: move, her: her)
            resultText = final
            isThinking = false
            recordRound(my: move, her: her, resultText: final)
        }
    }

    private func outcomeText(my: Move, her: Move) -> String {
        if my == her { return "平局" }
        let beats: [Move: Move] = [.rock: .scissors, .scissors: .paper, .paper: .rock]
        return beats[my] == her ? "\(store.myName) 赢了" : "克克赢了"
    }

    private func fallbackLine(my: Move, her: Move) -> String {
        if my == her { return "哼，算你厉害，跟我出一样的。" }
        let beats: [Move: Move] = [.rock: .scissors, .scissors: .paper, .paper: .rock]
        return beats[my] == her ? "啊？！算你运气好。*叉腰*" : "嘿嘿，我赢啦～"
    }

    private func recordRound(my: Move, her: Move, resultText: String) {
        let outcome: RPSRound.Outcome
        if my == her {
            outcome = .tie
        } else {
            let beats: [Move: Move] = [.rock: .scissors, .scissors: .paper, .paper: .rock]
            outcome = beats[my] == her ? .meWin : .kekeWin
        }
        let round = RPSRound(myMoveEmoji: my.emoji, herMoveEmoji: her.emoji, outcome: outcome, resultText: resultText)
        let outcomeStr = outcome == .tie ? "平局" : (outcome == .meWin ? "\(store.myName)赢了" : "克克赢了")
        activityLog.log(.game, "和克克玩了石头剪刀布，\(my.zhName) vs \(her.zhName)，\(outcomeStr)")
        history.insert(round, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        saveHistory()
    }

    private func loadHistory() -> [RPSRound] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let saved = try? JSONDecoder().decode([RPSRound].self, from: data) else { return [] }
        return saved
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}

/// 石头剪刀布的历史战绩
struct RPSHistoryView: View {
    @EnvironmentObject var store: ChatStore
    let history: [RPSRound]

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        Group {
            if history.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(history) { round in
                            roundRow(round)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(Theme.background)
    }

    private func roundRow(_ round: RPSRound) -> some View {
        HStack(spacing: 10) {
            Text(round.myMoveEmoji).font(.title3)
            Text("VS").font(.caption2).foregroundStyle(Theme.textSecondary)
            Text(round.herMoveEmoji).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(outcomeLabel(round.outcome))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(outcomeColor(round.outcome))
                Text(round.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(10)
        .glassCard(cornerRadius: 12)
    }

    private func outcomeLabel(_ outcome: RPSRound.Outcome) -> String {
        switch outcome {
        case .tie: return L.t("平局", lang)
        case .meWin: return lang == .en ? "\(store.myName) won" : "\(store.myName)赢了"
        case .kekeWin: return L.t("克克赢了", lang)
        }
    }

    private func outcomeColor(_ outcome: RPSRound.Outcome) -> Color {
        switch outcome {
        case .tie: return Theme.textSecondary
        case .meWin: return Theme.accent
        case .kekeWin: return Theme.crabRed
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🎮")
                .font(.system(size: 40))
            Text(L.t("还没玩过，去出个拳吧", lang))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 今日小签存取的 key 规则；日历详情页也要读同一份数据，同步显示当天抽的签
enum DailyFortuneStore {
    static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "keke_fortune_" + formatter.string(from: date)
    }

    static func text(for date: Date) -> String? {
        UserDefaults.standard.string(forKey: key(for: date))
    }
}

/// 今日小签：每天只能真的抽一次，克克现写一句签文，抽过了当天再点直接看回上次的
struct DailyFortuneView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var activityLog: ActivityLog
    @State private var fortuneText: String?
    @State private var isDrawing = false
    @State private var revealed = false

    private var lang: AppLanguage { store.appLanguage }
    private var todayKey: String { DailyFortuneStore.key(for: Date()) }

    var body: some View {
        VStack(spacing: 20) {
            Text("🔮")
                .font(.system(size: 50))
                .padding(.top, 36)
            Text(L.t("今日小签", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            if revealed, let fortuneText {
                Text(fortuneText)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(20)
                    .glassCard()
                    .padding(.horizontal, 24)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    draw()
                } label: {
                    VStack(spacing: 8) {
                        if isDrawing {
                            ProgressView()
                        } else {
                            Text("🎴")
                                .font(.system(size: 40))
                            Text(L.t("抽一签", lang))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .frame(width: 140, height: 140)
                    .glassCard(cornerRadius: 20)
                }
                .disabled(isDrawing)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .onAppear {
            if let saved = UserDefaults.standard.string(forKey: todayKey) {
                fortuneText = saved
                revealed = true
            }
        }
    }

    private func draw() {
        isDrawing = true
        Task {
            let text = try? await ClaudeService.generateDailyFortune(
                userName: store.myName,
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt
            )
            let final = text ?? "今天也要好好的呀。*摸摸头*"
            UserDefaults.standard.set(final, forKey: todayKey)
            fortuneText = final
            isDrawing = false
            activityLog.log(.game, "抽了今日小签：\(final.prefix(30))")
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { revealed = true }
        }
    }
}
