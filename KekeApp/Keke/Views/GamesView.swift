import SwiftUI

/// 探索 → 游戏：目前两个小游戏，石头剪刀布 + 今日小签
struct GamesHubView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var activityLog: ActivityLog
    @State private var showRPS = false
    @State private var showFortune = false
    @State private var showQuickQA = false
    @State private var showWouldYouRather = false
    @State private var showSpinner = false

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
                gameTile(icon: "questionmark.bubble.fill", label: "快问快答") { withAnimation { showQuickQA = true } }
                gameTile(icon: "arrow.left.arrow.right", label: "二选一") { withAnimation { showWouldYouRather = true } }
                gameTile(icon: "arrow.triangle.2.circlepath", label: "转盘") { withAnimation { showSpinner = true } }
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
        .slideOverCover(isPresented: $showQuickQA) {
            QuickQAView()
                .environmentObject(store)
                .environmentObject(activityLog)
                .backButtonInset { withAnimation { showQuickQA = false } }
        }
        .slideOverCover(isPresented: $showWouldYouRather) {
            WouldYouRatherView()
                .environmentObject(store)
                .environmentObject(activityLog)
                .backButtonInset { withAnimation { showWouldYouRather = false } }
        }
        .slideOverCover(isPresented: $showSpinner) {
            SpinnerWheelView()
                .environmentObject(store)
                .environmentObject(activityLog)
                .backButtonInset { withAnimation { showSpinner = false } }
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
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }
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
                    Text(personaName).font(.caption2).foregroundStyle(Theme.textSecondary)
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
        return beats[my] == her ? "\(store.myName) 赢了" : "\(personaName)赢了"
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
        let outcomeStr = outcome == .tie ? "平局" : (outcome == .meWin ? "\(store.myName)赢了" : "\(personaName)赢了")
        activityLog.log(.game, "和\(personaName)玩了石头剪刀布，\(my.zhName) vs \(her.zhName)，\(outcomeStr)")
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
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }

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
        case .kekeWin: return String(format: L.t("%@赢了", lang), personaName)
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
                personaName: PersonaStore.persona(for: store.personaId).name,
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

// MARK: - Quick Q&A

struct QuickQAView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var activityLog: ActivityLog
    @State private var questions: [String] = []
    @State private var currentIndex = 0
    @State private var isLoading = false
    @State private var answer = ""
    @State private var reaction: String?
    @State private var isReacting = false

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(spacing: 18) {
            Text("❓")
                .font(.system(size: 50))
                .padding(.top, 26)
            Text(L.t("快问快答", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            if isLoading {
                ProgressView()
                    .padding(.top, 20)
            } else if questions.isEmpty {
                Button {
                    loadQuestions()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 28))
                        Text(lang == .en ? "Generate Questions" : "出题")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 140, height: 100)
                    .glassCard(cornerRadius: 16)
                }
            } else if currentIndex < questions.count {
                questionCard
            } else {
                VStack(spacing: 12) {
                    Text("🎉")
                        .font(.system(size: 44))
                    Text(lang == .en ? "All done!" : "答完啦！")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        questions = []
                        currentIndex = 0
                        reaction = nil
                    } label: {
                        Text(L.t("再来一轮", lang))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
    }

    private var questionCard: some View {
        VStack(spacing: 12) {
            Text(questions[currentIndex])
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 14)

            if let reaction {
                Text(reaction)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .transition(.opacity)

                Button {
                    self.reaction = nil
                    answer = ""
                    currentIndex += 1
                } label: {
                    Text(lang == .en ? "Next" : "下一题")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
            } else {
                TextField(lang == .en ? "Your answer…" : "你的回答…", text: $answer)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(10)
                    .glassCard(cornerRadius: 10)

                Button {
                    submitAnswer()
                } label: {
                    if isReacting {
                        ProgressView()
                    } else {
                        Text(lang == .en ? "Submit" : "提交")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 10)
                            .background(answer.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.textSecondary.opacity(0.3) : Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty || isReacting)
            }
        }
        .padding(.horizontal, 18)
    }

    private func loadQuestions() {
        isLoading = true
        let recentChat = store.visibleMessages.suffix(10).map { $0.text }.joined(separator: "\n")
        Task {
            let text = try? await ClaudeService.generateQuickQA(
                userName: store.myName, recentChat: recentChat.isEmpty ? nil : String(recentChat.prefix(500)),
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt)
            let lines = (text ?? "用一个词形容今天的心情\n如果只能吃一种食物你选什么\n你觉得\(PersonaStore.persona(for: store.personaId).name)最可爱的地方是什么")
                .split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            questions = lines
            currentIndex = 0
            isLoading = false
            activityLog.log(.game, "开始玩快问快答")
        }
    }

    private func submitAnswer() {
        let q = questions[currentIndex]
        let a = answer.trimmingCharacters(in: .whitespaces)
        isReacting = true
        activityLog.log(.game, "快问快答回答了「\(q.prefix(20))」：\(a.prefix(20))")
        Task {
            let r = try? await ClaudeService.generateGameReaction(
                game: "快问快答", question: q, answer: a, userName: store.myName,
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt)
            withAnimation { reaction = r ?? "嗯……有意思。*歪头*" }
            isReacting = false
        }
    }
}

// MARK: - Would You Rather

struct WouldYouRatherView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var activityLog: ActivityLog
    @State private var questions: [(String, String)] = []
    @State private var currentIndex = 0
    @State private var isLoading = false
    @State private var reaction: String?
    @State private var isReacting = false

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(spacing: 18) {
            Text("⚖️")
                .font(.system(size: 50))
                .padding(.top, 26)
            Text(L.t("二选一", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            if isLoading {
                ProgressView()
                    .padding(.top, 20)
            } else if questions.isEmpty {
                Button {
                    loadQuestions()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 28))
                        Text(lang == .en ? "Generate Choices" : "出题")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 140, height: 100)
                    .glassCard(cornerRadius: 16)
                }
            } else if currentIndex < questions.count {
                choiceCard
            } else {
                VStack(spacing: 12) {
                    Text("🎉")
                        .font(.system(size: 44))
                    Text(lang == .en ? "All done!" : "答完啦！")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        questions = []
                        currentIndex = 0
                        reaction = nil
                    } label: {
                        Text(L.t("再来一轮", lang))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
    }

    private var choiceCard: some View {
        VStack(spacing: 14) {
            if let reaction {
                Text(reaction)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .transition(.opacity)

                Button {
                    self.reaction = nil
                    currentIndex += 1
                } label: {
                    Text(lang == .en ? "Next" : "下一题")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
            } else {
                let pair = questions[currentIndex]
                VStack(spacing: 10) {
                    choiceButton(pair.0)
                    Text(lang == .en ? "or" : "还是")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    choiceButton(pair.1)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private func choiceButton(_ text: String) -> some View {
        Button {
            choose(text)
        } label: {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .glassCard(cornerRadius: 14)
        }
        .disabled(isReacting)
    }

    private func choose(_ choice: String) {
        let pair = questions[currentIndex]
        let q = "\(pair.0) 还是 \(pair.1)"
        isReacting = true
        activityLog.log(.game, "二选一选了「\(choice.prefix(20))」")
        Task {
            let r = try? await ClaudeService.generateGameReaction(
                game: "二选一", question: q, answer: choice, userName: store.myName,
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt)
            withAnimation { reaction = r ?? "哦～这个选择嘛……*若有所思*" }
            isReacting = false
        }
    }

    private func loadQuestions() {
        isLoading = true
        let recentChat = store.visibleMessages.suffix(10).map { $0.text }.joined(separator: "\n")
        Task {
            let text = try? await ClaudeService.generateWouldYouRather(
                userName: store.myName, recentChat: recentChat.isEmpty ? nil : String(recentChat.prefix(500)),
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt)
            let fallback = "永远不能吃辣还是永远不能吃甜\n一直下雨还是一直大太阳\n只能用一个App还是只能用一个网站"
            let lines = (text ?? fallback)
                .split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            questions = lines.map { line in
                let parts = line.components(separatedBy: "还是")
                if parts.count >= 2 {
                    return (parts[0].trimmingCharacters(in: .whitespaces), parts.dropFirst().joined(separator: "还是").trimmingCharacters(in: .whitespaces))
                }
                let orParts = line.components(separatedBy: " or ")
                if orParts.count >= 2 {
                    return (orParts[0].trimmingCharacters(in: .whitespaces), orParts.dropFirst().joined(separator: " or ").trimmingCharacters(in: .whitespaces))
                }
                return (line, "？")
            }
            currentIndex = 0
            isLoading = false
            activityLog.log(.game, "开始玩二选一")
        }
    }
}

// MARK: - Spinner Wheel

struct SpinnerWheelView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var activityLog: ActivityLog
    @State private var options: [String] = []
    @State private var newOption = ""
    @State private var rotation: Double = 0
    @State private var isSpinning = false
    @State private var result: String?
    @State private var reaction: String?
    @State private var isReacting = false

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(spacing: 14) {
            Text("🎡")
                .font(.system(size: 44))
                .padding(.top, 20)
            Text(L.t("转盘", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lang == .en ? "Add options" : "添加选项")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        HStack {
                            TextField(lang == .en ? "Option…" : "选项…", text: $newOption)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Button {
                                let trimmed = newOption.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    options.append(trimmed)
                                    newOption = ""
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                            .disabled(newOption.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(10)
                        .glassCard(cornerRadius: 10)

                        if !options.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                                    HStack(spacing: 4) {
                                        Text(opt)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textPrimary)
                                        Button {
                                            options.remove(at: idx)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .glassCard(cornerRadius: 8)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 12)

                    if options.count >= 2 {
                        wheelView
                            .padding(.vertical, 10)

                        if let result {
                            VStack(spacing: 8) {
                                Text(lang == .en ? "Result:" : "结果：")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(result)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(Theme.accent)

                                if let reaction {
                                    Text(reaction)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 20)
                                } else if isReacting {
                                    ProgressView()
                                }
                            }
                            .padding(14)
                            .glassCard(cornerRadius: 14)
                        }
                    } else {
                        Text(lang == .en ? "Add at least 2 options to spin" : "至少添加2个选项才能转")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.background)
    }

    private var wheelView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.3), lineWidth: 3)
                    .frame(width: 200, height: 200)

                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    let angle = Double(idx) / Double(options.count) * 360
                    Text(opt)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .rotationEffect(.degrees(-rotation))
                        .offset(y: -70)
                        .rotationEffect(.degrees(angle + rotation))
                }

                ForEach(0..<options.count, id: \.self) { idx in
                    let angle = Double(idx) / Double(options.count) * 360
                    Rectangle()
                        .fill(Theme.accent.opacity(0.2))
                        .frame(width: 1, height: 100)
                        .offset(y: -50)
                        .rotationEffect(.degrees(angle + rotation))
                }

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 16, height: 16)
            }
            .frame(width: 200, height: 200)

            Image(systemName: "arrowtriangle.down.fill")
                .foregroundStyle(Theme.accent)
                .offset(y: -8)

            Button {
                spin()
            } label: {
                Text(lang == .en ? "Spin!" : "转！")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 10)
                    .background(isSpinning ? Theme.textSecondary.opacity(0.3) : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isSpinning)
        }
    }

    private func spin() {
        guard options.count >= 2 else { return }
        isSpinning = true
        result = nil
        reaction = nil

        let extraRotations = Double.random(in: 5...10) * 360
        let randomStop = Double.random(in: 0..<360)
        let totalRotation = extraRotations + randomStop

        withAnimation(.easeOut(duration: 3.0)) {
            rotation += totalRotation
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
            let normalizedAngle = rotation.truncatingRemainder(dividingBy: 360)
            let segmentSize = 360.0 / Double(options.count)
            let index = Int((360 - normalizedAngle).truncatingRemainder(dividingBy: 360) / segmentSize) % options.count
            let chosen = options[abs(index)]
            result = chosen
            isSpinning = false
            activityLog.log(.game, "转盘转到了「\(chosen)」")
            getReaction(chosen)
        }
    }

    private func getReaction(_ chosen: String) {
        isReacting = true
        Task {
            let r = try? await ClaudeService.generateGameReaction(
                game: "转盘", question: "选项有：\(options.joined(separator: "、"))", answer: chosen,
                userName: store.myName,
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt)
            withAnimation { reaction = r ?? "命运的选择！*拍爪*" }
            isReacting = false
        }
    }
}

