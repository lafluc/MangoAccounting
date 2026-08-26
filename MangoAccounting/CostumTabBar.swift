// CustomTabBar.swift

import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: TabItem
    let tabs: [TabItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18))
                        Text(LocalizedStringKey(tab.rawValue))
                            .font(.system(size: 11))
                            // Seven tabs at 11pt truncate on a narrow window.
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .foregroundColor(selectedTab == tab ? AppTheme.accent : AppTheme.textSecondary)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.cardBackground)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(LocalizedStringKey(tab.rawValue))
                .accessibilityLabel(LocalizedStringKey(tab.rawValue))
                .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)
                // Cmd-1 through Cmd-9 jump straight to a tab.
                .modifier(TabKeyboardShortcut(index: index))
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(AppTheme.background.ignoresSafeArea(edges: .top))
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }
}

/// Attaches Cmd-1 … Cmd-9 to a tab button, by position.
private struct TabKeyboardShortcut: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if let key = Self.keys[safe: index] {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }

    private static let keys: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
