// ContentView.swift

import SwiftUI

struct ContentView: View {
    
    @StateObject private var userSettings = UserSettings()
    @StateObject private var tabManager = TabSelectionManager()
    @State private var tabOrder: [TabItem] = []

    var body: some View {
        Group {
            #if os(macOS)
            // Custom layout for macOS to control tab resizing
            VStack(spacing: 0) {
                CustomTabBar(selectedTab: $tabManager.selectedTab, tabs: tabOrder)
                Divider()
                    .background(Color.black.opacity(0.4))
                
                // Display the view for the currently selected tab
                tabManager.selectedTab.view
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #else
            // Standard TabView for iOS native look and feel
            TabView(selection: $tabManager.selectedTab) {
                ForEach(tabOrder) { item in
                    item.view
                        .tabItem { Label(LocalizedStringKey(item.rawValue), systemImage: item.systemImage) }
                        .tag(item)
                }
            }
            #endif
        }
        .preferredColorScheme(.dark) // ADDITION: This line locks the app to dark mode.
        .onAppear(perform: loadTabOrder)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .environmentObject(tabManager)
    }
    
    private func loadTabOrder() {
        if let decodedOrder = try? JSONDecoder().decode([TabItem].self, from: userSettings.tabOrderData), !decodedOrder.isEmpty {
            self.tabOrder = decodedOrder
        } else {
            // Set default order if none is saved
            self.tabOrder = TabItem.allCases
        }
        
        // Ensure the selected tab is valid, otherwise default to the first in the order
        if !tabOrder.contains(tabManager.selectedTab) {
            if let firstTab = tabOrder.first {
                tabManager.selectedTab = firstTab
            }
        }
    }
}
