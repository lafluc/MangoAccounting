//
//  ThemeSnapshotTests.swift
//  MangoAccountingTests
//
//  Renders representative UI to PNGs so the light and dark palettes can actually
//  be looked at, rather than asserted about. Set MANGO_SNAPSHOT_DIR to collect
//  them; the test is a no-op otherwise, so it costs nothing in a normal run.
//

import SwiftUI
import Testing
@testable import MangoAccounting

@Suite("Theme snapshots")
@MainActor
struct ThemeSnapshotTests {

    /// Writes into the test host's temporary directory. Harmless, and the path is
    /// printed so the images can be found and looked at.
    private var outputDirectory: URL? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mango-theme-snapshots")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        print("MANGO_SNAPSHOTS_AT \(url.path)")
        return url
    }

    private func write<V: View>(_ view: V, named name: String, scheme: ColorScheme, to directory: URL) {
        let renderer = ImageRenderer(
            content: view
                .environment(\.colorScheme, scheme)
                .frame(width: 520)
                .background(AppTheme.background)
                .environment(\.colorScheme, scheme)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            Issue.record("could not render \(name)")
            return
        }
        try? png.write(to: directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
    }

    @Test("renders the component gallery in both appearances")
    func componentGallery() {
        guard let directory = outputDirectory else { return }
        for scheme in [ColorScheme.light, .dark] {
            write(ThemeGallery(), named: "gallery", scheme: scheme, to: directory)
        }
    }

    @Test("renders an invoice page, which must stay light whatever the app does")
    func invoicePage() {
        guard let directory = outputDirectory else { return }
        let draft = InvoiceDraft(
            number: "RE-20260826",
            clientName: "Acme AG",
            clientAddress: "Bahnhofstrasse 1, 8001 Zürich",
            customMessage: "Vielen Dank für die gute Zusammenarbeit.",
            isVATExempt: true,
            lineItems: [
                InvoiceLineItem(description: "Consulting, August", amount: 4_800),
                InvoiceLineItem(description: "Travel", amount: 320.55),
                InvoiceLineItem(description: "Early-payment discount", amount: -150),
            ],
            issuer: InvoiceIssuer(
                name: "Luc Lafrenaye",
                address: "Musterweg 2, 8000 Zürich",
                uid: "CHE-123.456.789",
                iban: "CH9300762011623852957"
            )
        )
        let pages = InvoicePagination.paginate(
            draft.lineItems,
            messageLineCount: InvoicePagination.messageLineCount(for: draft.customMessage)
        )
        // Rendered under the *dark* app scheme on purpose: the page must still come
        // out black-on-white.
        for page in pages {
            let view = InvoiceView(draft: draft, page: page, locale: Locale(identifier: "de_CH"))
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent("invoice-page\(page.index + 1).png"))
            }
        }
    }

    @Test("renders a long invoice to confirm the total and QR block are not clipped")
    func longInvoicePages() {
        guard let directory = outputDirectory else { return }
        let items = (1...26).map {
            InvoiceLineItem(description: "Position \($0) — billable work", amount: Double($0) * 37.5)
        }
        let draft = InvoiceDraft(
            number: "RE-LONG",
            clientName: "Vielposten GmbH",
            clientAddress: "Industriestrasse 9, 3000 Bern",
            customMessage: "Detailaufstellung siehe unten.",
            lineItems: items,
            issuer: InvoiceIssuer(
                name: "Luc Lafrenaye",
                address: "Musterweg 2, 8000 Zürich",
                uid: "CHE-123.456.789",
                iban: "CH9300762011623852957"
            )
        )
        let pages = InvoicePagination.paginate(
            draft.lineItems,
            messageLineCount: InvoicePagination.messageLineCount(for: draft.customMessage)
        )
        for page in pages {
            let view = InvoiceView(draft: draft, page: page, locale: Locale(identifier: "de_CH"))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent("invoice-long-page\(page.index + 1)-of\(page.count).png"))
            }
        }
    }
}

/// Every themed component on one sheet, so a palette change can be judged at a
/// glance in both appearances.
private struct ThemeGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            Text("Mango Accounting").font(AppTheme.titleFont).foregroundColor(AppTheme.textPrimary)

            SectionView(title: "Cards") {
                CardView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Coffee with client")
                            .font(AppTheme.headlineFont).foregroundColor(AppTheme.textPrimary)
                        Text("Client Entertainment")
                            .font(AppTheme.bodyFont).foregroundColor(AppTheme.textSecondary)
                        HStack {
                            Text("CHF 42.50").foregroundColor(AppTheme.negative)
                            Spacer()
                            Text("CHF 1'200.00").foregroundColor(AppTheme.positive)
                        }
                        .font(AppTheme.headlineFont)
                    }
                }
            }

            SectionView(title: "Accent Bar") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Net Profit").font(AppTheme.captionFont).foregroundColor(AppTheme.textSecondary)
                    Text("CHF 18'420.15").font(AppTheme.titleFont).foregroundColor(AppTheme.textPrimary)
                }
                .accentBarCard(color: AppTheme.accentSecondary)
            }

            SectionView(title: "Title suggestions") {
                TitleSuggestionRow(
                    suggestions: [
                        TitleSuggestion(title: "Coffee with client", useCount: 12, lastUsed: .now),
                        TitleSuggestion(title: "Train ticket", useCount: 7, lastUsed: .now),
                        TitleSuggestion(title: "Coworking desk", useCount: 2, lastUsed: .now),
                        TitleSuggestion(title: "Adobe subscription", useCount: 11, lastUsed: .now),
                        TitleSuggestion(title: "Studio rent", useCount: 9, lastUsed: .now),
                        TitleSuggestion(title: "Camera insurance", useCount: 4, lastUsed: .now),
                    ],
                    onSelect: { _ in }
                )
            }

            SectionView(title: "Buttons") {
                VStack(spacing: 10) {
                    Button("Save") {}.buttonStyle(PillButtonStyle())
                    Button("Save") {}.buttonStyle(PillButtonStyle()).disabled(true)
                    Button("Delete Asset") {}.buttonStyle(PillButtonStyle(role: .destructive))
                }
            }

            SectionView(title: "Tags") {
                HStack {
                    TagLabel(text: "Editable", tint: AppTheme.accent)
                    TagLabel(text: "PDF only", tint: AppTheme.textSecondary)
                }
            }
        }
        .padding(20)
    }
}
