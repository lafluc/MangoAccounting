// TabOrderSettingsView.swift

import SwiftUI

struct TabOrderSettingsView: View {
    @ObservedObject var settings: UserSettings
    @State private var tabs: [TabItem] = []

    var body: some View {
        List {
            ForEach(tabs) { tab in
                HStack {
                    Image(systemName: tab.systemImage)
                    Text(LocalizedStringKey(tab.rawValue))
                }
                // THEME: Make list rows transparent to show background
                .listRowBackground(Color.clear)
            }
            .onMove(perform: move)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Customize Tab Order")
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .onAppear(perform: loadTabs)
    }

    private func loadTabs() {
        if let decodedOrder = try? JSONDecoder().decode([TabItem].self, from: settings.tabOrderData) {
            self.tabs = decodedOrder
        } else {
            self.tabs = TabItem.allCases
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        if let encodedOrder = try? JSONEncoder().encode(tabs) {
            settings.tabOrderData = encodedOrder
        }
    }
}
