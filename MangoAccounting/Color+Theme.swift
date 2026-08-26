// Color+Theme.swift

import SwiftUI

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum AppTheme {

    // MARK: - Colours
    //
    // Asset-catalog colours, not `Color(hex:)`. A hex colour is a fixed value, so
    // the whole app had to be pinned to dark mode; `Color("name")` resolves against
    // the environment at render time, which makes every view adaptive without any
    // call site changing. Values and their contrast checks live in
    // scripts/generate_theme_colors.py.

    static let background = Color("AppBackground")
    static let cardBackground = Color("AppCardBackground")
    static let separator = Color("AppSeparator")

    /// Accent for text, icons and tints — dark enough to read on a light surface.
    static let accent = Color("AppAccent")
    /// Accent as a filled area, e.g. the primary button. A fill needs saturation
    /// where text needs darkness, so the two cannot share one value in light mode.
    static let accentFill = Color("AppAccentFill")
    /// Text and glyphs drawn on top of `accentFill`.
    static let accentOnFill = Color("AppAccentOnFill")
    static let accentSecondary = Color("AppAccentSecondary")

    static let textPrimary = Color("AppTextPrimary")
    static let textSecondary = Color("AppTextSecondary")

    static let positive = Color("AppPositive")
    static let negative = Color("AppNegative")
    /// Destructive button fill. Deeper than `negative`, which is tuned to read as
    /// text; as a filled button that lighter red leaves white lettering illegible.
    static let negativeFill = Color("AppNegativeFill")
    static let negativeOnFill = Color("AppNegativeOnFill")

    /// Chart series, in order. Eight hues rather than four, so a sixth expense
    /// category no longer reuses the colour of the first.
    static let chartSeries: [Color] = (1...8).map { Color("ChartSeries\($0)") }

    // MARK: - Typography
    //
    // Relative to the user's text-size setting rather than fixed point sizes, so
    // the app responds to Dynamic Type. The PDF views keep fixed sizes, which is
    // correct for a fixed-size page.

    static let titleFont = Font.system(.title, design: .rounded).weight(.bold)
    static let headlineFont = Font.system(.headline, design: .rounded).weight(.semibold)
    static let bodyFont = Font.system(.body)
    static let captionFont = Font.system(.caption, design: .monospaced).weight(.medium)

    // MARK: - Metrics

    static let cornerRadius: CGFloat = 10.0
    static let generalPadding: CGFloat = 16.0
    static let sectionSpacing: CGFloat = 24.0

    static let shadow = Shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 3)
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
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
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
        HStack(spacing: 0) {
            // Laid out beside the content rather than as an overlay, which used to
            // paint the bar on top of the card's leading edge.
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)
            content
                .padding(AppTheme.generalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .shadow(color: AppTheme.shadow.color,
                radius: AppTheme.shadow.radius,
                x: AppTheme.shadow.x,
                y: AppTheme.shadow.y)
    }
}

/// The app's primary call to action.
///
/// Reads `\.isEnabled`, which the previous version ignored: a disabled Save button
/// looked exactly like an enabled one and simply did nothing when clicked. The
/// destructive variant exists for the same reason — Delete used to render as the
/// same mango pill as the primary action.
struct PillButtonStyle: ButtonStyle {
    enum Role {
        case primary
        case destructive
    }

    var role: Role = .primary

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.headlineFont)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(fill)
            .foregroundColor(label)
            .clipShape(Capsule())
            .opacity(isEnabled ? 1.0 : 0.55)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }

    private var fill: Color {
        guard isEnabled else { return AppTheme.separator }
        switch role {
        case .primary: return AppTheme.accentFill
        case .destructive: return AppTheme.negativeFill
        }
    }

    private var label: Color {
        guard isEnabled else { return AppTheme.textSecondary }
        switch role {
        case .primary: return AppTheme.accentOnFill
        case .destructive: return AppTheme.negativeOnFill
        }
    }
}

extension View {
    /// RE-ADDED: Helper to make applying the accent bar modifier easier.
    func accentBarCard(color: Color) -> some View {
        self.modifier(AccentBarCardStyle(accentColor: color))
    }
}

extension Color {
    /// Builds a colour from a six-digit hex string.
    ///
    /// The theme no longer uses this — its colours come from the asset catalog so
    /// they can adapt to the appearance — but it is kept for one-off values. The
    /// scan result is checked now; it used to be discarded, so any malformed
    /// string silently produced black.
    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#")
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else {
            assertionFailure("Color(hex:) given a value it cannot parse: \(hex)")
            self = .gray
            return
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
