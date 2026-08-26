// Money.swift

import Foundation

/// Rounding rules for money.
///
/// Amounts are held as `Double` throughout the app. Rounding at every boundary —
/// each displayed row, each total, each PDF line — is what keeps a column of
/// printed figures adding up to the total printed beneath it.
enum Money {

    /// Rounds to whole rappen, half away from zero.
    ///
    /// `(value * 100).rounded() / 100` is not enough: 1.005 is held as slightly
    /// *less* than 1.005 in binary floating point, so that expression yields 1.00
    /// where an accountant expects 1.01. Going through `Decimal`, seeded from the
    /// value's decimal text so the binary approximation is discarded, rounds the
    /// number the user actually typed.
    static func roundToCents(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let text = String(format: "%.10f", value)
        var source = Decimal(string: text) ?? Decimal(value)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .plain)
        return NSDecimalNumber(decimal: rounded).doubleValue
    }

    /// Sums values that will each be displayed rounded, so the total matches the
    /// column above it rather than differing by a rappen.
    static func sumOfRounded<S: Sequence>(_ values: S) -> Double where S.Element == Double {
        roundToCents(values.reduce(0) { $0 + roundToCents($1) })
    }

    /// Two decimals with a dot, independent of locale — the form the Swiss QR
    /// payload and the PDF line items are specified in.
    static func fixedTwoDecimals(_ value: Double) -> String {
        String(format: "%.2f", roundToCents(value))
    }
}
