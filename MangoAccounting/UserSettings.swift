//
//  UserSettings.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 14.08.2025.
//

import SwiftUI
import Combine

class UserSettings: ObservableObject {
    @AppStorage("name") var name: String = ""
    @AppStorage("address") var address: String = ""
    @AppStorage("iban") var iban: String = ""
    @AppStorage("uid") var uid: String = ""
    @AppStorage("language") var language: String = "en"
    @AppStorage("tabOrder") var tabOrderData: Data = Data()
    
    // NEW: Store a list of used currencies (comma separated string)
    @AppStorage("usedCurrencies") var usedCurrenciesString: String = "CHF,EUR,USD"
    
    var usedCurrencies: [String] {
        get {
            usedCurrenciesString.split(separator: ",").map { String($0) }
        }
        set {
            usedCurrenciesString = newValue.joined(separator: ",")
        }
    }
    
    /// A locale the system can actually resolve, for formatting numbers, currency
    /// and dates.
    ///
    /// `language` may be "frk" (Oberfränkisch), which is a real user-facing choice
    /// for *strings* but not a locale Foundation knows. Formatting against it falls
    /// back unpredictably — and numeric text fields parse against it too, so a
    /// Swiss user typing "1234,50" could get an unpredictable value. Swiss German
    /// formatting is the right pairing for the dialect and for CHF amounts.
    var formattingLocaleIdentifier: String {
        switch language {
        case "frk": return "de_CH"
        case "de": return "de_CH"
        default: return language
        }
    }

    func addCurrency(_ code: String) {
        var currents = usedCurrencies
        if !currents.contains(code) {
            currents.append(code)
            currents.sort()
            usedCurrencies = currents
        }
    }
}
