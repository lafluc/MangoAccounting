//
//  MainView.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 19.08.2025.
//

import SwiftUI

struct MainView: View {
    @StateObject private var userSettings = UserSettings()

    var body: some View {
        ContentView()
            // This forces the entire view hierarchy to re-render
            // with the new language when the setting changes.
            //
            // Deliberately the raw language, not `formattingLocaleIdentifier`:
            // SwiftUI looks up localized strings through this locale, and "frk"
            // (Oberfränkisch) has to stay here for its translations to resolve.
            // Output where formatting conventions matter — the generated PDFs —
            // passes the resolvable locale to its renderer explicitly.
            .environment(\.locale, Locale(identifier: userSettings.language))
            // By adding an id that changes, we tell SwiftUI the view is completely new.
            .id(userSettings.language)
    }
}
