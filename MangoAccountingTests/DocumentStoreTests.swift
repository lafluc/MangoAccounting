//
//  DocumentStoreTests.swift
//  MangoAccountingTests
//
//  End-to-end coverage of the archive: the real read/write paths, against a
//  temporary directory rather than the user's documents folder.
//

import Foundation
import Testing
@testable import MangoAccounting

@Suite("DocumentStore archive", .serialized)
struct DocumentStoreTests {

    /// Runs a block against a fresh, isolated archive.
    private func withStore(_ body: (DocumentStore, URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MangoAccountingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try body(DocumentStore(rootDirectory: root), root)
    }

    private func sampleDraft(number: String = "RE-20260826") -> InvoiceDraft {
        // Whole-second timestamps: the sidecar encodes dates as ISO 8601, which
        // carries no fractional seconds, so a `.now` here would round-trip to a
        // value that differs in the sub-second digits and defeat an equality check.
        InvoiceDraft(
            number: number,
            invoiceDate: Date(timeIntervalSince1970: 1_770_000_000),
            dueDate: Date(timeIntervalSince1970: 1_772_592_000),
            clientName: "Acme AG",
            clientAddress: "Bahnhofstrasse 1, 8001 Zürich",
            customMessage: "Danke!",
            lineItems: [
                InvoiceLineItem(description: "Consulting", amount: 1200),
                InvoiceLineItem(description: "Rabatt", amount: -200),
            ],
            issuer: InvoiceIssuer(
                name: "Luc", address: "Musterweg 2, 8000 Zürich",
                uid: "CHE-123.456.789", iban: "CH9300762011623852957"
            )
        )
    }

    @Test("an empty archive reads as empty rather than failing")
    func emptyArchive() throws {
        try withStore { store, _ in
            #expect(store.listDocuments().isEmpty)
            try #expect(store.documents().isEmpty)
            #expect(store.idsWithDrafts().isEmpty)
        }
    }

    @Test("saving an invoice writes the PDF and its editable source together")
    func savesInvoiceWithDraft() throws {
        try withStore { store, root in
            let draft = sampleDraft()
            let pdf = Data("%PDF-1.4 fake".utf8)

            let document = try store.save(invoice: draft, pdf: pdf, replacing: nil)

            #expect(document.number == "RE-20260826")
            #expect(document.fileName == "Invoice-RE-20260826.pdf")
            #expect(document.clientName == "Acme AG")

            let archive = root.appendingPathComponent("SavedDocuments")
            let names = try FileManager.default.contentsOfDirectory(atPath: archive.path)
            #expect(names.contains("Invoice-RE-20260826.pdf"))
            #expect(names.contains("Invoice-RE-20260826.invoice.json"))
            #expect(names.contains("metadata.json"))

            #expect(store.loadPDF(for: document) == pdf)
            #expect(store.idsWithDrafts() == [document.id])

            let restored = try #require(store.draft(for: document))
            #expect(restored == draft)
            #expect(restored.total == 1000)
        }
    }

    @Test("reopening, changing and re-saving keeps one document, not two")
    func editInPlace() throws {
        try withStore { store, _ in
            let original = try store.save(
                invoice: sampleDraft(), pdf: Data("a".utf8), replacing: nil
            )

            var edited = try #require(store.draft(for: original))
            edited.lineItems.append(InvoiceLineItem(description: "Extra", amount: 50))
            edited.clientName = "Acme Holding AG"

            let saved = try store.save(invoice: edited, pdf: Data("b".utf8), replacing: original)

            try #expect(store.documents().count == 1)
            #expect(saved.id == original.id)
            #expect(saved.clientName == "Acme Holding AG")
            #expect(store.loadPDF(for: saved) == Data("b".utf8))
            #expect(store.draft(for: saved)?.total == 1050)
        }
    }

    @Test("renumbering an invoice renames it instead of leaving a duplicate")
    func renumberRemovesOldFiles() throws {
        try withStore { store, root in
            let original = try store.save(
                invoice: sampleDraft(number: "RE-1"), pdf: Data("a".utf8), replacing: nil
            )

            var renumbered = try #require(store.draft(for: original))
            renumbered.number = "RE-2"
            let saved = try store.save(invoice: renumbered, pdf: Data("b".utf8), replacing: original)

            try #expect(store.documents().count == 1)
            #expect(saved.number == "RE-2")

            let names = Set(try FileManager.default.contentsOfDirectory(
                atPath: root.appendingPathComponent("SavedDocuments").path
            ))
            #expect(names.contains("Invoice-RE-2.pdf"))
            #expect(names.contains("Invoice-RE-2.invoice.json"))
            #expect(!names.contains("Invoice-RE-1.pdf"), "the old PDF must not linger")
            #expect(!names.contains("Invoice-RE-1.invoice.json"))
        }
    }

    @Test("deleting an invoice removes its editable source too")
    func deleteRemovesDraft() throws {
        try withStore { store, root in
            let document = try store.save(
                invoice: sampleDraft(), pdf: Data("a".utf8), replacing: nil
            )
            try store.delete(document: document)

            try #expect(store.documents().isEmpty)
            let names = try FileManager.default.contentsOfDirectory(
                atPath: root.appendingPathComponent("SavedDocuments").path
            )
            #expect(!names.contains { $0.hasSuffix(".pdf") })
            #expect(!names.contains { $0.hasSuffix(".invoice.json") })
        }
    }

    /// The core backwards-compatibility promise: an archive written by the shipped
    /// build keeps working, is *not* reported as editable, and is left untouched.
    @Test("a pre-existing invoice stays readable, read-only and unmodified")
    func legacyDocumentsAreUntouched() throws {
        try withStore { store, root in
            let archive = root.appendingPathComponent("SavedDocuments")
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)

            let legacyPDF = Data("%PDF-1.4 shipped-by-old-build".utf8)
            try legacyPDF.write(to: archive.appendingPathComponent("Invoice-RE-20251015.pdf"))
            try Data("""
            [{"id":"RE-20251015","fileName":"Invoice-RE-20251015.pdf",
              "date":"2025-10-15T00:00:00Z","type":"invoice","clientName":"Old Client"}]
            """.utf8).write(to: archive.appendingPathComponent("metadata.json"))

            let legacy = try #require(try store.documents().first)
            #expect(legacy.number == "RE-20251015")
            #expect(store.loadPDF(for: legacy) == legacyPDF)
            #expect(store.draft(for: legacy) == nil, "there is no source to recover")
            #expect(store.idsWithDrafts().isEmpty, "it must not be offered as editable")

            // Saving a brand-new invoice must not disturb it.
            _ = try store.save(invoice: sampleDraft(number: "RE-NEW"), pdf: Data("x".utf8), replacing: nil)

            try #expect(store.documents().count == 2)
            #expect(store.loadPDF(for: legacy) == legacyPDF, "the old PDF must be byte-identical")
            #expect(store.idsWithDrafts() == ["invoice:RE-NEW"], "only the new one is editable")
        }
    }

    @Test("a corrupt index aborts a write instead of silently replacing the archive")
    func corruptIndexAbortsWrite() throws {
        try withStore { store, root in
            // Two real invoices, then a damaged index.
            _ = try store.save(invoice: sampleDraft(number: "RE-1"), pdf: Data("a".utf8), replacing: nil)
            _ = try store.save(invoice: sampleDraft(number: "RE-2"), pdf: Data("b".utf8), replacing: nil)

            let indexURL = root
                .appendingPathComponent("SavedDocuments")
                .appendingPathComponent("metadata.json")
            try Data("{ this is not the index }".utf8).write(to: indexURL)

            // The old behaviour returned [] here and the next save replaced the
            // whole index with a single row, orphaning both invoices.
            #expect(throws: DocumentStoreError.self) {
                _ = try store.save(invoice: sampleDraft(number: "RE-3"), pdf: Data("c".utf8), replacing: nil)
            }
            #expect(throws: DocumentStoreError.self) { try store.documents() }

            // The damaged index is left exactly as found, so it can be repaired.
            try #expect(Data(contentsOf: indexURL) == Data("{ this is not the index }".utf8))
        }
    }

    @Test("an invoice and a report sharing a number both survive in the archive")
    func invoiceAndReportCoexist() throws {
        try withStore { store, _ in
            try store.save(
                document: SavedDocument(
                    number: "2025", fileName: "Erfolgsrechnung-2025.pdf",
                    date: .now, type: .report
                ),
                data: Data("report".utf8)
            )
            _ = try store.save(
                invoice: sampleDraft(number: "2025"), pdf: Data("invoice".utf8), replacing: nil
            )

            let documents = try store.documents()
            #expect(documents.count == 2, "the report must not be overwritten by the invoice")
            #expect(Set(documents.map(\.type)) == [.invoice, .report])
        }
    }

    @Test("an invoice number containing a path separator cannot escape the folder")
    func hostileInvoiceNumber() throws {
        try withStore { store, root in
            let document = try store.save(
                invoice: sampleDraft(number: "../../escaped"), pdf: Data("x".utf8), replacing: nil
            )

            let archive = root.appendingPathComponent("SavedDocuments")
            let names = try FileManager.default.contentsOfDirectory(atPath: archive.path)
            #expect(names.contains(document.fileName))
            #expect(!document.fileName.contains("/"))
            // Nothing was written outside the archive folder.
            let parentNames = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(parentNames == ["SavedDocuments"])
        }
    }
}
