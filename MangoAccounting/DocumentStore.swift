// DocumentStore.swift

import Foundation

// A single, unified model for any saved document's metadata
struct SavedDocument: Identifiable, Codable, Hashable {
    enum DocumentType: String, Codable {
        case invoice, report
    }

    /// The document's business key: an invoice number, or a report year.
    var number: String
    var fileName: String
    var date: Date
    var type: DocumentType
    var clientName: String? // Optional, only for invoices

    /// Identity that is unique across both kinds.
    ///
    /// `number` alone is not: an invoice numbered "2025" and the 2025 annual
    /// report shared it, which gave `ForEach` duplicate ids and made the sidebar
    /// preview or delete the wrong row.
    var id: String { "\(type.rawValue):\(number)" }

    /// The stored keys are unchanged — `number` is still written as "id" — so
    /// every metadata.json written by an earlier build decodes as-is.
    private enum CodingKeys: String, CodingKey {
        case number = "id"
        case fileName
        case date
        case type
        case clientName
    }

    init(number: String, fileName: String, date: Date, type: DocumentType, clientName: String? = nil) {
        self.number = number
        self.fileName = fileName
        self.date = date
        self.type = type
        self.clientName = clientName
    }
}

enum DocumentStoreError: LocalizedError {
    /// The archive folder could not be reached or created.
    case directoryUnavailable(underlying: Error)
    /// The index file exists but could not be read or decoded. Treated as fatal
    /// for writes, deliberately — see `loadIndexLocked()`.
    case indexUnreadable(underlying: Error)
    /// A PDF or the index could not be written.
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable(let underlying):
            return "The folder for saved files could not be opened: \(underlying.localizedDescription)"
        case .indexUnreadable(let underlying):
            return "The list of saved files could not be read, so nothing was changed: \(underlying.localizedDescription)"
        case .writeFailed(let underlying):
            return "The file could not be saved: \(underlying.localizedDescription)"
        }
    }
}

/// Manages saving, loading and deleting archived PDFs plus their index.
///
/// All mutations take a process-wide lock, because the index is maintained by a
/// read-modify-write cycle and several views trigger saves from the main thread.
final class DocumentStore {
    static let shared = DocumentStore()

    private let lock = NSLock()
    private let directoryName = "SavedDocuments"
    private let indexFileName = "metadata.json"

    /// Overrides the parent of the archive folder. Only used by tests, so they can
    /// exercise the real read/write paths without touching the user's documents.
    private let rootOverride: URL?

    private init() {
        self.rootOverride = nil
    }

    init(rootDirectory: URL) {
        self.rootOverride = rootDirectory
    }

    // MARK: - Locations

    /// Resolved on demand rather than cached at init, so a transient failure at
    /// launch does not leave the store permanently broken for the session.
    private func directoryURL() throws -> URL {
        do {
            let documents = try rootOverride ?? FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let directory = documents.appendingPathComponent(directoryName)
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return directory
        } catch {
            throw DocumentStoreError.directoryUnavailable(underlying: error)
        }
    }

    private func indexURL() throws -> URL {
        try directoryURL().appendingPathComponent(indexFileName)
    }

    private func fileURL(for document: SavedDocument) throws -> URL {
        // A document's stored fileName is built from free text (an invoice
        // number), so it is re-sanitised on every use rather than trusted.
        let safeName = Self.sanitizedFileComponent(document.fileName, fallback: "document.pdf")
        return try directoryURL().appendingPathComponent(safeName)
    }

    /// Makes a string safe to use as one filename component.
    ///
    /// Invoice numbers are free text. Interpolated straight into a path, a "/"
    /// produces an unwritable name and "../" writes outside the archive folder.
    static func sanitizedFileComponent(_ raw: String, fallback: String) -> String {
        let illegal = CharacterSet(charactersIn: #"/\:*?"<>|"#)
            .union(.controlCharacters)
            .union(.newlines)
        var cleaned = raw.components(separatedBy: illegal).joined(separator: "-")
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        // A leading dot would hide the file, and "." / ".." are path traversal.
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.count > 100 { cleaned = String(cleaned.prefix(100)) }
        return cleaned.isEmpty ? fallback : cleaned
    }

    // MARK: - Reading

    /// The archived documents, newest first. Returns an empty list if the archive
    /// cannot be read — suitable for display, but never for a read-modify-write.
    func listDocuments() -> [SavedDocument] {
        lock.lock()
        defer { lock.unlock() }
        return (try? loadIndexLocked()) ?? []
    }

    /// The archived documents, propagating any failure. Use this wherever the
    /// result feeds a decision or a write.
    func documents() throws -> [SavedDocument] {
        lock.lock()
        defer { lock.unlock() }
        return try loadIndexLocked()
    }

    /// Reads the index.
    ///
    /// A missing or empty file means an empty archive. A file that exists but
    /// cannot be decoded is an *error*, never an empty archive: the previous
    /// behaviour returned `[]` there, and because every write is a
    /// read-modify-write, the next save then replaced the entire archive index
    /// with a single row and orphaned every earlier PDF.
    private func loadIndexLocked() throws -> [SavedDocument] {
        let url = try indexURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DocumentStoreError.indexUnreadable(underlying: error)
        }
        guard !data.isEmpty else { return [] }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SavedDocument].self, from: data)
        } catch {
            throw DocumentStoreError.indexUnreadable(underlying: error)
        }
    }

    private func writeIndexLocked(_ documents: [SavedDocument]) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(documents)
            try data.write(to: try indexURL(), options: .atomic)
        } catch let error as DocumentStoreError {
            throw error
        } catch {
            throw DocumentStoreError.writeFailed(underlying: error)
        }
    }

    func loadPDF(for document: SavedDocument) -> Data? {
        guard let url = try? fileURL(for: document) else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - Writing

    /// Archives a PDF and records it in the index.
    ///
    /// The index is read *first*, so a corrupt index aborts before any file is
    /// written, and the caller is told rather than shown a success message.
    func save(document: SavedDocument, data: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        var index = try loadIndexLocked()
        let url = try fileURL(for: document)

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw DocumentStoreError.writeFailed(underlying: error)
        }

        index.removeAll { $0.id == document.id }
        index.append(document)
        index.sort { $0.date > $1.date }
        try writeIndexLocked(index)
    }

    func delete(document: SavedDocument) throws {
        lock.lock()
        defer { lock.unlock() }

        var index = try loadIndexLocked()
        let url = try fileURL(for: document)

        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw DocumentStoreError.writeFailed(underlying: error)
            }
        }
        removeDraftFileLocked(for: document)

        index.removeAll { $0.id == document.id }
        try writeIndexLocked(index)
    }
}

// MARK: - Editable invoice sources

extension DocumentStore {

    /// Suffix for the sidecar that holds an invoice's editable source, written
    /// beside its PDF. Its *presence* is what makes an invoice editable:
    /// documents archived by earlier versions simply have no sidecar and stay
    /// view/export-only. Nothing about them is read or rewritten.
    private static let draftSuffix = ".invoice.json"

    private func draftURL(for document: SavedDocument) throws -> URL {
        let safeName = Self.sanitizedFileComponent(document.fileName, fallback: "document.pdf")
        let stem = (safeName as NSString).deletingPathExtension
        return try directoryURL().appendingPathComponent(stem + Self.draftSuffix)
    }

    /// The editable source for a document, or `nil` when there is none — which is
    /// the normal case for anything archived before this feature existed.
    func draft(for document: SavedDocument) -> InvoiceDraft? {
        guard document.type == .invoice,
              let url = try? draftURL(for: document),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InvoiceDraft.self, from: data)
    }

    /// Ids of archived documents that have an editable source, so a list can be
    /// rendered without a filesystem check per row.
    func idsWithDrafts() -> Set<String> {
        guard let directory = try? directoryURL(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }

        let stems = Set(
            names
                .filter { $0.hasSuffix(Self.draftSuffix) }
                .map { String($0.dropLast(Self.draftSuffix.count)) }
        )

        return Set(
            listDocuments()
                .filter { document in
                    let safeName = Self.sanitizedFileComponent(document.fileName, fallback: "document.pdf")
                    return stems.contains((safeName as NSString).deletingPathExtension)
                }
                .map(\.id)
        )
    }

    /// Removes the archive folder entirely. Test-only; guarded so it can never run
    /// against the user's real documents directory.
    func removeAllForTesting() throws {
        guard rootOverride != nil else {
            assertionFailure("removeAllForTesting() is only valid on an injected store")
            return
        }
        let directory = try directoryURL()
        try? FileManager.default.removeItem(at: directory)
    }

    /// The archive filename for an invoice number.
    static func invoiceFileName(for number: String) -> String {
        "Invoice-\(sanitizedFileComponent(number, fallback: "unnumbered")).pdf"
    }

    /// Writes an invoice's PDF and its editable source together.
    ///
    /// If `replacing` is given and its number changed, the old PDF and sidecar are
    /// removed so an edit renames rather than leaving a duplicate behind.
    @discardableResult
    func save(invoice draft: InvoiceDraft, pdf: Data, replacing previous: SavedDocument?) throws -> SavedDocument {
        let document = SavedDocument(
            number: draft.number,
            fileName: Self.invoiceFileName(for: draft.number),
            date: draft.invoiceDate,
            type: .invoice,
            clientName: draft.clientName
        )

        lock.lock()
        defer { lock.unlock() }

        var index = try loadIndexLocked()

        let pdfURL = try fileURL(for: document)
        do {
            try pdf.write(to: pdfURL, options: .atomic)
        } catch {
            throw DocumentStoreError.writeFailed(underlying: error)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(draft)
            try data.write(to: try draftURL(for: document), options: .atomic)
        } catch let error as DocumentStoreError {
            throw error
        } catch {
            throw DocumentStoreError.writeFailed(underlying: error)
        }

        // An edit that changed the invoice number leaves files under the old name.
        if let previous, previous.id != document.id {
            if let oldPDF = try? fileURL(for: previous),
               FileManager.default.fileExists(atPath: oldPDF.path) {
                try? FileManager.default.removeItem(at: oldPDF)
            }
            removeDraftFileLocked(for: previous)
            index.removeAll { $0.id == previous.id }
        }

        index.removeAll { $0.id == document.id }
        index.append(document)
        index.sort { $0.date > $1.date }
        try writeIndexLocked(index)

        return document
    }

    fileprivate func removeDraftFileLocked(for document: SavedDocument) {
        guard let url = try? draftURL(for: document),
              FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
