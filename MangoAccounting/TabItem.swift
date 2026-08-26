import SwiftUI

enum TabItem: String, Codable, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case transactions = "Transactions"
    case assets = "Assets" // NEW
    case annualReport = "Annual Report"
    case newInvoice = "New Invoice"
    case saved = "Saved"
    case settings = "Settings"
    
    var id: String { self.rawValue }
    
    var systemImage: String {
        switch self {
        case .dashboard: return "chart.pie.fill"
        case .transactions: return "list.bullet"
        case .assets: return "briefcase.fill" // NEW
        case .annualReport: return "doc.text.image"
        case .newInvoice: return "doc.text.fill"
        case .saved: return "archivebox"
        case .settings: return "gear"
        }
    }
    
    @ViewBuilder
    var view: some View {
        switch self {
        case .dashboard: DashboardView()
        case .transactions: TransactionsListView()
        case .assets: AssetsListView() // NEW
        case .annualReport: AnnualReportView()
        case .newInvoice: InvoiceGeneratorView()
        case .saved: DocumentListView()
        case .settings: SettingsView()
        }
    }
}

extension TabItem {

    /// Decodes a saved tab order, healing it against the current set of tabs.
    ///
    /// Two things must happen that the previous per-view decoding did not do:
    /// unknown raw values (a tab removed in a later version) are dropped rather
    /// than failing the whole decode, and any tab missing from the saved order is
    /// appended. Without the append step a user who reordered their tabs before a
    /// new tab shipped would never see that tab, with no way to get it back —
    /// which is exactly what happened to the Assets tab.
    static func decodeOrder(from data: Data) -> [TabItem] {
        // Saved orders were written as an array of the String raw values, so
        // decoding to [String] reads every existing file unchanged.
        let saved = (try? JSONDecoder().decode([String].self, from: data)) ?? []

        var seen = Set<TabItem>()
        var order = saved
            .compactMap(TabItem.init(rawValue:))
            .filter { seen.insert($0).inserted }

        guard !order.isEmpty else { return allCases }

        order.append(contentsOf: allCases.filter { !seen.contains($0) })
        return order
    }

    /// Encodes in the same shape the app has always written, so an older build
    /// reading this order still understands it.
    static func encodeOrder(_ order: [TabItem]) -> Data? {
        try? JSONEncoder().encode(order.map(\.rawValue))
    }
}
