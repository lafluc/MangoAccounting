// DashboardView.swift

import SwiftUI
import CoreData
import Charts

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TransactionItem.date, ascending: true)],
        animation: .default)
    private var transactions: FetchedResults<TransactionItem>

    @State private var selectedTimeframe: Timeframe = .allTime

    enum Timeframe: String, CaseIterable, Identifiable {
        case last30Days = "Last 30 Days"
        case last90Days = "Last 90 Days"
        case yearToDate = "Year to Date"
        case allTime = "All Time"
        var id: Self { self }
    }
    
    private var filteredTransactions: [TransactionItem] {
        let now = Date()
        let calendar = FiscalCalendar.calendar

        switch selectedTimeframe {
        case .last30Days:
            guard let startDate = calendar.date(byAdding: .day, value: -30, to: now) else {
                return Array(transactions)
            }
            return transactions.filter { ($0.date ?? .distantPast) >= startDate }
        case .last90Days:
            guard let startDate = calendar.date(byAdding: .day, value: -90, to: now) else {
                return Array(transactions)
            }
            return transactions.filter { ($0.date ?? .distantPast) >= startDate }
        case .yearToDate:
            let yearStart = FiscalCalendar.yearBounds(FiscalCalendar.year(of: now)).start
            return transactions.filter { ($0.date ?? .distantPast) >= yearStart }
        case .allTime:
            return Array(transactions)
        }
    }

    var body: some View {
        dashboardContent
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Dashboard")
    }
    
    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CustomTimeframePicker(selection: $selectedTimeframe)
                    .padding(.horizontal)

                SummaryView(transactions: filteredTransactions)
                    .padding(.horizontal)

                ChartSection(title: "Net Profit Trend") {
                    CumulativeProfitChartView(transactions: filteredTransactions)
                }
                
                ChartSection(title: "Expense Categories") {
                    CategoryChartView(transactions: filteredTransactions.filter { $0.type == "Expense" })
                }
                
                RecentTransactionsSection(transactions: Array(filteredTransactions.sorted(by: { $0.date ?? .distantPast > $1.date ?? .distantPast }).prefix(5)))

            }
            .padding(.vertical)
        }
    }
}

// MARK: - Custom Subviews and Components

struct CustomTimeframePicker: View {
    @Binding var selection: DashboardView.Timeframe
    
    var body: some View {
        HStack {
            ForEach(DashboardView.Timeframe.allCases) { timeframe in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = timeframe
                    }
                }) {
                    Text(LocalizedStringKey(timeframe.rawValue))
                        .font(AppTheme.bodyFont)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        // A 30%-opacity accent wash sat at about 3:1 against the
                        // card in light mode. The selected chip now uses the same
                        // fill-and-label pair as the primary button, which is
                        // legible in both appearances.
                        .background(selection == timeframe ? AppTheme.accentFill : Color.clear)
                        .foregroundColor(selection == timeframe ? AppTheme.accentOnFill : AppTheme.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                // Without this macOS draws its own bordered button underneath, so
                // unselected chips appeared as grey capsules.
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == timeframe ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
}

struct ChartSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTheme.headlineFont)
                .foregroundColor(AppTheme.textPrimary)
                .padding(.horizontal)
            
            // FIX: Use the generic CardView container
            CardView {
                content.frame(height: 250) // Adjusted height to fit padding
            }
            .padding(.horizontal)
        }
    }
}

struct RecentTransactionsSection: View {
    let transactions: [TransactionItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Transactions")
                .font(AppTheme.headlineFont)
                .foregroundColor(AppTheme.textPrimary)
                .padding(.horizontal)
            
            if transactions.isEmpty {
                // FIX: Use the generic CardView container
                CardView {
                    Text("No transactions in this period.")
                        .font(.headline)
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                }
                .padding(.horizontal)

            } else {
                // FIX: Use the generic CardView container
                CardView {
                    VStack(spacing: 0) {
                        ForEach(transactions, id: \.objectID) { t in
                            NavigationLink(destination: TransactionDetailView(transaction: t)) {
                                TransactionRowView(transaction: t)
                                    .padding(.vertical, 8) // Adjusted padding
                                    // The row is mostly Spacer, and a Spacer is
                                    // not hit-testable: without this, clicking
                                    // anywhere but the text did nothing.
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if t.objectID != transactions.last?.objectID {
                                Divider().background(AppTheme.background)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct SummaryView: View {
    let transactions: [TransactionItem]

    private var totalIncome: Double {
        transactions.filter { $0.type == "Income" }.reduce(0) { $0 + $1.amount }
    }
    private var totalExpense: Double {
        transactions.filter { $0.type == "Expense" }.reduce(0) { $0 + $1.amount }
    }
    private var netProfit: Double { totalIncome - totalExpense }

    var body: some View {
        VStack(spacing: 12) {
            SummaryCard(title: "Total Income", value: totalIncome, color: AppTheme.positive)
            SummaryCard(title: "Total Expense", value: totalExpense, color: AppTheme.negative)
            SummaryCard(title: "Net Profit", value: netProfit, color: AppTheme.accentSecondary)
        }
    }
}

struct SummaryCard: View {
    let title: LocalizedStringKey
    let value: Double
    let color: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.textSecondary)
                
                Text(value, format: .currency(code: "CHF"))
                    .font(AppTheme.titleFont.weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            Spacer()
        }
        // FIX: This now compiles because AccentBarCardStyle exists again.
        .modifier(AccentBarCardStyle(accentColor: color))
    }
}

// ... (CumulativeProfitChartView and CategoryChartView remain the same)
struct CumulativeProfitChartView: View {
    let transactions: [TransactionItem]
    @State private var selectedDate: Date?
    @State private var selectedProfit: Double?
    /// Identified by its date, not a fresh UUID: a new identity on every
    /// recomputation made the chart re-animate from scratch on unrelated state
    /// changes.
    struct DailyNet: Identifiable { let date: Date; var cumulativeProfit: Double; var id: Date { date } }
    private var chartData: [DailyNet] {
        guard !transactions.isEmpty else { return [] }
        let calendar = FiscalCalendar.calendar
        let groupedByDay = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.date ?? .now) }
        let dailyChanges = groupedByDay.map { (date, txs) -> (Date, Double) in
            let net = txs.reduce(0) { $0 + ($1.type == "Income" ? $1.amount : -$1.amount) }
            return (date, net)
        }.sorted { $0.0 < $1.0 }
        var cumulativeData = [DailyNet]()
        var runningTotal: Double = 0
        for (date, netChange) in dailyChanges {
            runningTotal += netChange
            cumulativeData.append(DailyNet(date: date, cumulativeProfit: runningTotal))
        }
        return cumulativeData
    }
    var body: some View {
        if chartData.count < 2 {
            Text("Not enough data to display a trend.").font(.callout).foregroundColor(AppTheme.textSecondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(chartData) { dataPoint in
                    LineMark(x: .value("Date", dataPoint.date, unit: .day), y: .value("Profit", dataPoint.cumulativeProfit)).interpolationMethod(.catmullRom).foregroundStyle(AppTheme.accent).symbol(Circle().strokeBorder(lineWidth: 2))
                    AreaMark(x: .value("Date", dataPoint.date, unit: .day), y: .value("Profit", dataPoint.cumulativeProfit)).interpolationMethod(.catmullRom).foregroundStyle(LinearGradient(gradient: Gradient(colors: [AppTheme.accent.opacity(0.5), AppTheme.accent.opacity(0.05)]), startPoint: .top, endPoint: .bottom))
                }
                if let selectedDate, let selectedProfit {
                    RuleMark(x: .value("Date", selectedDate)).foregroundStyle(Color.gray.opacity(0.5)).annotation(position: .top, alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading) {
                            Text(selectedDate, format: .dateTime.day().month().year()).font(AppTheme.captionFont).foregroundColor(AppTheme.textSecondary)
                            Text(selectedProfit, format: .currency(code: "CHF")).font(AppTheme.headlineFont).foregroundColor(AppTheme.accent)
                        }.padding(8).background(.thinMaterial).cornerRadius(8)
                    }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { AxisGridLine().foregroundStyle(AppTheme.textSecondary); AxisValueLabel().foregroundStyle(AppTheme.textSecondary) } }
            .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(AppTheme.textSecondary); AxisValueLabel().foregroundStyle(AppTheme.textSecondary) } }
            .chartOverlay { proxy in GeometryReader { geometry in Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 8).onChanged { value in let location = value.location; if let date: Date = proxy.value(atX: location.x) { updateSelection(at: date) } }.onEnded { _ in selectedDate = nil; selectedProfit = nil }) } }
        }
    }
    private func updateSelection(at date: Date) { selectedDate = date; if let closestDataPoint = chartData.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) { selectedProfit = closestDataPoint.cumulativeProfit } }
}
struct CategoryChartView: View {
    let transactions: [TransactionItem]
    private struct CategorySummary: Identifiable { let category: String; let total: Double; var id: String { category } }
    private var categoryData: [CategorySummary] {
        let grouped = Dictionary(grouping: transactions) { $0.category ?? "Uncategorized" }
        return grouped.map { (cat, trans) in let total = trans.reduce(0) { $0 + $1.amount }; return CategorySummary(category: cat, total: total) }.sorted(by: { $0.total > $1.total })
    }
    var body: some View {
        Chart(categoryData) { data in
            SectorMark(angle: .value("Amount", data.total), innerRadius: .ratio(0.618), angularInset: 1.5).foregroundStyle(by: .value("Category", data.category)).cornerRadius(5)
        }
        .chartForegroundStyleScale(range: AppTheme.chartSeries)
        .chartLegend(position: .bottom, alignment: .center, spacing: 15)
    }
}
