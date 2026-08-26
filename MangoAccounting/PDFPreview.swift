//
//  PDFPreview.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 19.08.2025.
//

import Foundation

/// A simple identifiable wrapper for PDF data, used for SwiftUI sheets.
struct PDFPreview: Identifiable {
    let id = UUID()
    let data: Data
}
