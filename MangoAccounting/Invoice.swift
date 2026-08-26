// Invoice.swift
//
// The editable source of an invoice.
//
// Before this existed, an invoice was only ever a rendered PDF plus five fields
// in the archive index: the line items, client address, due date, message and VAT
// flag lived in view state and were discarded the moment the form reset. Saving
// this alongside the PDF is what makes an invoice re-openable and re-exportable.

import Foundation

/// One billable line on an invoice.
struct InvoiceLineItem: Identifiable, Hashable, Codable {
    var id: UUID
    var description: String
    var amount: Double

    init(id: UUID = UUID(), description: String = "", amount: Double = 0) {
        self.id = id
        self.description = description
        self.amount = amount
    }
}

/// The issuer's details as they stood when the invoice was written.
///
/// Snapshotted per invoice instead of read from `UserSettings` at render time.
/// Without this, re-exporting last year's invoice after changing your IBAN or
/// business address would quietly produce a document you never sent.
struct InvoiceIssuer: Hashable, Codable {
    var name: String
    var address: String
    var uid: String
    var iban: String

    init(name: String = "", address: String = "", uid: String = "", iban: String = "") {
        self.name = name
        self.address = address
        self.uid = uid
        self.iban = iban
    }

    init(settings: UserSettings) {
        self.init(
            name: settings.name,
            address: settings.address,
            uid: settings.uid,
            iban: settings.iban
        )
    }
}

/// Everything needed to re-render an invoice exactly as it was saved.
struct InvoiceDraft: Hashable, Codable {

    /// Bumped only if the shape changes in a way an older build could not read.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var number: String
    var invoiceDate: Date
    var dueDate: Date
    var clientName: String
    var clientAddress: String
    var customMessage: String
    var isVATExempt: Bool
    var lineItems: [InvoiceLineItem]
    var issuer: InvoiceIssuer

    init(
        schemaVersion: Int = InvoiceDraft.currentSchemaVersion,
        number: String = "",
        invoiceDate: Date = .now,
        dueDate: Date = InvoiceDraft.defaultDueDate(from: .now),
        clientName: String = "",
        clientAddress: String = "",
        customMessage: String = "",
        isVATExempt: Bool = false,
        lineItems: [InvoiceLineItem] = [InvoiceLineItem()],
        issuer: InvoiceIssuer = InvoiceIssuer()
    ) {
        self.schemaVersion = schemaVersion
        self.number = number
        self.invoiceDate = invoiceDate
        self.dueDate = dueDate
        self.clientName = clientName
        self.clientAddress = clientAddress
        self.customMessage = customMessage
        self.isVATExempt = isVATExempt
        self.lineItems = lineItems
        self.issuer = issuer
    }

    /// Net payable.
    ///
    /// Negative lines are included, so a discount row actually reduces the
    /// total. Previously they were rendered on the PDF but excluded from the sum,
    /// which meant the invoice did not add up.
    var total: Double {
        // Each line is summed *after* rounding, which is what makes the printed
        // column add up to the printed total rather than differing by a rappen.
        InvoiceMath.roundToCents(
            lineItems.reduce(0) { $0 + InvoiceMath.roundToCents($1.amount) }
        )
    }

    /// Standard payment window used for a new invoice.
    static let defaultPaymentTermDays = 30

    static func defaultDueDate(from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: defaultPaymentTermDays, to: date) ?? date
    }
}

enum InvoiceMath {
    /// Rounds an amount to whole rappen, half away from zero.
    ///
    /// `(value * 100).rounded() / 100` is not enough: 1.005 is held as slightly
    /// *less* than 1.005 in binary floating point, so that expression yields 1.00
    /// where an accountant expects 1.01. Going through `Decimal` — seeded from the
    /// value's decimal text so the binary approximation is discarded — rounds the
    /// number the user actually typed.
    static func roundToCents(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let text = String(format: "%.10f", value)
        var source = Decimal(string: text) ?? Decimal(value)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .plain)
        return NSDecimalNumber(decimal: rounded).doubleValue
    }

    /// Formats an amount the way the PDF prints it: two decimals, always a dot,
    /// independent of the reader's locale, because the Swiss QR payload beside it
    /// is specified that way.
    static func fixedTwoDecimals(_ value: Double) -> String {
        String(format: "%.2f", roundToCents(value))
    }
}
