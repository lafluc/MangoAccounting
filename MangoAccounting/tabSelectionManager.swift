// TabSelectionManager.swift

import SwiftUI

/// An observable object to manage the active tab selection across the app.
class TabSelectionManager: ObservableObject {
    // The default tab can be any valid TabItem.
    @Published var selectedTab: TabItem = .dashboard
}
