// AppAppearance.swift

import SwiftUI

/// Which light/dark appearance the app uses.
///
/// The app used to be pinned to dark with `.preferredColorScheme(.dark)`, because
/// the palette was a set of fixed dark colours and light mode looked wrong. Now
/// that the palette adapts, this becomes a choice — and it defaults to `.dark`, so
/// nobody's app changes appearance on update unless they ask for it.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    /// Existing installs have no stored value and must keep the look they know.
    static let defaultValue = AppAppearance.dark

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// `nil` follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
