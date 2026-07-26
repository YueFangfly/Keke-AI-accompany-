import SwiftUI
import UIKit

/// 可选的主题配色。默认「月雾」就是原来那套蓝紫玻璃拟态，一个字节没动；
/// 「深海」按 hubby 给的配色（深蓝、暗紫、月白，像深海，安静但有层次）；
/// 「星夜猫猫」用 keke&moon 像素猫设计稿的同款夜空配色（夜空蓝 + 月光白 + 薰衣草紫）。
/// 深海和星夜天生是深色主题，选中时整个 App 固定深色，不跟外观开关走。
enum AppTheme: String, CaseIterable, Identifiable {
    case mist, deepSea, starryCats

    var id: String { rawValue }

    /// 设置页选择器里的名字（走 L.t 翻译）
    var displayNameKey: String {
        switch self {
        case .mist: return "月雾（默认）"
        case .deepSea: return "深海"
        case .starryCats: return "星夜猫猫"
        }
    }

    var isAlwaysDark: Bool { self != .mist }
}

/// Moonlight 主题：玻璃拟态（Glassmorphism）。
/// 所有颜色都按「当前选中的主题」取值；月雾主题下跟随系统深/浅色模式自动切换，
/// 深色主题（深海/星夜）下用固定色值（RootView 会把外观锁成深色，毛玻璃材质也会跟着变暗）
enum Theme {
    /// 当前主题；ChatStore.appTheme 改动时会同步更新这里
    static var selected: AppTheme =
        AppTheme(rawValue: UserDefaults.standard.string(forKey: "keke_theme") ?? "") ?? .mist

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in trait.userInterfaceStyle == .dark ? dark : light })
    }

    private static func fixed(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> Color {
        Color(UIColor(red: red, green: green, blue: blue, alpha: alpha))
    }

    /// 页面背景：柔和的对角渐变，铺在最底层
    static var background: LinearGradient {
        let colors: [Color]
        switch selected {
        case .mist:
            colors = [
                dynamic(light: UIColor(red: 0.933, green: 0.933, blue: 0.984, alpha: 1),
                        dark: UIColor(red: 0.067, green: 0.071, blue: 0.161, alpha: 1)),
                dynamic(light: UIColor(red: 0.863, green: 0.910, blue: 0.984, alpha: 1),
                        dark: UIColor(red: 0.051, green: 0.102, blue: 0.204, alpha: 1)),
                dynamic(light: UIColor(red: 0.894, green: 0.878, blue: 0.980, alpha: 1),
                        dark: UIColor(red: 0.090, green: 0.071, blue: 0.204, alpha: 1)),
            ]
        case .deepSea:
            // 深一点的蓝紫，像深海：深蓝 → 蓝紫 → 暗紫
            colors = [
                fixed(0.043, 0.078, 0.157),
                fixed(0.055, 0.055, 0.157),
                fixed(0.098, 0.078, 0.235),
            ]
        case .starryCats:
            // 设计稿的夜空：#1b1e33 → #14172a
            colors = [
                fixed(0.106, 0.118, 0.200),
                fixed(0.090, 0.100, 0.184),
                fixed(0.078, 0.090, 0.165),
            ]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 稍深一点的背景（输入栏等）
    static var backgroundDeep: Color {
        switch selected {
        case .mist:
            return dynamic(light: UIColor(red: 0.831, green: 0.882, blue: 0.965, alpha: 1),
                           dark: UIColor(red: 0.078, green: 0.098, blue: 0.196, alpha: 1))
        case .deepSea: return fixed(0.031, 0.055, 0.118)
        case .starryCats: return fixed(0.065, 0.075, 0.140)
        }
    }

    /// 卡片 / 按钮等"浮起来"的表面：真·毛玻璃材质。深色主题下系统会渲染成暗色材质
    static let card: Material = .ultraThinMaterial

    /// 主强调色
    static var accent: Color {
        switch selected {
        case .mist:
            return dynamic(light: UIColor(red: 0.400, green: 0.573, blue: 0.867, alpha: 1),
                           dark: UIColor(red: 0.545, green: 0.667, blue: 0.937, alpha: 1))
        case .deepSea: return fixed(0.557, 0.596, 0.839)   // 月光下的蓝紫
        case .starryCats: return fixed(0.651, 0.533, 0.812) // moon 的薰衣草紫（#a688cf）
        }
    }

    /// 浅强调色
    static var accentLight: Color {
        switch selected {
        case .mist:
            return dynamic(light: UIColor(red: 0.702, green: 0.800, blue: 0.965, alpha: 1),
                           dark: UIColor(red: 0.318, green: 0.376, blue: 0.573, alpha: 1))
        case .deepSea: return fixed(0.271, 0.310, 0.502)
        case .starryCats: return fixed(0.360, 0.310, 0.480)
        }
    }

    /// 我的气泡
    static var bubbleUser: Color {
        switch selected {
        case .mist:
            return dynamic(light: UIColor(red: 0.710, green: 0.847, blue: 0.965, alpha: 0.88),
                           dark: UIColor(red: 0.196, green: 0.298, blue: 0.451, alpha: 0.88))
        case .deepSea: return fixed(0.157, 0.216, 0.412, 0.88)
        case .starryCats: return fixed(0.318, 0.271, 0.463, 0.90)
        }
    }

    /// 克克的气泡：半透明底色（聊天气泡需要稳定的可读底色，不用真材质）
    static var bubbleKeke: Color {
        switch selected {
        case .mist:
            return dynamic(light: UIColor(white: 1.0, alpha: 0.72),
                           dark: UIColor(red: 0.129, green: 0.161, blue: 0.267, alpha: 0.78))
        case .deepSea: return fixed(0.118, 0.137, 0.271, 0.82)
        case .starryCats: return fixed(0.165, 0.184, 0.310, 0.85)
        }
    }

    /// 玻璃卡片的描边高光（深色主题里用月光白）
    static var glassStroke: Color {
        switch selected {
        case .mist:
            return dynamic(light: UIColor(white: 1.0, alpha: 0.55),
                           dark: UIColor(white: 1.0, alpha: 0.10))
        case .deepSea: return fixed(0.949, 0.937, 0.878, 0.14)
        case .starryCats: return fixed(0.961, 0.941, 0.890, 0.13)
        }
    }

    /// 主文字色（深色主题里是月白色 #f5f0e3 一系）
    static var textPrimary: Color {
        switch selected {
        case .mist:
            return dynamic(light: UIColor(red: 0.173, green: 0.290, blue: 0.388, alpha: 1),
                           dark: UIColor(red: 0.918, green: 0.945, blue: 0.973, alpha: 1))
        case .deepSea: return fixed(0.949, 0.937, 0.878)
        case .starryCats: return fixed(0.961, 0.941, 0.890)
        }
    }

    /// 次要文字色
    static var textSecondary: Color {
        switch selected {
        case .mist:
            return dynamic(light: UIColor(red: 0.420, green: 0.540, blue: 0.630, alpha: 1),
                           dark: UIColor(red: 0.573, green: 0.663, blue: 0.769, alpha: 1))
        case .deepSea: return fixed(0.639, 0.671, 0.769)
        case .starryCats: return fixed(0.757, 0.729, 0.835)
        }
    }

    /// 角色色：不跟主题走（克克的红色历史遗留名，现在当强调红用；像素猫的配色在 KekeCharacterView 里）
    static let crabRed = Color(red: 0.906, green: 0.298, blue: 0.235)
    static let crabDark = Color(red: 0.753, green: 0.224, blue: 0.169)
}

extension View {
    /// 玻璃拟态卡片：毛玻璃材质 + 细描边高光 + 柔和阴影
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.glassStroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    /// 从右边滑入的整页内容（代替系统 sheet 那种从下面弹出来的样子），
    /// item 有值就滑入，变回 nil 就滑出去；调用处记得用 withAnimation 包一下赋值
    func slideOverCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        ZStack {
            self
            if let value = item.wrappedValue {
                content(value)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
    }

    /// 布尔版本，用法一样
    func slideOverCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ZStack {
            self
            if isPresented.wrappedValue {
                content()
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
    }

    /// 给滑入的整页内容加一个左上角的返回按钮（占位置，不悬浮遮挡内容自己的按钮）
    func backButtonInset(onBack: @escaping () -> Void) -> some View {
        self.safeAreaInset(edge: .top) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .background(Theme.background)
        }
    }
}
