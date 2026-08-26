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

    private init() {}

    // MARK: - Locations

    /// Resolved on demand rather than cached at init, so a transient failure at
    /// launch does not leave the store permanently broken for the session.
    private func directoryURL() throws -> URL {
        do {
            let documents = try FileManager.default.url(
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

        index.removeAll { $0.id == document.id && $0.type == document.type }
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

        index.removeAll { $0.id == document.id && $0.type == document.type }
        try writeIndexLocked(index)
    }
}
