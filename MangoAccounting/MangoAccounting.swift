//
//  MangoAccounting.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 14.08.2025.
//

import SwiftUI

@main
struct MangoAccountingApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            // Use MainView as the root view now
            MainView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
