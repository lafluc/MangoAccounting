// CoreDataSaving.swift

import CoreData

extension NSManagedObjectContext {

    /// Saves pending changes, rolling back if the save is rejected.
    ///
    /// The rollback matters more than it looks. A `save()` that throws leaves the
    /// offending object in the context, so *every* later save anywhere in the app
    /// fails too — the user's subsequent edits and deletions then silently stop
    /// persisting with no visible cause. Discarding the bad change keeps the rest
    /// of the app working.
    ///
    /// - Returns: A message to show the user, or `nil` when the save succeeded
    ///   (or there was nothing to save).
    @discardableResult
    func saveOrRollback() -> String? {
        guard hasChanges else { return nil }
        do {
            try save()
            return nil
        } catch {
            rollback()
            return (error as NSError).localizedDescription
        }
    }
}
