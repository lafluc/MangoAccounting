//
//  MainView.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 19.08.2025.
//

import SwiftUI

struct MainView: View {
    // Read straight from UserDefaults rather than through UserSettings.
    //
    // `@AppStorage` only publishes changes when it is installed on a View. Inside
    // an ObservableObject it writes through but never notifies, and each screen
    // held its own instance — which is why switching language did nothing until
    // the app was relaunched. Declared here, these observe the same keys the
    // Settings screen writes and update immediately.
    @AppStorage("language") private var language: String = "en"
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw: String =
        AppAppearance.defaultValue.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .defaultValue
    }

    var body: some View {
        ContentView()
            // Deliberately the raw language, not a resolvable formatting locale:
            // SwiftUI looks up localized strings through this, and "frk"
            // (Oberfränkisch) has to stay here for its translations to resolve.
            // Output where formatting conventions matter — the generated PDFs —
            // passes a resolvable locale to its renderer explicitly.
            .environment(\.locale, Locale(identifier: language))
            .preferredColorScheme(appearance.colorScheme)
            // Rebuilds the hierarchy so every localized string is re-read.
            .id(language)
    }
}
