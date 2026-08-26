import Foundation

struct ReportGenerator {
    let transactions: [TransactionItem]
    let assets: [AssetItem]
    let targetYear: Int
    var liquidAssets: Double = 0.0
    var liabilities: Double = 0.0

    var totalIncome: Double {
        transactions.filter { $0.type == "Income" }.reduce(0) { $0 + $1.amount }
    }

    var totalDepreciation: Double {
        assets.reduce(0) { $0 + $1.depreciation(forYear: targetYear) }
    }

    var totalExpenses: Double {
        let baseExpenses = transactions.filter { $0.type == "Expense" }.reduce(0) { $0 + $1.amount }
        return baseExpenses + totalDepreciation
    }

    var netProfit: Double {
        totalIncome - totalExpenses
    }

    var totalCarKilometers: Double {
        transactions.filter { $0.category == "Car Expenses" }.reduce(0) { $0 + $1.carKilometers }
    }

    var incomeByCategory: [(category: String, total: Double)] {
        let grouped = Dictionary(grouping: transactions.filter { $0.type == "Income" }) {
            $0.category ?? "Sonstige Einnahmen"
        }
        return grouped.map { (category, items) in
            (category, items.reduce(0) { $0 + $1.amount })
        }.sorted { $0.total > $1.total }
    }

    var expensesByCategory: [(category: String, total: Double)] {
        var grouped = Dictionary(grouping: transactions.filter { $0.type == "Expense" }) {
            $0.category ?? "Sonstige Ausgaben"
        }.mapValues { items in items.reduce(0) { $0 + $1.amount } }

        let dep = totalDepreciation
        if dep > 0 {
            let current = grouped["Abschreibungen"] ?? 0
            grouped["Abschreibungen"] = current + dep
        }

        return grouped.map { (category: $0.key, total: $0.value) }.sorted { $0.total > $1.total }
    }

    var totalAssetBookValue: Double {
        assets.reduce(0) { $0 + $1.bookValue(atEndOfYear: targetYear) }
    }

    var totalAktiven: Double {
        liquidAssets + totalAssetBookValue
    }

    var totalPassiven: Double {
        liabilities
    }

    var eigenkapital: Double {
        totalAktiven - totalPassiven
    }
}
