// CustomTabBar.swift

import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: TabItem
    let tabs: [TabItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18))
                        Text(LocalizedStringKey(tab.rawValue))
                            .font(.system(size: 11))
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .foregroundColor(selectedTab == tab ? AppTheme.accent : AppTheme.textSecondary)
                    .background(
                        // Simplified background view
                        Group {
                            if selectedTab == tab {
                                AppTheme.cardBackground
                                    .cornerRadius(8)
                                    .padding(.horizontal, 4)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(AppTheme.background.ignoresSafeArea(edges: .top))
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }
}
