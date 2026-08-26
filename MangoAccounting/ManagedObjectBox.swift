// ManagedObjectBox.swift

import CoreData

/// Wraps a managed object so it can drive `.sheet(item:)` keyed on `objectID`.
///
/// Both entities carry an optional `id: UUID?` attribute, and their `Identifiable`
/// conformance resolves to it rather than to `objectID`. That attribute is only
/// assigned on insert and was never backfilled, so any pre-existing row with a
/// nil `id` shares an identity with every other such row — enough for SwiftUI to
/// present the wrong record. `objectID` is always present and always unique.
struct ManagedObjectBox<Object: NSManagedObject>: Identifiable {
    let object: Object
    var id: NSManagedObjectID { object.objectID }

    init(_ object: Object) {
        self.object = object
    }
}
