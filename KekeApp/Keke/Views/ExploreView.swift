import SwiftUI

/// 探索页：阅读 / 听歌 / 语言学习 / 小游戏 / 画画 / 计时器 / 读代码 / 翻译 / 汇率 / MCP 模块
struct ExploreView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var books: BookService
    @EnvironmentObject var draw: DrawService
    @EnvironmentObject var mcp: MCPRegistry
    @EnvironmentObject var toolAPIConfig: ToolAPIConfig
    @EnvironmentObject var customProviders: CustomProviderStore
    @EnvironmentObject var activityLog: ActivityLog
    @EnvironmentObject var anniversaries: AnniversaryStore
    @State private var showLanguagePicker = false
    @State private var showGames = false
    @State private var showReading = false
    @State private var showDraw = false
    @State private var showTimer = false
    @State private var showCode = false
    @State private var showTranslation = false
    @State private var showExchangeRate = false
    @State private var showNews = false
    @State private var showMCPRegistry = false
    @State private var showAnniversary = false
    @State private var showPomodoro = false
    @State private var showFileManager = false
    @State private var showSoonAlert = false

    private let languages = ["", "法语", "西班牙语", "德语", "俄语"]
    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("🌙✨")
                    .font(.system(size: 40))
                    .padding(.top, 26)
                Text(L.t("探索", lang))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t("工具和小玩意儿", lang))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 30)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    exploreTile(icon: "book.fill", label: "阅读", soon: false) {
                        withAnimation { showReading = true }
                    }
                    exploreTile(icon: "music.note", label: "听歌", soon: true) { showSoonAlert = true }
                    exploreTile(icon: "character.book.closed.fill", label: "语言学习", soon: false) {
                        withAnimation { showLanguagePicker = true }
                    }
                    exploreTile(icon: "gamecontroller.fill", label: "游戏", soon: false) {
                        withAnimation { showGames = true }
                    }
                    exploreTile(icon: "paintbrush.fill", label: "一起画画", soon: false) {
                        withAnimation { showDraw = true }
                    }
                    exploreTile(icon: "timer", label: "陪伴计时器", soon: false) {
                        withAnimation { showTimer = true }
                    }
                    exploreTile(icon: "chevron.left.forwardslash.chevron.right", label: "克克读代码", soon: false) {
                        withAnimation { showCode = true }
                    }
                    exploreTile(icon: "textformat.abc", label: "翻译", soon: false) {
                        withAnimation { showTranslation = true }
                    }
                    exploreTile(icon: "yensign.circle", label: "实时汇率", soon: false) {
                        withAnimation { showExchangeRate = true }
                    }
                    exploreTile(icon: "newspaper.fill", label: "新闻热搜", soon: false) {
                        withAnimation { showNews = true }
                    }
                    exploreTile(icon: "calendar.badge.clock", label: "纪念日", soon: false) {
                        withAnimation { showAnniversary = true }
                    }
                    exploreTile(icon: "leaf.fill", label: "番茄钟", soon: false) {
                        withAnimation { showPomodoro = true }
                    }
                    exploreTile(icon: "folder.fill", label: "文件管理", soon: false) {
                        withAnimation { showFileManager = true }
                    }
                    exploreTile(icon: "puzzlepiece.extension.fill", label: "MCP 模块", soon: false) {
                        withAnimation { showMCPRegistry = true }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                if !store.learningLanguage.isEmpty {
                    Text("🐱 \(store.learningLanguage)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .slideOverCover(isPresented: $showLanguagePicker) {
            languagePickerSheet
                .backButtonInset { withAnimation { showLanguagePicker = false } }
        }
        .slideOverCover(isPresented: $showGames) {
            GamesHubView()
                .environmentObject(store)
                .environmentObject(activityLog)
                .backButtonInset { withAnimation { showGames = false } }
        }
        .slideOverCover(isPresented: $showReading) {
            BookListView()
                .environmentObject(store)
                .environmentObject(books)
                .backButtonInset { withAnimation { showReading = false } }
        }
        .slideOverCover(isPresented: $showDraw) {
            DrawTogetherView()
                .environmentObject(store)
                .environmentObject(draw)
                .backButtonInset { withAnimation { showDraw = false } }
        }
        .slideOverCover(isPresented: $showTimer) {
            CompanionTimerView()
                .environmentObject(store)
                .backButtonInset { withAnimation { showTimer = false } }
        }
        .slideOverCover(isPresented: $showCode) {
            CodeReviewView()
                .environmentObject(store)
                .backButtonInset { withAnimation { showCode = false } }
        }
        .slideOverCover(isPresented: $showTranslation) {
            TranslationView()
                .environmentObject(store)
                .environmentObject(toolAPIConfig)
                .environmentObject(customProviders)
                .environmentObject(activityLog)
                .backButtonInset { withAnimation { showTranslation = false } }
        }
        .slideOverCover(isPresented: $showExchangeRate) {
            ExchangeRateView()
                .environmentObject(store)
                .environmentObject(toolAPIConfig)
                .environmentObject(customProviders)
                .environmentObject(activityLog)
                .backButtonInset { withAnimation { showExchangeRate = false } }
        }
        .slideOverCover(isPresented: $showNews) {
            NewsView()
                .environmentObject(store)
                .environmentObject(toolAPIConfig)
                .environmentObject(customProviders)
                .environmentObject(activityLog)
                .backButtonInset { withAnimation { showNews = false } }
        }
        .slideOverCover(isPresented: $showAnniversary) {
            AnniversaryView()
                .environmentObject(store)
                .environmentObject(anniversaries)
                .environmentObject(activityLog)
                .backButtonInset { withAnimation { showAnniversary = false } }
        }
        .slideOverCover(isPresented: $showPomodoro) {
            PomodoroView()
                .environmentObject(store)
                .environmentObject(activityLog)
                .backButtonInset { withAnimation { showPomodoro = false } }
        }
        .slideOverCover(isPresented: $showFileManager) {
            FileManagerView()
                .environmentObject(store)
                .environmentObject(activityLog)
                .environmentObject(toolAPIConfig)
                .environmentObject(customProviders)
                .backButtonInset { withAnimation { showFileManager = false } }
        }
        .slideOverCover(isPresented: $showMCPRegistry) {
            MCPRegistryView()
                .environmentObject(store)
                .environmentObject(mcp)
                .environmentObject(toolAPIConfig)
                .environmentObject(customProviders)
                .backButtonInset { withAnimation { showMCPRegistry = false } }
        }
        .alert(L.t("敬请期待", lang), isPresented: $showSoonAlert) {
            Button(L.t("好", lang)) {}
        } message: {
            Text(L.t("这里以后会放阅读、听歌或者小游戏之类的，慢慢来～", lang))
        }
    }

    private func exploreTile(icon: String, label: String, soon: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(L.t(label, lang))
                    .font(.caption2)
            }
            .foregroundStyle(soon ? Theme.textSecondary.opacity(0.6) : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .glassCard(cornerRadius: 16)
        }
    }

    private var languagePickerSheet: some View {
        VStack(spacing: 0) {
            Text(L.t("语言学习", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 4)
            Text(L.t("选一门语言，克克会顺便在聊天里教你几句", lang))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            VStack(spacing: 8) {
                languageRow(value: "", label: "不用")
                ForEach(languages.dropFirst(), id: \.self) { l in
                    languageRow(value: l, label: l)
                }
            }
            .padding(.horizontal, 18)

            Spacer(minLength: 0)
        }
        .background(Theme.background)
    }

    private func languageRow(value: String, label: String) -> some View {
        Button {
            store.learningLanguage = value
            showLanguagePicker = false
        } label: {
            HStack {
                Text(L.t(label, lang))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if store.learningLanguage == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassCard(cornerRadius: 12)
        }
    }
}
