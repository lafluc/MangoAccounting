import SwiftUI
import UniformTypeIdentifiers

struct AnnualReportView: View {
    @StateObject private var userSettings = UserSettings()
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TransactionItem.date, ascending: true)],
        animation: .default)
    private var allTransactions: FetchedResults<TransactionItem>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AssetItem.purchaseDate, ascending: true)],
        animation: .default)
    private var allAssets: FetchedResults<AssetItem>

    @State private var selectedYear: Int = FiscalCalendar.year(of: Date())
    @State private var pdfPreviewItem: PDFPreview?
    @State private var showSaveToast = false
    @State private var saveErrorMessage: String?

    /// Bank balance and debts, kept per year.
    ///
    /// These were view state only, and on macOS the tab's view is swapped out on
    /// every tab change — so the figures the user typed vanished and a regenerated
    /// PDF quietly reported zero.
    @AppStorage("balanceSheetInputs") private var balanceSheetInputsData: Data = Data()
    @State private var inputLiquidAssets: Double?
    @State private var inputLiabilities: Double?

    @State private var isExportingPDF = false
    @State private var pdfFileToExport: PDFFile?

    /// Years with data, plus the current year and whatever is selected.
    ///
    /// Rows without a date are excluded here *and* from the totals below, so the
    /// two agree. Previously one branch dated them to today and the other to year
    /// 1, which put a year in the picker whose totals then omitted that row. The
    /// data model marks `date` as required, so this is a defensive case only.
    private var availableYears: [Int] {
        var years = Set(allTransactions.compactMap { $0.date.map(FiscalCalendar.year(of:)) })
        years.insert(FiscalCalendar.year(of: Date()))
        years.insert(selectedYear)
        return years.sorted(by: >)
    }

    private var transactionsForSelectedYear: [TransactionItem] {
        allTransactions.filter {
            guard let date = $0.date else { return false }
            return FiscalCalendar.year(of: date) == selectedYear
        }
    }

    private var reportForSelectedYear: ReportGenerator {
        ReportGenerator(
            transactions: transactionsForSelectedYear,
            assets: Array(allAssets),
            targetYear: selectedYear,
            liquidAssets: inputLiquidAssets ?? 0.0,
            liabilities: inputLiabilities ?? 0.0
        )
    }

    var body: some View {
        reportContent
            .navigationTitle("Annual Report")
            .background(AppTheme.background.ignoresSafeArea())
            .task { loadBalanceSheetInputs() }
            .onChange(of: selectedYear) { loadBalanceSheetInputs() }
    }

    private var reportContent: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(FiscalCalendar.yearText(year)).tag(year)
                        }
                    }
                    .pickerStyle(.segmented)

                    let report = reportForSelectedYear

                    VStack(alignment: .leading, spacing: 20) {
                        Text("Summary for \(FiscalCalendar.yearText(selectedYear))")
                            .font(AppTheme.titleFont)
                            .foregroundColor(AppTheme.textPrimary)

                        ReportCategoryList(title: "Ertrag", items: report.incomeByCategory)
                        ReportTotalRow(label: "Total Ertrag", value: report.totalIncome)

                        ReportCategoryList(title: "Aufwand", items: report.expensesByCategory)
                        ReportTotalRow(label: "Total Aufwand", value: report.totalExpenses)

                        if report.totalCarKilometers > 0 {
                            ReportTotalRow(label: "Total Kilometers Driven", value: report.totalCarKilometers, isCurrency: false)
                        }

                        Divider().background(AppTheme.textSecondary)

                        ReportTotalRow(label: report.netProfit >= 0 ? "Jahresgewinn" : "Jahresverlust", value: report.netProfit, font: .title3.bold())
                    }

                    SectionView(title: "Balance Sheet Data (Stichtag 31.12.)") {
                        CardView {
                            VStack(spacing: 12) {
                                TextField("Liquid assets (bank/cash) in CHF", value: $inputLiquidAssets, format: .number.precision(.fractionLength(0...2)))
                                    .onChange(of: inputLiquidAssets) { persistBalanceSheetInputs() }
                                    .textFieldStyle(.roundedBorder)

                                Divider()

                                TextField("Liabilities (debts) in CHF", value: $inputLiabilities, format: .number.precision(.fractionLength(0...2)))
                                    .onChange(of: inputLiabilities) { persistBalanceSheetInputs() }
                                    .textFieldStyle(.roundedBorder)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Button {
                        generateReportPDF()
                    } label: {
                        Label("Generate PDF Statement", systemImage: "doc.richtext.fill")
                    }
                    .buttonStyle(PillButtonStyle())
                    .padding(.top)
                }
                .padding()
            }
            .sheet(item: $pdfPreviewItem) { item in
                pdfPreviewSheet(for: item)
            }

            if showSaveToast {
                ToastView(title: "Report Saved")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func pdfPreviewSheet(for item: PDFPreview) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Erfolgsrechnung \(FiscalCalendar.yearText(selectedYear))")
                    .font(.headline)
                Spacer()

                Button {
                    exportReport(data: item.data)
                } label: {
                    Label("Export PDF to Folder", systemImage: "square.and.arrow.up")
                }
                .tint(AppTheme.accent)

                Button {
                    saveReport(data: item.data)
                } label: {
                    Label("Save to Archive", systemImage: "archivebox.fill")
                }
                .tint(AppTheme.accent)

                Button("Close", role: .cancel) { pdfPreviewItem = nil }
            }
            .padding()
            Divider()

            ScrollView([.horizontal, .vertical]) {
                PDFKitView(data: item.data)
                    .frame(width: 595.2, height: 841.8)
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .fileExporter(isPresented: $isExportingPDF, document: pdfFileToExport, contentType: .pdf) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                saveErrorMessage = error.localizedDescription
            }
        }
        .alert(
            "Annual Report",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func exportReport(data: Data) {
        let fileName = "Annual-Report-\(selectedYear).pdf"
        pdfFileToExport = PDFFile(data: data, preferredFileName: fileName)
        isExportingPDF = true
    }

    private func saveReport(data: Data) {
        let doc = SavedDocument(number: String(selectedYear), fileName: "Erfolgsrechnung-\(selectedYear).pdf", date: .now, type: .report)
        do {
            try DocumentStore.shared.save(document: doc, data: data)
        } catch {
            // Keep the preview open so the user can retry rather than losing it.
            saveErrorMessage = error.localizedDescription
            return
        }
        pdfPreviewItem = nil

        withAnimation { showSaveToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { showSaveToast = false }
        }
    }

    // MARK: - Persisted balance-sheet inputs

    /// Bank balance and debts keyed by fiscal year.
    private var storedBalanceSheetInputs: [String: BalanceSheetInputs] {
        (try? JSONDecoder().decode([String: BalanceSheetInputs].self, from: balanceSheetInputsData)) ?? [:]
    }

    private func loadBalanceSheetInputs() {
        let stored = storedBalanceSheetInputs[FiscalCalendar.yearText(selectedYear)]
        inputLiquidAssets = stored?.liquidAssets
        inputLiabilities = stored?.liabilities
    }

    private func persistBalanceSheetInputs() {
        var all = storedBalanceSheetInputs
        let key = FiscalCalendar.yearText(selectedYear)
        if inputLiquidAssets == nil && inputLiabilities == nil {
            all.removeValue(forKey: key)
        } else {
            all[key] = BalanceSheetInputs(
                liquidAssets: inputLiquidAssets, liabilities: inputLiabilities
            )
        }
        if let encoded = try? JSONEncoder().encode(all) {
            balanceSheetInputsData = encoded
        }
    }

    @MainActor
    private func generateReportPDF() {
        let mutableData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: CGSize(width: 595.2, height: 841.8))

        guard let consumer = CGDataConsumer(data: mutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return
        }

        let incomePage = AnnualReportPDFView(
            year: selectedYear,
            user: userSettings,
            report: reportForSelectedYear,
            page: .incomeStatement
        )
        let balancePage = AnnualReportPDFView(
            year: selectedYear,
            user: userSettings,
            report: reportForSelectedYear,
            page: .balanceSheet
        )

        // ImageRenderer does not inherit the SwiftUI environment, so the app's
        // language never reached the report and it printed in the system locale.
        // The scheme is pinned too: the app runs dark, and any semantic colour in
        // the page would otherwise resolve to light-on-white.
        let reportLocale = Locale(identifier: userSettings.formattingLocaleIdentifier)
        let incomeRenderer = ImageRenderer(
            content: incomePage
                .environment(\.locale, reportLocale)
                .environment(\.colorScheme, .light)
        )
        let balanceRenderer = ImageRenderer(
            content: balancePage
                .environment(\.locale, reportLocale)
                .environment(\.colorScheme, .light)
        )

        pdfContext.beginPDFPage(nil)
        incomeRenderer.render { _, renderInContext in renderInContext(pdfContext) }
        pdfContext.endPDFPage()

        pdfContext.beginPDFPage(nil)
        balanceRenderer.render { _, renderInContext in renderInContext(pdfContext) }
        pdfContext.endPDFPage()
        pdfContext.closePDF()

        pdfPreviewItem = PDFPreview(data: mutableData as Data)
    }
}

struct ReportCategoryList: View {
    let title: LocalizedStringKey
    let items: [(category: String, total: Double)]

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(AppTheme.headlineFont)
                .foregroundColor(AppTheme.textPrimary)
                .padding(.bottom, 4)

            VStack(spacing: 12) {
                ForEach(items, id: \.category) { item in
                    HStack {
                        Text(LocalizedStringKey(item.category)).foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Text(item.total, format: .currency(code: "CHF")).foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
            .padding()
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cornerRadius)
        }
    }
}

struct ReportTotalRow: View {
    let label: String
    let value: Double
    var font: Font = .body.bold()
    var isCurrency: Bool = true

    var body: some View {
        HStack {
            Text(LocalizedStringKey(label)).font(font).foregroundColor(AppTheme.textPrimary)
            Spacer()
            if isCurrency {
                Text(value, format: .currency(code: "CHF")).font(font).foregroundColor(AppTheme.textPrimary)
            } else {
                Text("\(value, specifier: "%.2f") km").font(font).foregroundColor(AppTheme.textPrimary)
            }
        }
    }
}

/// The two figures the balance sheet cannot derive from the ledger.
struct BalanceSheetInputs: Codable, Hashable {
    var liquidAssets: Double?
    var liabilities: Double?
}
