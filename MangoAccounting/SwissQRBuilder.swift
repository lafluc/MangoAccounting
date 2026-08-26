//
//  SwissQRBuilder.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 17.08.2025.
//

import Foundation

public enum SwissQRBuilder {
    private static func sanitize(_ input: String, maxLength: Int) -> String {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines);
        return String(cleaned.prefix(maxLength))
    }
    
    // MODIFICATION: This function now also filters out any UID lines just in case.
    private static func parseAddress(_ address: String) -> (line1: String, line2: String) {
        // Filter out any line that starts with "UID:" before processing.
        let filteredLines = address.split(separator: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).uppercased().starts(with: "UID:")
        }
        let addressWithoutUID = filteredLines.joined(separator: "\n")
        
        // Try to split by newline character.
        var lines = addressWithoutUID.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).map { String($0) }
        
        // If there's only one line, try splitting by the last comma as a fallback.
        if lines.count == 1, let commaRange = lines[0].range(of: ",", options: .backwards) {
            let line1part = String(lines[0][..<commaRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let line2part = String(lines[0][commaRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            lines = [line1part, line2part]
        }
        
        let line1 = sanitize(lines.first ?? "", maxLength: 70)
        let line2 = sanitize(lines.count > 1 ? lines[1] : "", maxLength: 70)
        return (line1, line2)
    }

    public static func makePayload(
        iban: String,
        creditorName: String,
        creditorAddress: String,
        amount: Double,
        debtorName: String,
        debtorAddress: String,
        unstructuredMessage: String // CHANGED from 'reference'
    ) -> String? {
        // MODIFICATION: Remove spaces from the IBAN *before* sanitizing it.
        let ibanWithoutSpaces = iban.replacingOccurrences(of: " ", with: "")
        let cleanIban = sanitize(ibanWithoutSpaces, maxLength: 21)
        
        guard cleanIban.starts(with: "CH") || cleanIban.starts(with: "LI") else { return nil }
        let creditorName = sanitize(creditorName, maxLength: 70)
        let (creditorAddr1, creditorAddr2) = parseAddress(creditorAddress)
        let debtorName = sanitize(debtorName, maxLength: 70)
        let (debtorAddr1, debtorAddr2) = parseAddress(debtorAddress)
        let amountString = (amount > 0) ? String(format: "%.2f", amount) : ""
        let message = sanitize(unstructuredMessage, maxLength: 140)

        let payloadArray: [String] = [
            "SPC", "0200", "1", cleanIban,
            "K", creditorName, creditorAddr1, creditorAddr2, "", "", "CH",
            "", "", "", "", "", "", "",
            amountString, "CHF",
            "K", debtorName, debtorAddr1, debtorAddr2, "", "", "CH",
            "NON", // Reference Type
            "",    // CORRECT: Reference field must be EMPTY for NON type
            message, // Use the unstructured message field for the invoice number
            "EPD",
            ""
         ]
        
        return payloadArray.joined(separator: "\r\n")
    }
}
