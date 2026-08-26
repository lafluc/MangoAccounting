//
//  MangoAccountingTests.swift
//  MangoAccountingTests
//
//  Created by Luc Lafrenaye on 12.08.2025.
//

import Foundation
import Testing
@testable import MangoAccounting

// MARK: - Archive index backwards compatibility

@Suite("SavedDocument on-disk compatibility")
struct SavedDocumentCompatibilityTests {

    /// The exact shape written by the shipped build. Decoding this unchanged is
    /// the whole backwards-compatibility guarantee for existing users' archives.
    private let legacyJSON = """
    [
      {
        "id" : "RE-20251015",
        "fileName" : "Invoice-RE-20251015.pdf",
        "date" : "2025-10-15T00:00:00Z",
        "type" : "invoice",
        "clientName" : "Acme AG"
      },
      {
        "id" : "2025",
        "fileName" : "Erfolgsrechnung-2025.pdf",
        "date" : "2025-12-31T00:00:00Z",
        "type" : "report"
      }
    ]
    """

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test("a metadata.json from the shipped build still decodes")
    func decodesLegacyIndex() throws {
        let docs = try decoder.decode([SavedDocument].self, from: Data(legacyJSON.utf8))

        #expect(docs.count == 2)
        #expect(docs[0].number == "RE-20251015")
        #expect(docs[0].fileName == "Invoice-RE-20251015.pdf")
        #expect(docs[0].type == .invoice)
        #expect(docs[0].clientName == "Acme AG")
        #expect(docs[1].number == "2025")
        #expect(docs[1].type == .report)
        #expect(docs[1].clientName == nil)
    }

    @Test("re-encoding keeps the original key so an older build could still read it")
    func reEncodesWithLegacyKey() throws {
        let docs = try decoder.decode([SavedDocument].self, from: Data(legacyJSON.utf8))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let round = try encoder.encode(docs)
        let asObject = try JSONSerialization.jsonObject(with: round) as? [[String: Any]]

        let first = try #require(asObject?.first)
        #expect(first["id"] as? String == "RE-20251015")
        #expect(first["number"] == nil, "the stored key must stay \"id\"")

        // And it survives a full round trip.
        #expect(try decoder.decode([SavedDocument].self, from: round) == docs)
    }

    @Test("an invoice and a report sharing a number no longer share an identity")
    func compositeIdentityAvoidsCollision() {
        let invoice = SavedDocument(
            number: "2025", fileName: "Invoice-2025.pdf", date: .now, type: .invoice
        )
        let report = SavedDocument(
            number: "2025", fileName: "Erfolgsrechnung-2025.pdf", date: .now, type: .report
        )

        #expect(invoice.number == report.number)
        #expect(invoice.id != report.id, "identity must distinguish the two kinds")
        #expect(Set([invoice.id, report.id]).count == 2)
    }
}

// MARK: - Invoice source round trip

@Suite("InvoiceDraft")
struct InvoiceDraftTests {

    @Test("survives a JSON round trip, including the issuer snapshot")
    func roundTrips() throws {
        let draft = InvoiceDraft(
            number: "RE-20260826",
            invoiceDate: Date(timeIntervalSince1970: 1_770_000_000),
            dueDate: Date(timeIntervalSince1970: 1_772_592_000),
            clientName: "Acme AG",
            clientAddress: "Bahnhofstrasse 1, 8001 Zürich",
            customMessage: "Danke!",
            isVATExempt: true,
            lineItems: [
                InvoiceLineItem(description: "Consulting", amount: 1200),
                InvoiceLineItem(description: "Rabatt", amount: -200),
            ],
            issuer: InvoiceIssuer(
                name: "Luc", address: "Musterweg 2, 8000 Zürich",
                uid: "CHE-123.456.789", iban: "CH9300762011623852957"
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(InvoiceDraft.self, from: try encoder.encode(draft))
        #expect(restored == draft)
        #expect(restored.issuer.iban == "CH9300762011623852957")
        #expect(restored.schemaVersion == InvoiceDraft.currentSchemaVersion)
    }

    @Test("a negative line reduces the total instead of being ignored")
    func negativeLinesCount() {
        let draft = InvoiceDraft(lineItems: [
            InvoiceLineItem(description: "Work", amount: 1000),
            InvoiceLineItem(description: "Discount", amount: -250),
        ])
        #expect(draft.total == 750)
    }

    @Test("amounts round half away from zero, as an accountant expects")
    func roundsHalfAway() {
        // The naive (x * 100).rounded() / 100 gives 1.00 here, because 1.005 is
        // held as slightly less than 1.005 in binary floating point.
        #expect(InvoiceMath.roundToCents(1.005) == 1.01)
        #expect(InvoiceMath.roundToCents(2.675) == 2.68)
        #expect(InvoiceMath.roundToCents(2.344) == 2.34)
        #expect(InvoiceMath.roundToCents(-1.005) == -1.01)
        #expect(InvoiceMath.roundToCents(0) == 0)

        #expect(InvoiceMath.fixedTwoDecimals(1.5) == "1.50")
        #expect(InvoiceMath.fixedTwoDecimals(-3.456) == "-3.46")
        #expect(InvoiceMath.fixedTwoDecimals(1.005) == "1.01")
    }

    /// The property that matters on a document handed to a client or a tax
    /// office: the column of printed amounts adds up to the printed total. That
    /// requires summing the *rounded* lines, which is why two lines of 0.005
    /// total 0.02 — each one prints as "0.01".
    @Test("the printed rows always sum to the printed total", arguments: [
        [0.005, 0.005],
        [1.005, 2.675, 3.334],
        [1000.0 / 3.0, 1000.0 / 3.0, 1000.0 / 3.0],
        [19.99, 0.01, -5.555],
        [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7],
    ])
    func printedRowsSumToPrintedTotal(amounts: [Double]) {
        let draft = InvoiceDraft(
            lineItems: amounts.map { InvoiceLineItem(description: "row", amount: $0) }
        )

        // Re-read the printed strings, exactly as the PDF renders them.
        let printedRows = amounts.map { Double(InvoiceMath.fixedTwoDecimals($0))! }
        let printedTotal = Double(InvoiceMath.fixedTwoDecimals(draft.total))!

        #expect(
            abs(printedRows.reduce(0, +) - printedTotal) < 0.000_001,
            "rows \(printedRows) print a sum that differs from the printed total \(printedTotal)"
        )
    }
}

// MARK: - Pagination

@Suite("InvoicePagination")
struct InvoicePaginationTests {

    private func items(_ count: Int) -> [InvoiceLineItem] {
        (0..<count).map { InvoiceLineItem(description: "Item \($0)", amount: Double($0)) }
    }

    @Test("a short invoice stays on one page")
    func shortInvoiceIsSinglePage() {
        let pages = InvoicePagination.paginate(items(5), messageLineCount: 1)
        #expect(pages.count == 1)
        #expect(pages[0].isFirst && pages[0].isLast)
        #expect(pages[0].items.count == 5)
    }

    @Test("an empty invoice still produces one page")
    func emptyInvoiceHasOnePage() {
        let pages = InvoicePagination.paginate([], messageLineCount: 0)
        #expect(pages.count == 1)
        #expect(pages[0].items.isEmpty)
    }

    @Test("a long invoice breaks across pages and loses nothing", arguments: [15, 24, 40, 120, 500])
    func longInvoicePaginates(count: Int) {
        let source = items(count)
        let pages = InvoicePagination.paginate(source, messageLineCount: 2)

        // Every item appears exactly once, in order.
        let flattened = pages.flatMap(\.items)
        #expect(flattened.count == count)
        #expect(flattened.map(\.description) == source.map(\.description))

        // Page numbering is coherent.
        #expect(pages.first?.isFirst == true)
        #expect(pages.last?.isLast == true)
        #expect(pages.allSatisfy { $0.count == pages.count })
        #expect(pages.map(\.index) == Array(0..<pages.count))
        #expect(pages.filter(\.isLast).count == 1)
    }

    @Test("the final page always has room for the total and the QR block")
    func finalPageReservesClosingBlock() {
        let closingCapacity = InvoicePagination.rowCapacity(
            onFirstPage: false, messageLineCount: 0, reservingClosing: true
        )
        let singleCapacity = InvoicePagination.rowCapacity(
            onFirstPage: true, messageLineCount: 2, reservingClosing: true
        )

        for count in [14, 15, 16, 30, 31, 60, 200] {
            let pages = InvoicePagination.paginate(items(count), messageLineCount: 2)
            let last = pages[pages.count - 1]
            let allowed = pages.count == 1 ? singleCapacity : closingCapacity
            #expect(
                last.items.count <= allowed,
                "last page of \(count) items carries \(last.items.count) rows, over the \(allowed) that leave room for the total"
            )
        }
    }

    @Test("message length is measured for page budgeting")
    func messageLineCounting() {
        #expect(InvoicePagination.messageLineCount(for: "") == 0)
        #expect(InvoicePagination.messageLineCount(for: "one line") == 1)
        #expect(InvoicePagination.messageLineCount(for: "a\nb\nc") == 3)
        #expect(InvoicePagination.messageLineCount(for: String(repeating: "x", count: 200)) >= 2)
    }
}

// MARK: - Filename safety

@Suite("Archive filename sanitising")
struct SanitizedFileComponentTests {

    @Test("existing well-formed names are left exactly as they are")
    func idempotentOnRealNames() {
        for name in ["Invoice-RE-20251015.pdf", "Erfolgsrechnung-2025.pdf", "metadata.json"] {
            #expect(DocumentStore.sanitizedFileComponent(name, fallback: "x") == name)
        }
    }

    @Test("path separators and traversal cannot escape the archive folder")
    func blocksTraversal() {
        let cleaned = DocumentStore.sanitizedFileComponent("../../etc/passwd", fallback: "x")
        #expect(!cleaned.contains("/"))
        #expect(!cleaned.hasPrefix("."))

        #expect(!DocumentStore.sanitizedFileComponent("a/b", fallback: "x").contains("/"))
        #expect(!DocumentStore.sanitizedFileComponent(#"a\b"#, fallback: "x").contains(#"\"#))
        #expect(!DocumentStore.sanitizedFileComponent("a:b", fallback: "x").contains(":"))
    }

    @Test("empty or unusable input falls back rather than producing a bad path")
    func fallsBack() {
        #expect(DocumentStore.sanitizedFileComponent("", fallback: "unnumbered") == "unnumbered")
        #expect(DocumentStore.sanitizedFileComponent("   ", fallback: "unnumbered") == "unnumbered")
        #expect(DocumentStore.sanitizedFileComponent("...", fallback: "unnumbered") == "unnumbered")
    }

    @Test("names are capped so the filesystem never rejects them")
    func capsLength() {
        let long = String(repeating: "n", count: 400)
        #expect(DocumentStore.sanitizedFileComponent(long, fallback: "x").count <= 100)
    }

    @Test("invoice filenames match the shipped naming convention")
    func invoiceFileNaming() {
        #expect(DocumentStore.invoiceFileName(for: "RE-20251015") == "Invoice-RE-20251015.pdf")
        #expect(DocumentStore.invoiceFileName(for: "") == "Invoice-unnumbered.pdf")
        #expect(!DocumentStore.invoiceFileName(for: "a/b").contains("/"))
    }
}

// MARK: - Tab order

@Suite("Tab order")
struct TabOrderTests {

    @Test("no saved order gives every tab")
    func emptyGivesAll() {
        #expect(TabItem.decodeOrder(from: Data()) == TabItem.allCases)
    }

    @Test("a tab added after the order was saved is appended, not lost")
    func appendsNewTabs() throws {
        // What a user's UserDefaults held before the Assets tab shipped.
        let legacy = try JSONEncoder().encode(
            ["Dashboard", "Transactions", "Annual Report", "New Invoice", "Saved", "Settings"]
        )
        let order = TabItem.decodeOrder(from: legacy)

        #expect(order.contains(.assets), "the Assets tab must come back for existing users")
        #expect(Set(order) == Set(TabItem.allCases))
        // The user's own ordering is preserved ahead of the additions.
        #expect(Array(order.prefix(2)) == [.dashboard, .transactions])
    }

    @Test("unknown entries are dropped instead of failing the whole decode")
    func dropsUnknown() throws {
        let data = try JSONEncoder().encode(["Settings", "SomethingRemoved", "Dashboard"])
        let order = TabItem.decodeOrder(from: data)

        #expect(Array(order.prefix(2)) == [.settings, .dashboard])
        #expect(Set(order) == Set(TabItem.allCases))
    }

    @Test("duplicates in a saved order are collapsed")
    func collapsesDuplicates() throws {
        let data = try JSONEncoder().encode(["Dashboard", "Dashboard", "Settings"])
        let order = TabItem.decodeOrder(from: data)
        #expect(order.count == TabItem.allCases.count)
        #expect(Set(order).count == order.count)
    }

    @Test("encoding writes the same shape the app has always written")
    func encodesLegacyShape() throws {
        let data = try #require(TabItem.encodeOrder([.settings, .dashboard]))
        let raw = try JSONDecoder().decode([String].self, from: data)
        #expect(raw == ["Settings", "Dashboard"])
    }
}
