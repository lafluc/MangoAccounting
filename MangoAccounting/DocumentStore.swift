// DocumentStore.swift

import Foundation

// A single, unified model for any saved document's metadata
struct SavedDocument: Identifiable, Codable, Hashable {
    enum DocumentType: String, Codable {
        case invoice, report
    }
    
    var id: String // Invoice number or Report year
    var fileName: String
    var date: Date
    var type: DocumentType
    var clientName: String? // Optional, only for invoices
}

// A single class to manage saving, loading, and deleting all PDFs
class DocumentStore {
    static let shared = DocumentStore()
    
    private let directoryURL: URL
    private let metadataURL: URL
    
    private init() {
        var tempDir: URL
        var tempMeta: URL
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            tempDir = documents.appendingPathComponent("SavedDocuments")
            tempMeta = tempDir.appendingPathComponent("metadata.json")
            
            if !FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            print("CRITICAL ERROR: Could not set up DocumentStore: \(error)")
            tempDir = URL(fileURLWithPath: "")
            tempMeta = URL(fileURLWithPath: "")
        }
        self.directoryURL = tempDir
        self.metadataURL = tempMeta
    }
    
    func listDocuments() -> [SavedDocument] {
        guard let data = try? Data(contentsOf: metadataURL) else { return [] }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SavedDocument].self, from: data)
        } catch {
            print("Failed to decode document metadata: \(error)")
            return []
        }
    }
    
    private func saveMetadata(_ documents: [SavedDocument]) {
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(documents)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            print("Failed to save metadata: \(error)")
        }
    }
    
    func save(document: SavedDocument, data: Data) {
        let fileURL = directoryURL.appendingPathComponent(document.fileName)
        do {
            try data.write(to: fileURL)
            var allDocs = listDocuments()
            allDocs.removeAll { $0.id == document.id && $0.type == document.type }
            allDocs.append(document)
            allDocs.sort { $0.date > $1.date }
            saveMetadata(allDocs)
        } catch {
            print("Failed to save PDF file: \(error)")
        }
    }
    
    func loadPDF(for document: SavedDocument) -> Data? {
        let fileURL = directoryURL.appendingPathComponent(document.fileName)
        return try? Data(contentsOf: fileURL)
    }
    
    func delete(document: SavedDocument) {
        let fileURL = directoryURL.appendingPathComponent(document.fileName)
        try? FileManager.default.removeItem(at: fileURL)
        var allDocs = listDocuments()
        allDocs.removeAll { $0.id == document.id && $0.type == document.type }
        saveMetadata(allDocs)
    }
}
