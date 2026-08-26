//
//  PDFKitView.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 14.08.2025.
//

import SwiftUI
import PDFKit

#if os(iOS)
typealias PlatformViewRepresentable = UIViewRepresentable
#else
typealias PlatformViewRepresentable = NSViewRepresentable
#endif

struct PDFKitView: PlatformViewRepresentable {
    let data: Data

    #if os(iOS)
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }
    
    // MODIFICATION: Implemented updateUIView to reload the document when data changes.
    func updateUIView(_ uiView: PDFView, context: Context) {
        if let newDocument = PDFDocument(data: data) {
            uiView.document = newDocument
        }
    }
    #else
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }
    
    // MODIFICATION: Implemented updateNSView to reload the document when data changes.
    func updateNSView(_ nsView: PDFView, context: Context) {
        if let newDocument = PDFDocument(data: data) {
            nsView.document = newDocument
        }
    }
    #endif
}
