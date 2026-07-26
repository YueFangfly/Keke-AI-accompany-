import SwiftUI

/// 收藏页：长按聊天气泡收藏的话都在这里
struct FavoritesView: View {
    @EnvironmentObject var store: ChatStore

    var body: some View {
        Group {
            if store.favorites.isEmpty {
                VStack(spacing: 12) {
                    Text("🐱")
                        .font(.system(size: 44))
                    Text(L.t("还没有收藏\n长按聊天气泡可以收藏喜欢的话", store.appLanguage))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.favorites) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(message.role == .keke ? L.t("克克", store.appLanguage) : store.myName)
                                    .font(.caption2.bold())
                                    .foregroundStyle(message.role == .keke ? Theme.crabRed : Theme.accent)
                                Text(message.text)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(message.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                            .contextMenu {
                                Button {
                                    store.toggleFavorite(message.id)
                                } label: {
                                    Label(L.t("取消收藏", store.appLanguage), systemImage: "star.slash")
                                }
                                Button {
                                    UIPasteboard.general.string = message.text
                                } label: {
                                    Label(L.t("复制", store.appLanguage), systemImage: "doc.on.doc")
                                }
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(Theme.background)
    }
}
