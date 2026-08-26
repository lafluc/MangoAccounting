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
    
    func addCurrency(_ code: String) {
        var currents = usedCurrencies
        if !currents.contains(code) {
            currents.append(code)
            currents.sort()
            usedCurrencies = currents
        }
    }
}
