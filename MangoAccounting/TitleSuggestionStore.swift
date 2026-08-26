// TitleSuggestionStore.swift

import CoreData
import Foundation

/// A transaction title that has been used before, with how often and how recently.
struct TitleSuggestion: Identifiable, Hashable {
    let title: String
    let useCount: Int
    let lastUsed: Date?

    var id: String { title }
}

/// Supplies previously-used transaction titles for autocomplete.
enum TitleSuggestionStore {

    /// How many chips to offer at once. More than this and the row stops being
    /// scannable at a glance.
    static let maximumSuggestions = 8

    /// Loads every distinct title with a use count and a last-used date.
    ///
    /// Uses an aggregate dictionary fetch rather than loading `TransactionItem`
    /// objects, because `billImage` is binary data stored inline in the row — no
    /// external-storage flag on the attribute — so fetching whole objects would
    /// pull every receipt scan into memory just to read a description.
    static func loadAll(in context: NSManagedObjectContext) -> [TitleSuggestion] {
        let request = NSFetchRequest<NSDictionary>(entityName: "TransactionItem")
        request.resultType = .dictionaryResultType
        request.propertiesToGroupBy = ["details"]
        request.predicate = NSPredicate(format: "details != nil AND details != %@", "")

        let useCount = NSExpressionDescription()
        useCount.name = "useCount"
        useCount.expression = NSExpression(
            forFunction: "count:", arguments: [NSExpression(forKeyPath: "details")]
        )
        useCount.expressionResultType = .integer64AttributeType

        let lastUsed = NSExpressionDescription()
        lastUsed.name = "lastUsed"
        lastUsed.expression = NSExpression(
            forFunction: "max:", arguments: [NSExpression(forKeyPath: "date")]
        )
        lastUsed.expressionResultType = .dateAttributeType

        request.propertiesToFetch = ["details", useCount, lastUsed]

        guard let rows = try? context.fetch(request) else { return [] }

        return rows.compactMap { row in
            guard let title = row["details"] as? String,
                  !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return TitleSuggestion(
                title: title,
                useCount: (row["useCount"] as? Int) ?? 1,
                lastUsed: row["lastUsed"] as? Date
            )
        }
    }

    /// Orders suggestions for what has been typed so far.
    ///
    /// Titles starting with the typed text come first, then the most-used, then
    /// the most-recent. A title identical to what is already typed is dropped —
    /// there is nothing to complete.
    static func rank(
        _ suggestions: [TitleSuggestion],
        matching query: String,
        limit: Int = maximumSuggestions
    ) -> [TitleSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        let candidates = trimmed.isEmpty
            ? suggestions
            : suggestions.filter {
                $0.title.range(of: trimmed, options: options) != nil
                    && $0.title.compare(trimmed, options: options) != .orderedSame
            }

        return Array(
            candidates
                .sorted { first, second in
                    let firstIsPrefix = hasPrefix(first.title, trimmed, options)
                    let secondIsPrefix = hasPrefix(second.title, trimmed, options)
                    if firstIsPrefix != secondIsPrefix { return firstIsPrefix }

                    if first.useCount != second.useCount { return first.useCount > second.useCount }

                    let firstDate = first.lastUsed ?? .distantPast
                    let secondDate = second.lastUsed ?? .distantPast
                    if firstDate != secondDate { return firstDate > secondDate }

                    return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
                }
                .prefix(limit)
        )
    }

    private static func hasPrefix(
        _ title: String, _ query: String, _ options: String.CompareOptions
    ) -> Bool {
        guard !query.isEmpty else { return false }
        return title.range(of: query, options: options.union(.anchored)) != nil
    }

    /// The most recent transaction with this exact title, used to prefill the rest
    /// of the form. Fetches one row, so the receipt blob cost is bounded.
    static func mostRecentTransaction(
        withTitle title: String, in context: NSManagedObjectContext
    ) -> TransactionItem? {
        let request: NSFetchRequest<TransactionItem> = TransactionItem.fetchRequest()
        request.predicate = NSPredicate(format: "details == %@", title)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TransactionItem.date, ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }
}
