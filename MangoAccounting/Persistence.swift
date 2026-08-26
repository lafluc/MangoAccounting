//
//  Persistence.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 14.08.2025.
//

import CoreData
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for i in 0..<8 {
            let newItem = TransactionItem(context: viewContext)
            newItem.id = UUID()
            newItem.date = Calendar.current.date(byAdding: .day, value: -i, to: Date())
            newItem.details = i % 2 == 0 ? "Income Example \(i)" : "Expense Example \(i)"
            newItem.amount = i % 2 == 0 ? Double.random(in: 500...2000) : Double.random(in: 50...300)
            newItem.type = i % 2 == 0 ? "Income" : "Expense"
            newItem.category = i % 2 == 0 ? "Project A" : "Office Supplies"
            newItem.currencyCode = "CHF"
            newItem.originalAmount = newItem.amount
        }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("Unresolved error during preview setup: \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "MangoAccounting")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        
        // Enable Lightweight Migration
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                // -------------------------------------------------------------
                // AUTO-FIX: WIPE DATABASE ON MIGRATION FAILURE
                // -------------------------------------------------------------
                // Error 134140 = Persistent store migration failed
                if error.code == 134140 || error.domain == NSCocoaErrorDomain {
                    print("⚠️ MIGRATION FAILED. WIPING INCOMPATIBLE STORE...")
                    
                    if let url = storeDescription.url {
                        do {
                            // Destroy the old database file
                            try FileManager.default.removeItem(at: url)
                            
                            // Also delete the support files (.wal, .shm)
                            let wal = url.appendingPathExtension("wal")
                            let shm = url.appendingPathExtension("shm")
                            try? FileManager.default.removeItem(at: wal)
                            try? FileManager.default.removeItem(at: shm)
                            
                            print("✅ Database deleted. Please restart the app to create a fresh one.")
                            
                            // We purposefully crash here so the app restarts fresh next time.
                            fatalError("Database was incompatible and has been reset. Please restart the app.")
                        } catch {
                            print("❌ Failed to delete incompatible store: \(error)")
                        }
                    }
                }
                
                // If it wasn't a migration error, log it normally
                fatalError("Unresolved error loading persistent stores: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
