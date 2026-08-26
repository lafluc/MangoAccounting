// DocumentListView.swift

import SwiftUI
import UniformTypeIdentifiers

@MainActor
class DocumentListViewModel: ObservableObject {
    @Published var documents: [SavedDocument] = []
    @Published var selectedDocumentID: SavedDocument.ID? {
        didSet { updatePreview() }
    }
    @Published var previewData: Data?
    /// Non-nil when the archive could not be read or written. Presented as an
    /// alert; previously these failures were silent.
    @Published var errorMessage: String?
    /// Ids of invoices that have an editable source saved beside their PDF.
    /// Anything archived before that existed is absent here and stays read-only.
    @Published var editableIDs: Set<String> = []
    var allDocuments: [SavedDocument] = []

    func reloadDocuments() {
        let all: [SavedDocument]
        do {
            all = try DocumentStore.shared.documents()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        self.allDocuments = all
        self.documents = all
        self.editableIDs = DocumentStore.shared.idsWithDrafts()

        if selectedDocumentID == nil || !documents.contains(where: { $0.id == selectedDocumentID }) {
            selectedDocumentID = documents.first?.id
        } else {
            updatePreview()
        }
    }
    
    func filter(with query: String) {
        if query.isEmpty {
            documents = allDocuments
        } else {
            documents = allDocuments.filter { doc in
                doc.fileName.localizedCaseInsensitiveContains(query) || (doc.clientName ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        if let selectedId = selectedDocumentID, !documents.contains(where: { $0.id == selectedId }) {
            selectedDocumentID = nil
        }
    }
    
    func isEditable(_ document: SavedDocument) -> Bool {
        document.type == .invoice && editableIDs.contains(document.id)
    }

    func updatePreview() {
        guard let id = selectedDocumentID,
           let document = allDocuments.first(where: { $0.id == id }) else {
            previewData = nil
            return
        }
        previewData = DocumentStore.shared.loadPDF(for: document)
    }
    
    func delete(document: SavedDocument) {
        do {
            try DocumentStore.shared.delete(document: document)
        } catch {
            errorMessage = error.localizedDescription
        }
        reloadDocuments()
    }

    func delete(at offsets: IndexSet) {
        for doc in offsets.map({ documents[$0] }) {
            do {
                try DocumentStore.shared.delete(document: doc)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        reloadDocuments()
    }
}

struct DocumentListView: View {
    @StateObject private var viewModel = DocumentListViewModel()
    // Held only to hand on to the invoice editor below. A sheet does inherit the
    // environment, but InvoiceGeneratorView requires this object and would trap if
    // it ever did not — so it is passed explicitly rather than relied upon.
    @EnvironmentObject private var tabManager: TabSelectionManager
    @State private var documentToDelete: SavedDocument?
    @State private var showDeleteConfirmation = false
    @State private var searchQuery: String = ""
    
    @State private var isExporting = false
    @State private var documentToExport: PDFFile?
    @State private var invoiceEditorTarget: InvoiceEditorTarget?
    private var selectedDocument: SavedDocument? {
        guard let id = viewModel.selectedDocumentID else { return nil }
        return viewModel.allDocuments.first(where: { $0.id == id })
    }

    var body: some View {
        NavigationSplitView {
            sidebarList
        } detail: {
            detailView
        }
        .onAppear { viewModel.reloadDocuments() }
        .onChange(of: searchQuery) { viewModel.filter(with: searchQuery) }
        .alert("Delete File", isPresented: $showDeleteConfirmation, presenting: documentToDelete) { doc in
            Button("Delete", role: .destructive) { viewModel.delete(document: doc) }
        } message: { doc in
            Text(String.localizedStringWithFormat(NSLocalizedString("This file (%@) will be permanently deleted.", comment: ""), doc.fileName))
        }
        .sheet(item: $invoiceEditorTarget, onDismiss: { viewModel.reloadDocuments() }) { target in
            NavigationStack {
                InvoiceGeneratorView(
                    editingDocument: target.document,
                    initialDraft: target.draft
                )
            }
            .environmentObject(tabManager)
            .frame(minWidth: 560, idealWidth: 680, minHeight: 560, idealHeight: 760)
        }
        .fileExporter(isPresented: $isExporting, document: documentToExport, contentType: .pdf) { result in
            if case .failure(let error) = result {
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Saved Files",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    @ViewBuilder
    private var sidebarList: some View {
        VStack {
            if viewModel.documents.isEmpty && searchQuery.isEmpty {
                placeholderView(forSidebar: true)
            } else {
                List(selection: $viewModel.selectedDocumentID) {
                    ForEach(viewModel.documents) { doc in
                        NavigationLink(value: doc.id) {
                            documentRow(for: doc)
                        }
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            if viewModel.isEditable(doc) {
                                Button {
                                    openEditor(for: doc)
                                } label: {
                                    Label("Edit Invoice", systemImage: "pencil")
                                }
                            }
                            if doc.type == .invoice {
                                Button {
                                    openDuplicate(of: doc)
                                } label: {
                                    Label("Duplicate as New Invoice", systemImage: "plus.square.on.square")
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                self.documentToDelete = doc
                                self.showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: confirmDelete)
                }
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
                .searchable(text: $searchQuery, prompt: "Search by name or client")
                .navigationTitle("Saved Files")
                .overlay {
                     if viewModel.documents.isEmpty && !searchQuery.isEmpty {
                        ContentUnavailableView.search
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        if let data = viewModel.previewData, let selectedDoc = selectedDocument {
            VStack(spacing: 0) {
                #if os(macOS)
                HStack {
                    Text(selectedDoc.fileName).font(.headline).lineLimit(1)
                    Spacer()
                    if viewModel.isEditable(selectedDoc) {
                        Button {
                            openEditor(for: selectedDoc)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(AppTheme.accent)
                        .help("Reopen this invoice and change it")
                    }
                    Button {
                        self.documentToExport = PDFFile(data: data, preferredFileName: selectedDoc.fileName)
                        self.isExporting = true
                    } label: {
                        Label("Save As...", systemImage: "square.and.arrow.down")
                    }
                    .tint(AppTheme.accent)
                }
                .padding()
                .background(.bar)
                Divider()
                #endif
                
                PDFKitView(data: data)
                
                #if os(iOS)
                .navigationTitle(selectedDoc.fileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(
                            item: PDFFile(data: data, preferredFileName: selectedDoc.fileName),
                            preview: SharePreview(selectedDoc.fileName, image: Image(systemName: "doc.text.fill"))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(AppTheme.accent)
                    }
                }
                #endif
            }
        } else {
            placeholderView(forSidebar: false)
        }
    }

    private func documentRow(for doc: SavedDocument) -> some View {
        HStack(spacing: 15) {
            Image(systemName: doc.type == .invoice ? "doc.text.fill" : "doc.text.image.fill")
                .font(.title)
                .foregroundColor(AppTheme.accent)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.type == .invoice ? "Invoice \(doc.number)" : "Annual Report \(doc.number)")
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary)
                HStack(spacing: 6) {
                    Text(doc.clientName ?? "Financial Statement")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary)
                    if doc.type == .invoice {
                        if viewModel.isEditable(doc) {
                            TagLabel(text: "Editable", tint: AppTheme.accent)
                        } else {
                            TagLabel(text: "PDF only", tint: AppTheme.textSecondary)
                        }
                    }
                }
            }
            Spacer()
            Text(doc.date, style: .date)
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary)
         }
        .padding(.vertical, 8)
    }
     
    // CORRECTION: This function was missing and has been re-added.
    @ViewBuilder
    private func placeholderView(forSidebar: Bool) -> some View {
        PlaceholderView(
            systemImageName: "archivebox.fill",
            title: "No Saved Files",
            subtitle: forSidebar ? "Saved invoices and reports will appear here." : "Select a file from the list to see a preview."
        )
    }
    
    private func openEditor(for document: SavedDocument) {
        guard let draft = DocumentStore.shared.draft(for: document) else {
            viewModel.errorMessage = String(
                localized: "This invoice was saved before editing was supported, so its details are not stored. Use \"Duplicate as New Invoice\" to re-enter them once."
            )
            return
        }
        invoiceEditorTarget = InvoiceEditorTarget(document: document, draft: draft)
    }

    /// Opens a new invoice prefilled from an existing one.
    ///
    /// For an invoice with no stored source this is the migration path: whatever
    /// the archive still knows — the client and the date — is carried over, and the
    /// result is editable from then on. The original is left untouched.
    private func openDuplicate(of document: SavedDocument) {
        var draft = DocumentStore.shared.draft(for: document) ?? InvoiceDraft(
            invoiceDate: document.date,
            dueDate: InvoiceDraft.defaultDueDate(from: document.date),
            clientName: document.clientName ?? ""
        )
        // An empty number makes the editor assign the next free one.
        draft.number = ""
        invoiceEditorTarget = InvoiceEditorTarget(document: nil, draft: draft)
    }

    // CORRECTION: This function was missing and has been re-added.
    private func confirmDelete(at offsets: IndexSet) {
        if let index = offsets.first {
            self.documentToDelete = viewModel.documents[index]
            self.showDeleteConfirmation = true
        }
    }
}

// CORRECTION: This struct was missing and has been re-added.
struct PDFFile: FileDocument, Transferable {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data
    var preferredFileName: String = "Document.pdf"
    
    init(data: Data = Data(), preferredFileName: String? = nil) {
        self.data = data
        if let name = preferredFileName { self.preferredFileName = name }
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
        self.preferredFileName = configuration.file.filename ?? "Document.pdf"
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { file in file.data }
        .suggestedFileName { file in file.preferredFileName }
    }
}

/// Identifies which invoice the editor sheet should open.
struct InvoiceEditorTarget: Identifiable {
    /// `nil` when composing a new invoice (a duplicate) rather than editing one.
    let document: SavedDocument?
    let draft: InvoiceDraft

    var id: String { document?.id ?? "new:\(draft.number)" }
}

/// Small inline chip, matching the pill already used for foreign-currency amounts.
struct TagLabel: View {
    let text: LocalizedStringKey
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.18))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }
}

private extension String {
    init(localized key: String.LocalizationValue) {
        self.init(localized: key, bundle: .main)
    }
}
