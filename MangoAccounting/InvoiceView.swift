//
//  InvoiceView.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 17.08.2025.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct InvoiceView: View {
    let userSettings: UserSettings
    let clientName: String
    let clientAddress: String
    let invoiceNumber: String
    let invoiceDate: Date
    let dueDate: Date
    let lineItems: [InvoiceGeneratorView.LineItem]
    let totalAmount: Double
    let customMessage: String
    let isVATExempt: Bool
    let locale: Locale

    private var a4Size: CGSize { CGSize(width: 595.2, height: 841.8) }
    private var margin: CGFloat { 40 }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = locale
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            
            Spacer().frame(height: 60)
            
            titleSection
            
            if !customMessage.isEmpty {
                Text(customMessage)
                    .font(.callout)
                    .padding(.top, 25)
            }
            
            Spacer(minLength: 20)
            
            lineItemsSection
            
            totalAndVATSection // This section is now corrected
            
            qrCodeSection.frame(maxWidth: .infinity)
        }
        .padding(margin)
        .frame(width: a4Size.width, height: a4Size.height)
        .background(Color.white)
        .foregroundColor(.black)
        .font(.system(size: 11, design: .default))
    }
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invoice \(invoiceNumber)")
                .font(.title.weight(.semibold))
                .foregroundColor(.primary)
            
            HStack {
                Text("Date")
                Text(dateFormatter.string(from: invoiceDate))
                Spacer()
                Text("Due Date").bold()
                Text(dateFormatter.string(from: dueDate)).bold()
            }
            .font(.subheadline)
        }
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
            
            ForEach(lineItems) { item in
                HStack(alignment: .top) {
                    Text(item.description)
                    Spacer()
                    Text(String(format: "%.2f", item.amount))
                }
                Divider()
            }
        }
    }
    
    // MODIFICATION: The layout is changed to a VStack to place VAT info below the total.
    private var totalAndVATSection: some View {
        // Use a VStack to align content to the trailing edge.
        VStack(alignment: .trailing, spacing: 5) {
            // Total Row
            HStack {
                Spacer() // Pushes the content to the right
                Text("Total")
                Spacer().frame(width: 60)
                Text("CHF \(String(format: "%.2f", totalAmount))")
                    .bold()
            }
            .font(.title2)
            
            // VAT Exemption Text, shown conditionally
            if isVATExempt {
                Text("Not subject to VAT according to Art. 10 Abs. 2 MWSTG")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.top, 20) // Add space above the total section
    }

    @ViewBuilder
    private var qrCodeSection: some View {
        let qrPayload = SwissQRBuilder.makePayload(iban: userSettings.iban, creditorName: userSettings.name, creditorAddress: userSettings.address, amount: totalAmount, debtorName: clientName, debtorAddress: clientAddress, unstructuredMessage: invoiceNumber)
        
        if let payload = qrPayload, let qrImage = generateQRImage(from: payload) {
            HStack(spacing: 20) {
                #if os(iOS)
                Image(uiImage: qrImage).interpolation(.none).resizable().scaledToFit()
                #else
                 Image(nsImage: qrImage).interpolation(.none).resizable().scaledToFit()
                #endif
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Payable to").bold()
                    Text(userSettings.name)
                    Text("IBAN: \(userSettings.iban)")
                    Spacer().frame(height: 10)
                    Text(String.localizedStringWithFormat(NSLocalizedString("Amount: %@", comment: ""), "CHF \(String(format: "%.2f", totalAmount))"))
                    Text(String.localizedStringWithFormat(NSLocalizedString("Reference: %@", comment: ""), invoiceNumber))
                 }
                .font(.system(size: 10, design: .monospaced))
                Spacer()
            }
            .frame(height: 120)
            .padding(.top)
            .overlay(EdgeBorder(width: 1, edges: [.top]).foregroundColor(.gray))
         } else {
            Text("QR code could not be generated.\nPlease check IBAN and address details.").font(.caption).foregroundColor(.red)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(clientName).font(.title3).bold()
                Text(clientAddress.replacingOccurrences(of: ", ", with: "\n"))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(userSettings.name).font(.headline)
                Text(userSettings.address.replacingOccurrences(of: ", ", with: "\n"))
                // ADDITION: Display the UID on the invoice if it exists
                if !userSettings.uid.isEmpty {
                    Text("UID: \(userSettings.uid)")
                }
            }
            .font(.footnote).multilineTextAlignment(.trailing)
        }
    }
    
    private func generateQRImage(from string: String) -> XImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(string.utf8); filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        guard let cgImage = cgImage(from: scaledImage) else { return nil }
        return platformImage(from: cgImage)
    }
}

extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
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
