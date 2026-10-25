//
//  Theme.swift
//  DeepChat
//
//  配色、圆角、通用修饰器
//

import SwiftUI

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex & 0xFF0000) >> 16) / 255.0,
                  green: CGFloat((hex & 0x00FF00) >> 8) / 255.0,
                  blue: CGFloat(hex & 0x0000FF) / 255.0,
                  alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(UIColor(hex: hex, alpha: CGFloat(alpha)))
    }

    /// 自动适配深浅色
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

enum Theme {

    /// DeepSeek 蓝
    static let accent = Color(hex: 0x4D6BFE)
    static let accentDark = Color(hex: 0x2F49D8)
    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0x6E8BFF), Color(hex: 0x4D6BFE)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let background = Color.dynamic(light: 0xF5F6FA, dark: 0x101116)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1A1B22)
    static let surfaceAlt = Color.dynamic(light: 0xEFF1F7, dark: 0x23252E)
    static let userBubble = Color.dynamic(light: 0xE7EDFF, dark: 0x2A3048)
    static let border = Color.dynamic(light: 0xE3E6EE, dark: 0x2C2E38)
    static let textSecondary = Color.dynamic(light: 0x6B7280, dark: 0x9AA1AE)
    static let codeBackground = Color(hex: 0x0E1117)
    static let codeHeader = Color(hex: 0x161B26)
    static let codeText = Color(hex: 0xD6DEEB)

    static let cornerLarge: CGFloat = 20
    static let cornerMedium: CGFloat = 14
    static let cornerSmall: CGFloat = 10
}

// MARK: - 通用修饰

struct CardModifier: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.8)
            )
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// 键盘弹出时让内容不被遮挡
    func hideKeyboardOnTap() -> some View {
        onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
    }
}

// MARK: - 品牌图标

struct BrandMark: View {
    var size: CGFloat = 34
    var radius: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: radius ?? size * 0.28, style: .continuous)
            .fill(Theme.accentGradient)
            .frame(width: size, height: size)
            .overlay(
                Text("🐟")
                    .font(.system(size: size * 0.46))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius ?? size * 0.28, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
            .shadow(color: Theme.accent.opacity(0.35), radius: size * 0.18, x: 0, y: size * 0.08)
    }
}
