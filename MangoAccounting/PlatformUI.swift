//
//  PlatformUI.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 14.08.2025.
//

import SwiftUI
import CoreGraphics
import PDFKit
import CoreImage
import CoreImage.CIFilterBuiltins

#if os(iOS)
import UIKit
public typealias XFont = UIFont
public typealias XColor = UIColor
public typealias XImage = UIImage
#else
import AppKit
public typealias XFont = NSFont
public typealias XColor = NSColor
public typealias XImage = NSImage
#endif

// MARK: - Cross-platform Colors for SwiftUI
extension Color {
    static var platformBackground: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
    static var platformSecondaryBackground: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    static var platformGroupedBackground: Color {
        #if os(iOS)
        return Color(UIColor.systemGroupedBackground)
        #else
        return Color(NSColor.underPageBackgroundColor)
        #endif
    }
}

// MARK: - Cross-platform text drawing helpers
struct DrawStyle {
    var font: XFont
    var color: XColor
}




// MARK: - Cross-platform QR image from CIImage
func cgImage(from ciImage: CIImage) -> CGImage? {
    let ctx = CIContext()
    return ctx.createCGImage(ciImage, from: ciImage.extent)
}

func platformImage(from cg: CGImage) -> XImage {
    #if os(iOS)
    return UIImage(cgImage: cg)
    #else
    return NSImage(cgImage: cg, size: .zero)
    #endif
}

// MARK: - Render a single-page PDF from a platform image

// Add this extension to the end of PlatformUI.swift

extension XColor {
    static var platformLabel: XColor {
        #if os(iOS)
        return .label
        #else
        return .labelColor
        #endif
    }

    static var platformSecondaryLabel: XColor {
        #if os(iOS)
        return .secondaryLabel
        #else
        return .secondaryLabelColor
        #endif
    }
}
extension Image {
    init(xImage: XImage) {
        #if os(iOS)
        self.init(uiImage: xImage)
        #else
        self.init(nsImage: xImage)
        #endif
    }
}
