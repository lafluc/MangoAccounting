import Foundation

struct ReportGenerator {
    let transactions: [TransactionItem]
    let assets: [AssetItem]
    let targetYear: Int
    var liquidAssets: Double = 0.0
    var liabilities: Double = 0.0

    /// Totals are the sum of the *rounded* category rows, so the figures printed
    /// in the report add up to the totals printed beneath them. Summing the raw
    /// values first could leave the column and its total a rappen apart.
    var totalIncome: Double {
        Money.sumOfRounded(incomeByCategory.map(\.total))
    }

    var totalDepreciation: Double {
        Money.sumOfRounded(assets.map { $0.depreciation(forYear: targetYear) })
    }

    var totalExpenses: Double {
        Money.sumOfRounded(expensesByCategory.map(\.total))
    }

    var netProfit: Double {
        Money.roundToCents(totalIncome - totalExpenses)
    }

    /// Mileage total for the Fahrtenbuch.
    ///
    /// Keyed on the literal category name seeded by `CategoryManager`. Renaming
    /// that category in the app silently zeroes this figure — a known limitation:
    /// categories are plain strings with no stable identity.
    static let carExpensesCategory = "Car Expenses"

    var totalCarKilometers: Double {
        transactions
            .filter { $0.category == Self.carExpensesCategory }
            .reduce(0) { $0 + $1.carKilometers }
    }

    /// Category name used when a transaction has none. These are data values that
    /// appear verbatim in the report, not localization keys.
    static let uncategorizedIncome = "Sonstige Einnahmen"
    static let uncategorizedExpense = "Sonstige Ausgaben"
    static let depreciationCategory = "Abschreibungen"

    var incomeByCategory: [(category: String, total: Double)] {
        Dictionary(grouping: transactions.filter { $0.type == "Income" }) {
            $0.category?.isEmpty == false ? $0.category! : Self.uncategorizedIncome
        }
        .map { (category: $0.key, total: Money.sumOfRounded($0.value.map(\.amount))) }
        .sorted { $0.total > $1.total }
    }

    var expensesByCategory: [(category: String, total: Double)] {
        var grouped = Dictionary(grouping: transactions.filter { $0.type == "Expense" }) {
            $0.category?.isEmpty == false ? $0.category! : Self.uncategorizedExpense
        }
        .mapValues { items in Money.sumOfRounded(items.map(\.amount)) }

        let depreciation = Money.sumOfRounded(assets.map { $0.depreciation(forYear: targetYear) })
        if depreciation > 0 {
            grouped[Self.depreciationCategory] =
                Money.roundToCents((grouped[Self.depreciationCategory] ?? 0) + depreciation)
        }

        return grouped.map { (category: $0.key, total: $0.value) }.sorted { $0.total > $1.total }
    }

    var totalAssetBookValue: Double {
        Money.sumOfRounded(assets.map { $0.bookValue(atEndOfYear: targetYear) })
    }

    var totalAktiven: Double {
        Money.roundToCents(liquidAssets + totalAssetBookValue)
    }

    var totalPassiven: Double {
        Money.roundToCents(liabilities)
    }

    /// Equity is derived, so the balance sheet balances by construction and cannot
    /// reveal a data-entry error in the two figures the user types. Reconciling it
    /// against accumulated profit would need an opening-balance concept the app
    /// does not have.
    var eigenkapital: Double {
        Money.roundToCents(totalAktiven - totalPassiven)
    }
}
