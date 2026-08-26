//
//  MangoAccounting.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 14.08.2025.
//

import SwiftUI

@main
struct MangoAccountingApp: App {
    @StateObject private var persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            // If the store could not be opened, show a recovery screen rather
            // than launching into an app whose data is missing.
            if persistenceController.loadFailure == nil {
                MainView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
            } else {
                StoreRecoveryView(controller: persistenceController)
            }
        }
    }
}
