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
