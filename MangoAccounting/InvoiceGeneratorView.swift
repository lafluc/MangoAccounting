// InvoiceGeneratorView.swift

import SwiftUI
import PDFKit

// =================================================================
// MARK: - LineItemRowView Subview
// =================================================================
struct LineItemRowView: View {
    @Binding var item: InvoiceLineItem
    var deleteAction: () -> Void

    var body: some View {
        HStack {
            TextField("Description", text: $item.description)

            TextField("Amount", value: $item.amount, format: .number.precision(.fractionLength(0...2)))
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .frame(width: 120)
                .multilineTextAlignment(.trailing)

            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundColor(AppTheme.negative)
            .help("Remove this line")
        }
    }
}


struct InvoiceGeneratorView: View {
    @Environment(\.locale) var locale
    @Environment(\.dismiss) private var dismiss
    @StateObject private var userSettings = UserSettings()
    @EnvironmentObject var tabManager: TabSelectionManager

    /// The archived invoice being edited, or `nil` when composing a new one.
    var editingDocument: SavedDocument?
    /// Starting values — an existing invoice's source, or a prefill for a duplicate.
    var initialDraft: InvoiceDraft?

    @State private var draft = InvoiceDraft()
    @State private var hasLoaded = false
    @State private var pdfPreviewItem: PDFPreview?
    @State private var showSaveToast = false
    @State private var showOverwriteAlert = false
    @State private var dataToSave: Data?
    @State private var saveErrorMessage: String?

    private var isEditing: Bool { editingDocument != nil }

    /// Swiss QR-bill payloads cap the amount at this value.
    private static let maximumInvoiceAmount: Double = 999_999_999.99

    private var isFormValid: Bool {
        !draft.issuer.name.isEmpty
            && !draft.issuer.iban.isEmpty
            && !draft.issuer.address.isEmpty
            && !draft.clientName.isEmpty
            && !draft.number.isEmpty
            && draft.total > 0
            && draft.total <= Self.maximumInvoiceAmount
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
            .navigationTitle(Text(isEditing ? "Edit Invoice" : "New Invoice"))
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .sheet(item: $pdfPreviewItem) { item in
                pdfPreviewSheet(for: item)
            }
            .task { loadOnce() }
            .onChange(of: tabManager.selectedTab) {
                // Only the composer tab refreshes its suggested number, and only
                // while the form is untouched. An edit session must never have its
                // number rewritten underneath it.
                guard !isEditing, tabManager.selectedTab == .newInvoice, isPristine else { return }
                draft.number = generateSequentialInvoiceNumber()
            }
            .alert(
                "Invoice",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }

            if showSaveToast {
                ToastView(title: "Invoice Saved")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var isPristine: Bool {
        draft.clientName.isEmpty
            && draft.clientAddress.isEmpty
            && draft.lineItems.count == 1
            && draft.lineItems.first?.description.isEmpty == true
            && draft.lineItems.first?.amount == 0
    }

    // MARK: - Loading

    private func loadOnce() {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let initialDraft {
            draft = initialDraft
            // A duplicate arrives without a number so it gets a fresh one.
            if draft.number.isEmpty {
                draft.number = generateSequentialInvoiceNumber()
            }
            if draft.issuer.name.isEmpty && draft.issuer.iban.isEmpty {
                draft.issuer = InvoiceIssuer(settings: userSettings)
            }
            return
        }

        // A new invoice starts from the saved business details, then keeps its own
        // copy: editing the form no longer rewrites app-wide settings as you type.
        draft.issuer = InvoiceIssuer(settings: userSettings)
        draft.customMessage = Self.defaultClosingMessage
        draft.number = generateSequentialInvoiceNumber()
    }

    private static let defaultClosingMessage = "Vielen Dank für die gute Zusammenarbeit."

    // MARK: - Form Sections

    private var yourInformationSection: some View {
        SectionView(title: "Your Information") {
            CardView {
                VStack {
                    TextField("Name", text: $draft.issuer.name)
                    Divider()
                    TextField("Address", text: $draft.issuer.address, axis: .vertical).lineLimit(1...3)
                    Divider()
                    TextField("UID (CHE-...)", text: $draft.issuer.uid)
                        .autocorrectionDisabled()
                    Divider()
                    TextField("IBAN (CH...)", text: $draft.issuer.iban)
                        .autocorrectionDisabled()
                }
            }
        }
    }

    private var clientInformationSection: some View {
        SectionView(title: "Client Information") {
            CardView {
                VStack {
                    TextField("Client Name", text: $draft.clientName)
                    Divider()
                    TextField("Client Address", text: $draft.clientAddress, axis: .vertical).lineLimit(1...3)
                }
            }
        }
    }

    private var invoiceDetailsSection: some View {
        SectionView(title: "Invoice Details") {
            CardView {
                VStack {
                    TextField("Invoice Number", text: $draft.number)
                        .autocorrectionDisabled()
                    Divider()
                    DatePicker("Invoice Date", selection: $draft.invoiceDate, displayedComponents: .date)
                    Divider()
                    DatePicker("Due Date", selection: $draft.dueDate, displayedComponents: .date)
                }
            }
        }
    }

    private var vatExemptionSection: some View {
        SectionView(title: "VAT Exemption") {
            Toggle("Not subject to VAT according to Art. 10 Abs. 2 MWSTG", isOn: $draft.isVATExempt)
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(AppTheme.cornerRadius)
        }
    }

    private var messageToClientSection: some View {
        SectionView(title: "Message to Client") {
            TextEditor(text: $draft.customMessage)
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
                    ForEach($draft.lineItems) { $item in
                        LineItemRowView(item: $item) {
                            draft.lineItems.removeAll { $0.id == item.id }
                        }
                        if item.id != draft.lineItems.last?.id {
                            Divider()
                        }
                    }

                    Button("Add Item") {
                        draft.lineItems.append(InvoiceLineItem())
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
                    Text(draft.total, format: .currency(code: "CHF")).bold()
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
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("Preview: %@", comment: ""), draft.number
                ))
                .font(.headline)
                Spacer()
                Button {
                    initiateSave(data: item.data)
                } label: {
                    Label(isEditing ? "Save Changes" : "Save", systemImage: "archivebox.fill")
                }
                .tint(AppTheme.accent)
                .keyboardShortcut("s", modifiers: .command)

                Button("Close", role: .cancel) { pdfPreviewItem = nil }
            }
            .padding()
            Divider()
            ScrollView([.horizontal, .vertical]) {
                PDFKitView(data: item.data)
                    .frame(
                        width: InvoicePagination.pageSize.width,
                        height: InvoicePagination.pageSize.height * CGFloat(max(1, pageCount(of: item.data)))
                    )
            }
        }
        .frame(minWidth: 480, idealWidth: 640, minHeight: 480, idealHeight: 720)
        .alert("Invoice Number Exists", isPresented: $showOverwriteAlert) {
            Button("Overwrite", role: .destructive) {
                let data = dataToSave
                dataToSave = nil
                if let data { saveInvoice(data: data) }
            }
            Button("Cancel", role: .cancel) {
                dataToSave = nil
            }
        } message: {
            Text("An invoice with the number \"\(draft.number)\" already exists.\nDo you want to overwrite it?")
        }
    }

    private func pageCount(of data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 1
    }

    // MARK: - Saving

    private func initiateSave(data: Data) {
        let existing: [SavedDocument]
        do {
            existing = try DocumentStore.shared.documents().filter { $0.type == .invoice }
        } catch {
            saveErrorMessage = error.localizedDescription
            return
        }

        let targetID = SavedDocument(
            number: draft.number,
            fileName: DocumentStore.invoiceFileName(for: draft.number),
            date: draft.invoiceDate,
            type: .invoice
        ).id

        // Re-saving the invoice you are editing is not a collision.
        let collides = existing.contains { $0.id == targetID } && editingDocument?.id != targetID
        if collides {
            dataToSave = data
            showOverwriteAlert = true
        } else {
            saveInvoice(data: data)
        }
    }

    private func saveInvoice(data: Data) {
        do {
            try DocumentStore.shared.save(invoice: draft, pdf: data, replacing: editingDocument)
        } catch {
            // The previous version showed "Invoice Saved" and cleared the form even
            // when nothing had been written, destroying the user's input.
            saveErrorMessage = error.localizedDescription
            return
        }

        // A new invoice updates the stored business details for next time. An edit
        // must not write a historical snapshot back over current settings.
        if !isEditing {
            userSettings.name = draft.issuer.name
            userSettings.address = draft.issuer.address
            userSettings.uid = draft.issuer.uid
            userSettings.iban = draft.issuer.iban
        }

        pdfPreviewItem = nil

        if isEditing {
            dismiss()
            return
        }

        withAnimation { showSaveToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { showSaveToast = false }
        }
        resetForm()
    }

    private func resetForm() {
        let issuer = draft.issuer
        draft = InvoiceDraft()
        draft.issuer = issuer
        draft.customMessage = Self.defaultClosingMessage
        draft.number = generateSequentialInvoiceNumber()
    }

    // MARK: - Rendering

    @MainActor
    private func generateAndShowPDF() {
        guard let data = renderPDF() else {
            saveErrorMessage = String(
                localized: "The PDF could not be created. Please try again."
            )
            return
        }
        pdfPreviewItem = PDFPreview(data: data)
    }

    @MainActor
    private func renderPDF() -> Data? {
        // Fully blank rows are working scaffolding, not billable lines.
        let printableItems = draft.lineItems.filter {
            !($0.description.trimmingCharacters(in: .whitespaces).isEmpty && $0.amount == 0)
        }
        let pages = InvoicePagination.paginate(
            printableItems,
            messageLineCount: InvoicePagination.messageLineCount(for: draft.customMessage)
        )

        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: InvoicePagination.pageSize)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for page in pages {
            let content = InvoiceView(draft: draft, page: page, locale: locale)
            let renderer = ImageRenderer(content: content.environment(\.locale, locale))
            pdfContext.beginPDFPage(nil)
            renderer.render { _, renderInContext in renderInContext(pdfContext) }
            pdfContext.endPDFPage()
        }
        pdfContext.closePDF()

        return mutableData as Data
    }

    // MARK: - Numbering

    private func generateSequentialInvoiceNumber() -> String {
        // POSIX locale and an explicit Gregorian calendar: under a non-Gregorian
        // calendar or non-Latin digits the prefix drifted and the Int parse below
        // failed, which produced duplicate invoice numbers.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd"
        let datePrefix = formatter.string(from: Date())
        let fullPrefix = "RE-\(datePrefix)"

        // A suggested number is cosmetic, so the display-safe reader is fine here;
        // initiateSave() re-checks against the throwing reader before writing.
        let allInvoices = DocumentStore.shared.listDocuments().filter { $0.type == .invoice }

        let existingSequenceNumbers: Set<Int> = Set(allInvoices.compactMap { doc -> Int? in
            if doc.number == fullPrefix {
                return 0
            } else if doc.number.starts(with: "\(fullPrefix)-") {
                guard let lastPart = doc.number.split(separator: "-").last,
                      let number = Int(lastPart) else { return nil }
                return number
            } else {
                return nil
            }
        })

        var nextSequenceNumber = 0
        while existingSequenceNumbers.contains(nextSequenceNumber) {
            nextSequenceNumber += 1
        }

        return nextSequenceNumber == 0 ? fullPrefix : "\(fullPrefix)-\(nextSequenceNumber)"
    }
}

private extension String {
    init(localized key: String.LocalizationValue) {
        self.init(localized: key, bundle: .main)
    }
}
