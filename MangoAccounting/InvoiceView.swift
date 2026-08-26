//
//  InvoiceView.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 17.08.2025.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

/// One rendered page of an invoice.
///
/// Reads the issuer from the draft's snapshot rather than from live settings, so
/// re-exporting an old invoice reproduces the document that was actually sent.
struct InvoiceView: View {
    let draft: InvoiceDraft
    let page: InvoicePage
    let locale: Locale

    private var issuer: InvoiceIssuer { draft.issuer }
    private var a4Size: CGSize { InvoicePagination.pageSize }
    private var margin: CGFloat { InvoicePagination.margin }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = locale
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if page.isFirst {
                headerSection

                Spacer().frame(height: 60)

                titleSection

                if !draft.customMessage.isEmpty {
                    Text(draft.customMessage)
                        .font(.callout)
                        .padding(.top, 25)
                }
            } else {
                continuationHeader
            }

            Spacer(minLength: 20)

            lineItemsSection

            if page.isLast {
                totalAndVATSection
                qrCodeSection.frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }

            if page.count > 1 {
                pageFooter
            }
        }
        .padding(margin)
        .frame(width: a4Size.width, height: a4Size.height)
        .background(Color.white)
        // An explicit black, not .primary: the app runs in dark mode, and
        // .primary resolved against that scheme rendered white text onto the
        // white page.
        .foregroundColor(.black)
        .font(.system(size: 11, design: .default))
        // The renderer does not inherit the app's environment, so the page is
        // pinned to light regardless of the user's appearance setting.
        .environment(\.colorScheme, .light)
        .environment(\.locale, locale)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invoice \(draft.number)")
                .font(.title.weight(.semibold))
                .foregroundColor(.black)

            HStack {
                Text("Date")
                Text(dateFormatter.string(from: draft.invoiceDate))
                Spacer()
                Text("Due Date").bold()
                Text(dateFormatter.string(from: draft.dueDate)).bold()
            }
            .font(.subheadline)
        }
    }

    private var continuationHeader: some View {
        HStack {
            Text("Invoice \(draft.number)")
                .font(.headline)
            Spacer()
            Text(issuer.name)
                .font(.footnote)
        }
        .foregroundColor(.black)
    }

    private var lineItemsSection: some View {
        VStack(spacing: 12) {
            Divider().padding(.bottom, 10)
            HStack {
                Text("Description").bold()
                Spacer()
                Text("Amount").bold()
            }
            .font(.headline)
            .padding(.bottom, 5)

            ForEach(page.items) { item in
                HStack(alignment: .top) {
                    Text(item.description)
                    Spacer()
                    Text(InvoiceMath.fixedTwoDecimals(item.amount))
                }
                Divider()
            }
        }
    }

    private var totalAndVATSection: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack {
                Spacer()
                Text("Total")
                Spacer().frame(width: 60)
                Text("CHF \(InvoiceMath.fixedTwoDecimals(draft.total))")
                    .bold()
            }
            .font(.title2)

            if draft.isVATExempt {
                Text("Not subject to VAT according to Art. 10 Abs. 2 MWSTG")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private var qrCodeSection: some View {
        let qrPayload = SwissQRBuilder.makePayload(
            iban: issuer.iban,
            creditorName: issuer.name,
            creditorAddress: issuer.address,
            amount: draft.total,
            debtorName: draft.clientName,
            debtorAddress: draft.clientAddress,
            unstructuredMessage: draft.number
        )

        if let payload = qrPayload, let qrImage = generateQRImage(from: payload) {
            HStack(spacing: 20) {
                #if os(iOS)
                Image(uiImage: qrImage).interpolation(.none).resizable().scaledToFit()
                #else
                Image(nsImage: qrImage).interpolation(.none).resizable().scaledToFit()
                #endif

                VStack(alignment: .leading, spacing: 6) {
                    Text("Payable to").bold()
                    Text(issuer.name)
                    Text("IBAN: \(issuer.iban)")
                    Spacer().frame(height: 10)
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("Amount: %@", comment: ""),
                        "CHF \(InvoiceMath.fixedTwoDecimals(draft.total))"
                    ))
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("Reference: %@", comment: ""),
                        draft.number
                    ))
                }
                .font(.system(size: 10, design: .monospaced))
                Spacer()
            }
            .frame(height: 120)
            .padding(.top)
            .overlay(EdgeBorder(width: 1, edges: [.top]).foregroundColor(.gray))
        } else {
            Text("QR code could not be generated.\nPlease check IBAN and address details.")
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    private var pageFooter: some View {
        HStack {
            Spacer()
            Text(String.localizedStringWithFormat(
                NSLocalizedString("Page %d of %d", comment: ""),
                page.index + 1, page.count
            ))
            .font(.caption)
            .foregroundColor(.gray)
        }
        .padding(.top, 8)
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.clientName).font(.title3).bold()
                Text(draft.clientAddress.replacingOccurrences(of: ", ", with: "\n"))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(issuer.name).font(.headline)
                Text(issuer.address.replacingOccurrences(of: ", ", with: "\n"))
                if !issuer.uid.isEmpty {
                    Text("UID: \(issuer.uid)")
                }
            }
            .font(.footnote).multilineTextAlignment(.trailing)
        }
    }

    private func generateQRImage(from string: String) -> XImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        guard let cgImage = cgImage(from: scaledImage) else { return nil }
        return platformImage(from: cgImage)
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX
                }
            }
            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY
                }
            }
            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return self.width
                }
            }
            var h: CGFloat {
                switch edge {
                case .top, .bottom: return self.width
                case .leading, .trailing: return rect.height
                }
            }
            path.addPath(Path(CGRect(x: x, y: y, width: w, height: h)))
        }
        return path
    }
}
