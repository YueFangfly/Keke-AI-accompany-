import SwiftUI

/// 五宫格底部导航：聊天 / 记忆 / (突出的圆形)首页 / 探索 / 设置
enum RootTab: CaseIterable, Identifiable {
    case chat, memory, home, explore, settings
    var id: Self { self }
}

struct BottomTabBar: View {
    @Binding var tab: RootTab
    let language: AppLanguage

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                tabButton(.chat, icon: "bubble.left.and.bubble.right.fill", label: "聊天")
                tabButton(.memory, icon: "brain.head.profile", label: "记忆")
                Color.clear.frame(maxWidth: .infinity)
                tabButton(.explore, icon: "sparkles", label: "探索")
                tabButton(.settings, icon: "gearshape.fill", label: "设置")
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .frame(height: 62)
            .background(Theme.card)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.glassStroke), alignment: .top)

            homeButton
                .offset(y: -6)
                .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tabButton(_ value: RootTab, icon: String, label: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { tab = value }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                Text(L.t(label, language))
                    .font(.system(size: 10))
            }
            .foregroundStyle(tab == value ? Theme.accent : Theme.textSecondary)
            .frame(maxWidth: .infinity)
        }
    }

    private var homeButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { tab = .home }
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 44, height: 44)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 7, x: 0, y: 3)
                Image(systemName: "house.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay(Circle().stroke(Theme.glassStroke, lineWidth: 1.5))
            .scaleEffect(tab == .home ? 1.06 : 1.0)
        }
    }
}
