// InvoicePagination.swift
//
// Decides where an invoice breaks across pages.
//
// The renderer used to emit exactly one PDF page into a fixed A4 frame, so once
// an invoice had roughly fifteen lines the total and the payment QR code were
// pushed off the sheet with no warning. Editable invoices grow over time, so the
// break points have to be computed.

import CoreGraphics
import Foundation

/// One page of a rendered invoice.
struct InvoicePage: Identifiable {
    let index: Int
    let count: Int
    let items: [InvoiceLineItem]

    var id: Int { index }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == count - 1 }
}

enum InvoicePagination {

    /// A4 at 72 points per inch, matching the media box the PDF context is given.
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 40

    // Heights of the blocks that compete for vertical space, taken from the
    // rendered layout in InvoiceView. They are used only to choose break points;
    // the renderer lays itself out independently, so an imprecise estimate costs
    // some whitespace rather than a clipped page.
    private static let rowHeight: CGFloat = 24
    private static let tableHeaderHeight: CGFloat = 44
    private static let addressBlockHeight: CGFloat = 120
    private static let titleBlockHeight: CGFloat = 116
    private static let messageLineHeight: CGFloat = 16
    private static let totalsBlockHeight: CGFloat = 64
    private static let qrBlockHeight: CGFloat = 150
    private static let footerHeight: CGFloat = 26

    /// How many line-item rows fit on a page.
    ///
    /// - Parameter reservingClosing: whether the page must also hold the total and
    ///   the QR block, which only the final page does.
    static func rowCapacity(onFirstPage: Bool, messageLineCount: Int, reservingClosing: Bool) -> Int {
        var available = pageSize.height - (margin * 2) - footerHeight - tableHeaderHeight
        if onFirstPage {
            available -= addressBlockHeight + titleBlockHeight
            available -= CGFloat(messageLineCount) * messageLineHeight
        }
        if reservingClosing {
            available -= totalsBlockHeight + qrBlockHeight
        }
        return max(0, Int(available / rowHeight))
    }

    /// Splits line items into pages. Always returns at least one page.
    ///
    /// Capacity is recomputed per page, because the first page holds far fewer
    /// rows than a continuation page (it carries the address and title blocks),
    /// and the *final* page — whichever that turns out to be — has to reserve room
    /// for the total and the QR block as well.
    static func paginate(_ items: [InvoiceLineItem], messageLineCount: Int) -> [InvoicePage] {
        var chunks: [[InvoiceLineItem]] = []
        var remaining = items[...]
        var isFirst = true

        while true {
            let messageLines = isFirst ? messageLineCount : 0
            let closingCapacity = rowCapacity(
                onFirstPage: isFirst, messageLineCount: messageLines, reservingClosing: true
            )

            // Everything left fits together with the total and the QR block, so
            // this is the final page.
            if remaining.count <= closingCapacity {
                chunks.append(Array(remaining))
                break
            }

            // `max(1, …)` guarantees progress even if the estimates ever exceed a page.
            let fullCapacity = max(1, rowCapacity(
                onFirstPage: isFirst, messageLineCount: messageLines, reservingClosing: false
            ))
            let nextClosingCapacity = rowCapacity(
                onFirstPage: false, messageLineCount: 0, reservingClosing: true
            )

            let take: Int
            if remaining.count <= fullCapacity && nextClosingCapacity >= 1 {
                // The rows all fit on this page but the closing block does not.
                // Move the minimum across rather than giving the total a bare page.
                take = max(1, remaining.count - nextClosingCapacity)
            } else {
                take = fullCapacity
            }

            chunks.append(Array(remaining.prefix(take)))
            remaining = remaining.dropFirst(take)
            isFirst = false

            if remaining.isEmpty {
                // Only reachable when a continuation page cannot hold the closing
                // block at all; give it a page of its own.
                chunks.append([])
                break
            }
        }

        return chunks.enumerated().map {
            InvoicePage(index: $0.offset, count: chunks.count, items: $0.element)
        }
    }

    /// Rough line count for the free-text message, used when budgeting page one.
    static func messageLineCount(for message: String, charactersPerLine: Int = 95) -> Int {
        guard !message.isEmpty else { return 0 }
        return message
            .components(separatedBy: .newlines)
            .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / Double(charactersPerLine)))) }
    }
}
