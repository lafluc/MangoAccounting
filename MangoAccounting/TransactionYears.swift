// TransactionYears.swift

import CoreData

/// Which fiscal years the ledger actually spans.
enum TransactionYears {

    /// Every year from the earliest transaction to the latest, inclusive.
    ///
    /// One aggregate fetch for the two bounding dates rather than loading rows:
    /// `billImage` is binary data stored inline in each row, so fetching objects
    /// would pull every receipt scan into memory to read a date.
    static func spanned(in context: NSManagedObjectContext) -> [Int] {
        let request = NSFetchRequest<NSDictionary>(entityName: "TransactionItem")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "date != nil")

        let earliest = NSExpressionDescription()
        earliest.name = "earliest"
        earliest.expression = NSExpression(
            forFunction: "min:", arguments: [NSExpression(forKeyPath: "date")]
        )
        earliest.expressionResultType = .dateAttributeType

        let latest = NSExpressionDescription()
        latest.name = "latest"
        latest.expression = NSExpression(
            forFunction: "max:", arguments: [NSExpression(forKeyPath: "date")]
        )
        latest.expressionResultType = .dateAttributeType

        request.propertiesToFetch = [earliest, latest]

        guard let row = (try? context.fetch(request))?.first,
              let first = row["earliest"] as? Date,
              let last = row["latest"] as? Date
        else { return [] }

        let firstYear = FiscalCalendar.year(of: first)
        let lastYear = FiscalCalendar.year(of: last)
        guard firstYear <= lastYear else { return [] }
        return Array(firstYear...lastYear)
    }
}
