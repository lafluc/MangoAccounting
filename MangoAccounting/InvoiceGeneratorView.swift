// InvoiceGeneratorView.swift

import SwiftUI
import PDFKit

// =================================================================
// MARK: - LineItemRowView Subview
// This view handles the layout for a single line item.
// =================================================================
struct LineItemRowView: View {
    @Binding var item: InvoiceGeneratorView.LineItem
    var deleteAction: () -> Void

    var body: some View {
        HStack {
            TextField("Description", text: $item.description)
            
            TextField("Amount", value: $item.amount, format: .currency(code: "CHF"))
                // THE FIX IS HERE: This modifier is now only applied for iOS builds.
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .frame(width: 120)
                .multilineTextAlignment(.trailing)

            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundColor(AppTheme.negative)
        }
    }
}


struct InvoiceGeneratorView: View {
    @Environment(\.locale) var locale
    @StateObject private var userSettings = UserSettings()
    @EnvironmentObject var tabManager: TabSelectionManager
    
    @State private var clientName: String = ""
    @State private var clientAddress: String = ""
    
    @State private var invoiceNumber: String = ""
    @State private var invoiceDate: Date = .now
    @State private var dueDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
    @State private var customMessage: String = "Vielen Dank für die gute Zusammenarbeit."
    @State private var isVATExempt: Bool = false
    
    struct LineItem: Identifiable, Hashable { let id = UUID(); var description: String; var amount: Double }
    @State private var lineItems: [LineItem] = [LineItem(description: "", amount: 0)]
    @State private var pdfPreviewItem: PDFPreview?
    @State private var showSaveToast = false

    @State private var showOverwriteAlert = false
    @State private var dataToSave: Data?
    private var totalAmount: Double { lineItems.reduce(0) { $0 + max(0, $1.amount) } }
    private var a4Size = CGSize(width: 595.2, height: 841.8)
    private var isFormValid: Bool {
        !userSettings.name.isEmpty && !userSettings.iban.isEmpty && !userSettings.address.isEmpty && !clientName.isEmpty && !lineItems.isEmpty && totalAmount > 0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    yourInformationSection
                    clientInformationSection
                    invoiceDetailsSection
                    vatExemptionSection
                    messageToClientSection
                    lineItemsSection
                    totalSection
                    generatePDFButton
                }
                .padding()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(Text("New Invoice"))
            .sheet(item: $pdfPreviewItem) { item in
                pdfPreviewSheet(for: item)
            }
            .onAppear {
                if invoiceNumber.isEmpty {
                    invoiceNumber = generateSequentialInvoiceNumber()
                }
            }
            .onChange(of: tabManager.selectedTab) {
                if tabManager.selectedTab == .newInvoice {
                    let isPristine = clientName.isEmpty &&
                                     clientAddress.isEmpty &&
                                     lineItems.count == 1 &&
                                     lineItems.first?.description == "" &&
                                     lineItems.first?.amount == 0
                    
                    if isPristine {
                        invoiceNumber = generateSequentialInvoiceNumber()
                    }
                }
            }
            
            if showSaveToast {
                ToastView(title: "Invoice Saved")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Form Sections
    
    private var yourInformationSection: some View {
        SectionView(title: "Your Information") {
            CardView {
                VStack {
                    TextField("Name", text: $userSettings.name)
                    Divider()
                    TextField("Address", text: $userSettings.address, axis: .vertical).lineLimit(1...3)
                    Divider()
                    // ADDITION: New TextField for the UID
                    TextField("UID (CHE-...)", text: $userSettings.uid)
                    Divider()
                    TextField("IBAN (CH...)", text: $userSettings.iban)
                }
            }
        }
    }
    
    private var clientInformationSection: some View {
        SectionView(title: "Client Information") {
            CardView {
                VStack {
                    TextField("Client Name", text: $clientName)
                    Divider()
                    TextField("Client Address", text: $clientAddress, axis: .vertical).lineLimit(1...3)
                }
            }
        }
    }
    
    private var invoiceDetailsSection: some View {
        SectionView(title: "Invoice Details") {
            CardView {
                VStack {
                    TextField("Invoice Number", text: $invoiceNumber)
                    Divider()
                    DatePicker("Invoice Date", selection: $invoiceDate, displayedComponents: .date)
                    Divider()
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                }
            }
        }
    }
    
    private var vatExemptionSection: some View {
        SectionView(title: "VAT Exemption") {
            Toggle("Not subject to VAT according to Art. 10 Abs. 2 MWSTG", isOn: $isVATExempt)
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(AppTheme.cornerRadius)
        }
    }
    
    private var messageToClientSection: some View {
        SectionView(title: "Message to Client") {
            TextEditor(text: $customMessage)
                .frame(minHeight: 120)
                .padding(8)
                .background(AppTheme.cardBackground)
                .cornerRadius(AppTheme.cornerRadius)
                .scrollContentBackground(.hidden)
        }
    }
    
    private var lineItemsSection: some View {
        SectionView(title: "Line Items") {
            CardView {
                VStack {
                    ForEach(lineItems) { item in
                        if let index = lineItems.firstIndex(where: { $0.id == item.id }) {
                            LineItemRowView(item: $lineItems[index]) {
                                lineItems.removeAll { $0.id == item.id }
                            }
                            
                            if item.id != lineItems.last?.id {
                                Divider()
                            }
                        }
                    }
                    
                    Button("Add Item") {
                        lineItems.append(LineItem(description: "", amount: 0))
                    }
                    .tint(AppTheme.accent)
                    .padding(.top, 8)
                }
            }
        }
    }
    
    private var totalSection: some View {
        SectionView(title: "Total") {
            CardView {
                HStack {
                    Text("Total Amount").bold()
                    Spacer()
                    Text(totalAmount, format: .currency(code: "CHF")).bold()
                }
            }
        }
    }
    
    private var generatePDFButton: some View {
        Button {
            generateAndShowPDF()
        } label: {
            Label("Generate & Preview PDF", systemImage: "doc.richtext")
                .fontWeight(.semibold)
        }
        .buttonStyle(PillButtonStyle())
        .disabled(!isFormValid)
        .padding(.top)
    }
    
    @ViewBuilder
    private func pdfPreviewSheet(for item: PDFPreview) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(String.localizedStringWithFormat(NSLocalizedString("Preview: %@", comment: ""), invoiceNumber))
                    .font(.headline)
                Spacer()
                Button {
                    initiateSave(data: item.data)
                } label: {
                    Label("Save", systemImage: "archivebox.fill")
                }
                .tint(AppTheme.accent)
                Button("Close", role: .cancel) { pdfPreviewItem = nil }
            }
            .padding()
            Divider()
            ScrollView([.horizontal, .vertical]) {
                PDFKitView(data: item.data)
                     .frame(width: a4Size.width, height: a4Size.height)
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .alert("Invoice Number Exists", isPresented: $showOverwriteAlert) {
            Button("Overwrite", role: .destructive) {
                if let data = dataToSave {
                    saveInvoice(data: data)
                }
            }
            Button("Cancel", role: .cancel) {
                dataToSave = nil
            }
        } message: {
            Text("An invoice with the number \"\(invoiceNumber)\" already exists.\nDo you want to overwrite it?")
        }
    }

    private func initiateSave(data: Data) {
        let existingIDs = DocumentStore.shared.listDocuments()
            .filter { $0.type == .invoice }
            .map { $0.id }

        if existingIDs.contains(invoiceNumber) {
            self.dataToSave = data
            self.showOverwriteAlert = true
        } else {
            saveInvoice(data: data)
        }
    }

    private func saveInvoice(data: Data) {
        let doc = SavedDocument(
            id: invoiceNumber,
            fileName: "Invoice-\(invoiceNumber).pdf",
            date: invoiceDate,
            type: .invoice,
            clientName: clientName
        )
        
        DocumentStore.shared.save(document: doc, data: data)
        pdfPreviewItem = nil
        
        withAnimation {
            showSaveToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            withAnimation {
                showSaveToast = false
            }
        }
        
        resetForm()
    }
    
    private func resetForm() {
        clientName = ""
        clientAddress = ""
        invoiceDate = .now
        dueDate = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
        customMessage = "Vielen Dank für die gute Zusammenarbeit."
        isVATExempt = false
        lineItems = [LineItem(description: "", amount: 0)]
        
        invoiceNumber = generateSequentialInvoiceNumber()
    }

    @MainActor
    private func generateAndShowPDF() {
         let invoiceContent = InvoiceView(
            userSettings: userSettings, clientName: clientName, clientAddress: clientAddress,
            invoiceNumber: invoiceNumber, invoiceDate: invoiceDate, dueDate: dueDate,
            lineItems: lineItems, totalAmount: totalAmount, customMessage: customMessage,
            isVATExempt: isVATExempt,
            locale: self.locale
        )
        let renderer = ImageRenderer(content: invoiceContent.environment(\.locale, self.locale))
        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData) else { return }
        var mediaBox = CGRect(origin: .zero, size: a4Size)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
        pdfContext.beginPDFPage(nil)
        renderer.render { size, renderer in renderer(pdfContext) }
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        pdfPreviewItem = PDFPreview(data: mutableData as Data)
    }
    
    private func generateSequentialInvoiceNumber() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let datePrefix = formatter.string(from: Date())
        let fullPrefix = "RE-\(datePrefix)"

        let allInvoices = DocumentStore.shared.listDocuments().filter { $0.type == .invoice }

        let existingSequenceNumbers: Set<Int> = Set(allInvoices.compactMap { doc -> Int? in
            if doc.id == fullPrefix {
                return 0
            } else if doc.id.starts(with: "\(fullPrefix)-") {
                guard let lastPart = doc.id.split(separator: "-").last, let number = Int(lastPart) else {
                    return nil
                }
                return number
            } else {
                return nil
            }
        })

        var nextSequenceNumber = 0
        while existingSequenceNumbers.contains(nextSequenceNumber) {
            nextSequenceNumber += 1
        }

        if nextSequenceNumber == 0 {
            return fullPrefix
        } else {
            return "\(fullPrefix)-\(nextSequenceNumber)"
        }
    }
}
