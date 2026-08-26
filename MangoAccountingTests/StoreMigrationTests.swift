//
//  StoreMigrationTests.swift
//  MangoAccountingTests
//
//  Proves that a database written by the shipped build opens in this build with
//  every row intact. This is the one guarantee that matters most on update: users
//  replace the .app in place and keep their existing store.
//

import CoreData
import Foundation
import Testing
@testable import MangoAccounting

@Suite("Store migration from the shipped model", .serialized)
struct StoreMigrationTests {

    /// The model as it shipped in the October 2025 build.
    ///
    /// Reconstructed by removing `AssetItem` from the current model: the shipped
    /// bundle's VersionInfo.plist carries version hashes for `TransactionItem`
    /// only, so the assets feature reached users for the first time after it.
    /// Reconstructing rather than reading the old bundle keeps the test
    /// self-contained.
    private func shippedModel() throws -> NSManagedObjectModel {
        let current = PersistenceController.shared.container.managedObjectModel
        let old = try #require(current.copy() as? NSManagedObjectModel)
        old.entities = old.entities.filter { $0.name != "AssetItem" }
        #expect(old.entities.map(\.name) == ["TransactionItem"])
        return old
    }

    private func store(at url: URL, model: NSManagedObjectModel) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "MangoAccounting", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    @Test("a store written by the shipped model opens here with every row intact")
    func migratesFromShippedModel() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MangoMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("MangoAccounting.sqlite")

        // ---- Write with the old model, as a user's existing install would ----
        let expected: [(details: String, amount: Double, type: String, year: Int)] = [
            ("Coffee with client", 42.50, "Expense", 2024),
            ("Project A milestone", 4_800.00, "Income", 2024),
            ("Train ticket", 88.00, "Expense", 2025),
        ]
        do {
            let old = try store(at: storeURL, model: try shippedModel())
            let context = old.viewContext
            for row in expected {
                let item = NSEntityDescription.insertNewObject(
                    forEntityName: "TransactionItem", into: context
                )
                item.setValue(UUID(), forKey: "id")
                item.setValue(row.details, forKey: "details")
                item.setValue(row.amount, forKey: "amount")
                item.setValue(row.type, forKey: "type")
                item.setValue("CHF", forKey: "currencyCode")
                item.setValue(row.amount, forKey: "originalAmount")
                item.setValue(FiscalCalendar.yearBounds(row.year).start, forKey: "date")
            }
            try context.save()

            // Close cleanly so the write-ahead log is checkpointed.
            for persistent in old.persistentStoreCoordinator.persistentStores {
                try old.persistentStoreCoordinator.remove(persistent)
            }
        }
        #expect(FileManager.default.fileExists(atPath: storeURL.path))

        // ---- Reopen with the current model, which is what the update does ----
        let current = try store(
            at: storeURL, model: PersistenceController.shared.container.managedObjectModel
        )
        let context = current.viewContext

        let request = NSFetchRequest<NSManagedObject>(entityName: "TransactionItem")
        request.sortDescriptors = [NSSortDescriptor(key: "amount", ascending: true)]
        let migrated = try context.fetch(request)

        #expect(migrated.count == expected.count, "no transaction may be lost on update")

        let byDetails = Dictionary(
            uniqueKeysWithValues: migrated.map { ($0.value(forKey: "details") as! String, $0) }
        )
        for row in expected {
            let item = try #require(byDetails[row.details], "\(row.details) went missing")
            #expect(item.value(forKey: "amount") as? Double == row.amount)
            #expect(item.value(forKey: "type") as? String == row.type)
            #expect(item.value(forKey: "currencyCode") as? String == "CHF")
            let date = try #require(item.value(forKey: "date") as? Date)
            #expect(FiscalCalendar.year(of: date) == row.year, "the fiscal year must not shift")
        }

        // The entity added after the shipped build is present and usable, and
        // starts empty rather than erroring.
        let assets = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "AssetItem"))
        #expect(assets.isEmpty)

        let asset = NSEntityDescription.insertNewObject(forEntityName: "AssetItem", into: context)
        asset.setValue(UUID(), forKey: "id")
        asset.setValue("RED Komodo", forKey: "name")
        asset.setValue(10_000.0, forKey: "purchasePrice")
        asset.setValue(40.0, forKey: "depreciationRate")
        asset.setValue(false, forKey: "isLinear")
        asset.setValue(FiscalCalendar.yearBounds(2025).start, forKey: "purchaseDate")
        try context.save()

        #expect(try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "AssetItem")) == 1)
    }

    @Test("the recovery path is not reachable for a store that only needs migration")
    func migrationDoesNotTriggerRecovery() throws {
        // The old code treated any NSCocoaErrorDomain error as grounds to delete
        // the store. A routine model addition must not look like a failure at all.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MangoMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("MangoAccounting.sqlite")
        let old = try store(at: storeURL, model: try shippedModel())
        for persistent in old.persistentStoreCoordinator.persistentStores {
            try old.persistentStoreCoordinator.remove(persistent)
        }

        // Opening with the current model must simply succeed.
        let reopened = try store(
            at: storeURL, model: PersistenceController.shared.container.managedObjectModel
        )
        #expect(reopened.persistentStoreCoordinator.persistentStores.count == 1)
        #expect(FileManager.default.fileExists(atPath: storeURL.path))
    }
}
