//
//  Persistence.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 14.08.2025.
//

import CoreData
import Foundation

/// Why the persistent store could not be opened on this launch.
///
/// The app surfaces this instead of crashing, so a bad launch never costs the
/// user their ledger. Recovery is always explicit — see
/// `PersistenceController.backUpAndStartFresh()`.
enum StoreLoadFailure: Equatable {
    /// The store on disk does not match the current data model and lightweight
    /// migration could not bridge the gap.
    case incompatibleWithModel(message: String)

    /// The store could not be read for a reason unrelated to the model — a full
    /// disk, missing permissions, a locked or in-use file. Very often transient,
    /// so the store must be left exactly where it is.
    case unreadable(message: String)

    var message: String {
        switch self {
        case .incompatibleWithModel(let message), .unreadable(let message):
            return message
        }
    }

    /// Whether starting over with a fresh store is a sensible offer. Only true
    /// for a genuine model mismatch; a transient read failure should be retried,
    /// never "fixed" by setting the user's data aside.
    var allowsStartingFresh: Bool {
        if case .incompatibleWithModel = self { return true }
        return false
    }
}

final class PersistenceController: ObservableObject {

    static let shared = PersistenceController()

    /// In-memory controller for SwiftUI previews, seeded with sample rows.
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

    /// Non-nil when the store could not be opened. The UI presents a recovery
    /// screen instead of the app while this is set.
    @Published private(set) var loadFailure: StoreLoadFailure?

    /// Path of the store that was moved aside by `backUpAndStartFresh()`, so the
    /// recovery screen can show the user where their old data went.
    @Published private(set) var lastBackupURL: URL?

    private static let modelName = "MangoAccounting"

    /// Core Data error codes that mean "this store's schema does not match this
    /// model". These are the only failures where recreating the store is a
    /// coherent recovery.
    ///
    /// Deliberately excluded: `NSPersistentStoreIncompatibleSchemaError` (134020),
    /// which despite its name also covers database-level problems such as missing
    /// permissions; `NSMigrationCancelledError`, which this app never triggers;
    /// and the source/destination store errors, which can be caused by disk
    /// trouble rather than the model.
    private static let modelMismatchCodes: Set<Int> = [
        NSPersistentStoreIncompatibleVersionHashError,
        NSMigrationError,
        NSMigrationMissingSourceModelError,
        NSMigrationMissingMappingModelError,
        NSEntityMigrationPolicyError,
        NSInferredMappingModelError,
    ]

    init(inMemory: Bool = false) {
        let container = NSPersistentCloudKitContainer(name: Self.modelName)

        if let description = container.persistentStoreDescriptions.first {
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            }
            #if DEBUG
            // UI tests run against a disposable store so they are reproducible and
            // never touch the user's real database.
            if !inMemory, UITestSupport.isActive {
                UITestSupport.resetSupportingState()
                description.url = UITestSupport.makeCleanStoreURL()
            }
            #endif
            // Lightweight migration: adding entities or optional attributes is
            // inferred automatically, which is how every model change so far has
            // reached existing users.
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        self.container = container
        self.loadFailure = Self.attachStores(to: container)

        #if DEBUG
        if !inMemory, UITestSupport.isActive, loadFailure == nil {
            UITestSupport.seed(into: container.viewContext)
        }
        #endif
    }

    // MARK: - Loading

    /// Attaches the persistent stores, returning a failure description rather
    /// than trapping. Nothing on disk is modified here under any circumstances.
    private static func attachStores(to container: NSPersistentCloudKitContainer) -> StoreLoadFailure? {
        var loadError: NSError?
        container.loadPersistentStores { _, error in
            // For local stores this handler runs synchronously, once per store.
            if let error = error as NSError?, loadError == nil {
                loadError = error
            }
        }

        guard let error = loadError else { return nil }

        let detail = error.localizedDescription
        if modelMismatchCodes.contains(error.code) {
            return .incompatibleWithModel(message: detail)
        }
        return .unreadable(message: detail)
    }

    /// Re-attempts the load, for failures that may have been transient.
    func retry() {
        guard loadFailure != nil else { return }
        // Drop any half-attached stores so the retry starts clean.
        detachLoadedStores()
        loadFailure = Self.attachStores(to: container)
    }

    /// Moves the unreadable store aside — never deletes it — and creates a fresh
    /// one in its place. Only offered for a genuine model mismatch, and only ever
    /// called from an explicit user action.
    func backUpAndStartFresh() {
        guard let failure = loadFailure, failure.allowsStartingFresh else { return }
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            loadFailure = .unreadable(message: "The location of the database could not be determined.")
            return
        }

        detachLoadedStores()

        do {
            lastBackupURL = try Self.moveStoreAside(at: storeURL)
        } catch {
            loadFailure = .unreadable(message: "The database could not be moved aside: \(error.localizedDescription)")
            return
        }

        loadFailure = Self.attachStores(to: container)
    }

    private func detachLoadedStores() {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
    }

    // MARK: - Backup

    /// Renames the store and its write-ahead-log sidecars out of the way,
    /// returning the new location of the main file.
    private static func moveStoreAside(at storeURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let stem = storeURL.deletingPathExtension().lastPathComponent
        let extensionName = storeURL.pathExtension
        let stamp = backupTimestamp()

        var backupStem = "\(stem)-backup-\(stamp)"
        var backupURL = directory.appendingPathComponent(
            extensionName.isEmpty ? backupStem : "\(backupStem).\(extensionName)"
        )
        // Two recoveries within the same second must not collide.
        var attempt = 2
        while fileManager.fileExists(atPath: backupURL.path) {
            backupStem = "\(stem)-backup-\(stamp)-\(attempt)"
            backupURL = directory.appendingPathComponent(
                extensionName.isEmpty ? backupStem : "\(backupStem).\(extensionName)"
            )
            attempt += 1
        }

        try fileManager.moveItem(at: storeURL, to: backupURL)

        // SQLite names its sidecars "MangoAccounting.sqlite-wal" and "-shm": a
        // suffix appended to the whole filename, not a second path extension.
        // Getting this wrong leaves a stale write-ahead log that can bleed rows
        // from the old database into the new one.
        for suffix in ["-wal", "-shm"] {
            let sidecar = directory.appendingPathComponent(storeURL.lastPathComponent + suffix)
            guard fileManager.fileExists(atPath: sidecar.path) else { continue }
            let sidecarBackup = directory.appendingPathComponent(backupURL.lastPathComponent + suffix)
            try? fileManager.moveItem(at: sidecar, to: sidecarBackup)
        }

        return backupURL
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
