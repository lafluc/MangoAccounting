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

func drawText(_ text: String, at point: CGPoint, style: DrawStyle) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: style.font,
        .foregroundColor: style.color
    ]
    #if os(iOS)
    (text as NSString).draw(at: point, withAttributes: attrs)
    #else
    (text as NSString).draw(at: point, withAttributes: attrs)
    #endif
}

@discardableResult
func drawMultilineText(_ text: String, in rect: CGRect, style: DrawStyle) -> CGSize {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: style.font,
        .foregroundColor: style.color
    ]
    let bounds = (text as NSString).boundingRect(
        with: rect.size,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attrs,
        context: nil
    )
    (text as NSString).draw(
        with: rect, // ✅ pass CGRect instead of CGSize
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attrs,
        context: nil
    )
    return bounds.size
}

func drawLine(from: CGPoint, to: CGPoint, width: CGFloat = 0.5) {
    #if os(iOS)
    let path = UIBezierPath()
    path.move(to: from); path.addLine(to: to)
    path.lineWidth = width
    UIColor.separator.setStroke()
    path.stroke()
    #else
    let path = NSBezierPath()
    path.move(to: from); path.line(to: to)
    path.lineWidth = width
    NSColor.separatorColor.setStroke()
    path.stroke()
    #endif
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
func pdfData(from image: XImage, pageSize: CGSize) -> Data? {
    let doc = PDFDocument()
    #if os(iOS)
    guard let page = PDFPage(image: image) else { return nil }
    #else
    guard let page = PDFPage(image: image) else { return nil }
    #endif
    doc.insert(page, at: 0)
    return doc.dataRepresentation()
}

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
