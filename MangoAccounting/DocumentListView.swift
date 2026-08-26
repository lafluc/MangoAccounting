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
    var allDocuments: [SavedDocument] = []
    
    func reloadDocuments() {
        let all = DocumentStore.shared.listDocuments()
        self.allDocuments = all
        self.documents = all
        
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
    
    func updatePreview() {
        guard let id = selectedDocumentID,
           let document = allDocuments.first(where: { $0.id == id }) else {
            previewData = nil
            return
        }
        previewData = DocumentStore.shared.loadPDF(for: document)
    }
    
    func delete(document: SavedDocument) {
        DocumentStore.shared.delete(document: document)
        reloadDocuments()
    }
    
    func delete(at offsets: IndexSet) {
        offsets.map { documents[$0] }.forEach { doc in
            DocumentStore.shared.delete(document: doc)
        }
        reloadDocuments()
    }
}

struct DocumentListView: View {
    @StateObject private var viewModel = DocumentListViewModel()
    @State private var documentToDelete: SavedDocument?
    @State private var showDeleteConfirmation = false
    @State private var searchQuery: String = ""
    
    @State private var isExporting = false
    @State private var documentToExport: PDFFile?
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
        .fileExporter(isPresented: $isExporting, document: documentToExport, contentType: .pdf) { result in
            // Handle result if needed
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
                Text(doc.type == .invoice ? "Invoice \(doc.id)" : "Annual Report \(doc.id)")
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary)
                Text(doc.clientName ?? "Financial Statement")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary)
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
