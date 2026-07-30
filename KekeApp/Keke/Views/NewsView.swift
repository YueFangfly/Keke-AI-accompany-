import SwiftUI

struct NewsView: View {
    @EnvironmentObject var store: ChatStore
    @State private var articles: [NewsArticle] = []
    @State private var selectedFeed: NewsFeed
    @State private var isLoading = false

    private var lang: AppLanguage { store.appLanguage }

    init() {
        _selectedFeed = State(initialValue: NewsMCP.allFeeds[0])
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L.t("新闻热搜", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NewsMCP.allFeeds) { feed in
                        feedChip(feed)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 10)

            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text(L.t("加载中…", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 8)
                Spacer()
            } else if articles.isEmpty {
                Spacer()
                Text(L.t("暂无新闻，换个来源试试", lang))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(articles) { article in
                            articleRow(article)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Theme.background)
        .task { await loadFeed() }
    }

    private func feedChip(_ feed: NewsFeed) -> some View {
        let isSelected = feed.id == selectedFeed.id
        return Button {
            selectedFeed = feed
            Task { await loadFeed() }
        } label: {
            Text(lang == .en ? feed.nameEN : feed.name)
                .font(.caption2)
                .foregroundStyle(isSelected ? .white : Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Theme.accent : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : Theme.textSecondary.opacity(0.3), lineWidth: 1))
        }
    }

    private func articleRow(_ article: NewsArticle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(article.source)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.accent)
                Spacer()
                if let date = article.pubDate {
                    Text(relativeTime(date))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(article.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
            if !article.description.isEmpty {
                Text(article.description)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
    }

    private func relativeTime(_ date: Date) -> String {
        let minutes = Int(-date.timeIntervalSinceNow / 60)
        if minutes < 1 { return lang == .en ? "just now" : "刚刚" }
        if minutes < 60 { return "\(minutes) \(lang == .en ? "min ago" : "分钟前")" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) \(lang == .en ? "hr ago" : "小时前")" }
        let days = hours / 24
        return "\(days) \(lang == .en ? (days == 1 ? "day ago" : "days ago") : "天前")"
    }

    private func loadFeed() async {
        isLoading = true
        defer { isLoading = false }
        let feedName = lang == .en ? selectedFeed.nameEN : selectedFeed.name
        if let fetched = await NewsMCP.fetchRSS(url: selectedFeed.url, sourceName: feedName) {
            articles = fetched
        } else {
            articles = []
        }
    }
}
