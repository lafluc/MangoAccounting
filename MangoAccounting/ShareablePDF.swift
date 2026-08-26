// ShareablePDF.swift

import SwiftUI
import UniformTypeIdentifiers

/// This struct wraps our PDF data and provides the necessary metadata
/// for the share sheet to recognize it as a PDF with a specific name.
struct ShareablePDF: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        // Defines how the data is represented when shared.
        // We specify the content type as PDF.
        DataRepresentation(exportedContentType: .pdf) { pdf in
            // When the system asks for the data, we provide it from our `data` property.
            pdf.data
        }
        // This modifier tells the system what to name the file by default.
        .suggestedFileName { pdf in
            pdf.filename
        }
    }
}
