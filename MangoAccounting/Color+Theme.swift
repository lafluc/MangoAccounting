// Color+Theme.swift

import SwiftUI

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum AppTheme {
    // MODIFICATION: Replaced adaptive colors with static dark theme colors.
    static let background = Color(hex: "1C1C1E")
    static let cardBackground = Color(hex: "2C2C2E")
    
    // Accent colors are kept, as they work well on a dark theme.
    static let accent = Color(hex: "FFC947")
    static let accentSecondary = Color(hex: "4DD0E1")
    
    // MODIFICATION: Text colors are now static light colors for contrast.
    static let textPrimary = Color(hex: "E5E5E7")
    static let textSecondary = Color(hex: "8E8E93")
    
    // MODIFICATION: Updated positive/negative colors for better visibility on a dark background.
    static let positive = Color(hex: "30D158") // Brighter Green
    static let negative = Color(hex: "FF453A") // Brighter Red

    // Fonts and layout remain the same.
    static let titleFont = Font.system(size: 28, weight: .bold, design: .rounded)
    static let headlineFont = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let bodyFont = Font.system(size: 16, weight: .regular, design: .default)
    static let captionFont = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let cornerRadius: CGFloat = 8.0
    static let generalPadding: CGFloat = 16.0
    
    // MODIFICATION: Shadow is now a subtle black shadow.
    static let shadow = Shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
}

// MARK: - Custom Views and Styles

/// A robust container view for generic cards.
struct CardView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppTheme.generalPadding)
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cornerRadius)
            .shadow(color: AppTheme.shadow.color,
                    radius: AppTheme.shadow.radius,
                    x: AppTheme.shadow.x,
                    y: AppTheme.shadow.y)
    }
}

/// A custom view modifier for sharp cards with a left accent bar.
/// RE-ADDED: This is needed for the summary cards.
struct AccentBarCardStyle: ViewModifier {
    var accentColor: Color

    func body(content: Content) -> some View {
        content
            .padding(AppTheme.generalPadding)
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cornerRadius)
            .overlay(
                HStack {
                    Capsule()
                        .fill(accentColor)
                        .frame(width: 6)
                    Spacer()
                }
            )
            .shadow(color: AppTheme.shadow.color,
                    radius: AppTheme.shadow.radius,
                    x: AppTheme.shadow.x,
                    y: AppTheme.shadow.y)
    }
}

struct PillButtonStyle: ButtonStyle {
    // ... (This style remains the same)
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.headlineFont)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(AppTheme.accent)
            .foregroundColor(Color.black) // MODIFICATION: Changed text to black for better contrast on yellow.
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

extension View {
    /// RE-ADDED: Helper to make applying the accent bar modifier easier.
    func accentBarCard(color: Color) -> some View {
        self.modifier(AccentBarCardStyle(accentColor: color))
    }
}

extension Color {
    // ... (The hex initializer remains the same)
    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#")
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
