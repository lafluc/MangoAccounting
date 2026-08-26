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

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var pdfPreviewItem: PDFPreview?
    @State private var showSaveToast = false

    @State private var inputLiquidAssets: Double?
    @State private var inputLiabilities: Double?

    @State private var isExportingPDF = false
    @State private var pdfFileToExport: PDFFile?

    private var yearFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.groupingSeparator = ""
        return formatter
    }

    private var availableYears: [Int] {
        let years = Set(allTransactions.compactMap {
            Calendar.current.component(.year, from: $0.date ?? Date())
        })
        let allYears = years.isEmpty ? [selectedYear] : Array(years)
        return allYears.sorted(by: >)
    }

    private var transactionsForSelectedYear: [TransactionItem] {
        allTransactions.filter {
            Calendar.current.component(.year, from: $0.date ?? .distantPast) == selectedYear
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
    }

    private var reportContent: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(yearFormatter.string(from: NSNumber(value: year)) ?? "").tag(year)
                        }
                    }
                    .pickerStyle(.segmented)

                    let report = reportForSelectedYear

                    VStack(alignment: .leading, spacing: 20) {
                        Text("Summary for \(yearFormatter.string(from: NSNumber(value: selectedYear)) ?? "")")
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
                                TextField("Flussige Mittel (Bank/Kasse) in CHF", value: $inputLiquidAssets, format: .number)
                                    .textFieldStyle(.roundedBorder)

                                Divider()

                                TextField("Fremdkapital (Schulden) in CHF", value: $inputLiabilities, format: .number)
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
                Text("Erfolgsrechnung \(yearFormatter.string(from: NSNumber(value: selectedYear)) ?? "")")
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
                print("Failed to export PDF: \(error)")
            }
        }
    }

    private func exportReport(data: Data) {
        let fileName = "Annual-Report-\(selectedYear).pdf"
        pdfFileToExport = PDFFile(data: data, preferredFileName: fileName)
        isExportingPDF = true
    }

    private func saveReport(data: Data) {
        let doc = SavedDocument(id: String(selectedYear), fileName: "Erfolgsrechnung-\(selectedYear).pdf", date: .now, type: .report)
        DocumentStore.shared.save(document: doc, data: data)
        pdfPreviewItem = nil

        withAnimation { showSaveToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { showSaveToast = false }
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

        let incomeRenderer = ImageRenderer(content: incomePage)
        let balanceRenderer = ImageRenderer(content: balancePage)

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
