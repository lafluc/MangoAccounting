//
//  DepreciationAndReportTests.swift
//  MangoAccountingTests
//

import CoreData
import Foundation
import Testing
@testable import MangoAccounting

/// One shared in-memory Core Data stack for the whole test bundle.
///
/// Reuses the model the host app already loaded. Loading a second copy makes Core
/// Data log "Failed to find a unique match for an NSEntityDescription" on every
/// insert, because two models then claim the same managed-object subclasses.
private enum TestStack {
    static let container: NSPersistentContainer = {
        let model = PersistenceController.shared.container.managedObjectModel
        let container = NSPersistentContainer(name: "MangoAccounting", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            precondition(error == nil, "in-memory store failed: \(error!)")
        }
        return container
    }()
}

private func makeContext() -> NSManagedObjectContext {
    TestStack.container.viewContext
}

private func makeAsset(
    in context: NSManagedObjectContext,
    price: Double,
    rate: Double,
    linear: Bool,
    purchasedIn year: Int
) -> AssetItem {
    let asset = AssetItem(context: context)
    asset.id = UUID()
    asset.name = "Asset"
    asset.purchasePrice = price
    asset.originalPrice = price
    asset.currencyCode = "CHF"
    asset.depreciationRate = rate
    asset.isLinear = linear
    asset.purchaseDate = FiscalCalendar.yearBounds(year).start
    return asset
}

private func makeTransaction(
    in context: NSManagedObjectContext,
    amount: Double,
    type: String,
    category: String,
    year: Int,
    kilometers: Double = 0
) -> TransactionItem {
    let item = TransactionItem(context: context)
    item.id = UUID()
    item.amount = amount
    item.originalAmount = amount
    item.currencyCode = "CHF"
    item.type = type
    item.category = category
    item.details = "Entry"
    item.date = FiscalCalendar.yearBounds(year).start
    item.carKilometers = kilometers
    return item
}

@Suite("Asset depreciation")
struct DepreciationTests {

    @Test("an asset carries no book value in a year before it was bought")
    func noValueBeforePurchase() {
        let context = makeContext()
        let asset = makeAsset(in: context, price: 10_000, rate: 40, linear: false, purchasedIn: 2026)

        // This returned the full purchase price, inflating total assets on every
        // balance sheet for a year before the item existed.
        #expect(asset.bookValue(atEndOfYear: 2024) == 0)
        #expect(asset.bookValue(atEndOfYear: 2025) == 0)
        #expect(asset.depreciation(forYear: 2025) == 0)
        #expect(asset.bookValue(atEndOfYear: 2026) > 0)
    }

    @Test("a linear asset depreciates all the way to zero")
    func linearReachesZero() {
        let context = makeContext()
        // 20% linear over 5 years writes the asset off exactly.
        let asset = makeAsset(in: context, price: 1_000, rate: 20, linear: true, purchasedIn: 2020)

        #expect(asset.bookValue(atEndOfYear: 2020) == 800)
        #expect(asset.bookValue(atEndOfYear: 2023) == 200)

        // Previously floored at CHF 1.00 forever, so book value and accumulated
        // depreciation permanently disagreed and total assets drifted upward with
        // every retired item.
        #expect(asset.bookValue(atEndOfYear: 2024) == 0)
        #expect(asset.bookValue(atEndOfYear: 2030) == 0)
    }

    @Test("a linear asset's book value plus its accumulated depreciation is its cost")
    func linearBooksReconcile() {
        let context = makeContext()
        let asset = makeAsset(in: context, price: 1_000, rate: 20, linear: true, purchasedIn: 2020)

        for year in 2020...2030 {
            let accumulated = (2020...year).reduce(0.0) { $0 + asset.depreciation(forYear: $1) }
            let book = asset.bookValue(atEndOfYear: year)
            #expect(
                abs(accumulated + book - 1_000) < 0.001,
                "year \(year): \(accumulated) + \(book) should be 1000"
            )
        }
    }

    @Test("a degressive asset keeps the conventional CHF 1 residual")
    func degressiveKeepsResidual() {
        let context = makeContext()
        let asset = makeAsset(in: context, price: 10_000, rate: 40, linear: false, purchasedIn: 2010)

        // Degressive depreciation never mathematically reaches zero, so the
        // residual is deliberate and unchanged.
        #expect(asset.bookValue(atEndOfYear: 2040) == 1.0)
        #expect(asset.bookValue(atEndOfYear: 2010) == 6_000)
    }

    @Test("the fiscal year of a stored date does not depend on the device time zone")
    func fiscalYearIsStable() {
        // 1 January 2025 in Zurich is stored as 2024-12-31T23:00:00Z. Read with
        // Calendar.current on a machine west of UTC that is 2024; the pinned
        // calendar must still say 2025.
        let newYear = FiscalCalendar.yearBounds(2025).start
        #expect(FiscalCalendar.year(of: newYear) == 2025)

        let lastMoment = FiscalCalendar.yearBounds(2025).end.addingTimeInterval(-1)
        #expect(FiscalCalendar.year(of: lastMoment) == 2025)

        // The bounds are half-open and contiguous.
        #expect(FiscalCalendar.yearBounds(2025).end == FiscalCalendar.yearBounds(2026).start)
    }
}

@Suite("Annual report figures")
struct ReportGeneratorTests {

    @Test("category rows add up to the totals printed beneath them")
    func rowsSumToTotals() {
        let context = makeContext()
        // Amounts chosen so the raw sum and the sum of rounded rows differ.
        let transactions = [
            makeTransaction(in: context, amount: 1000.0 / 3.0, type: "Income", category: "A", year: 2025),
            makeTransaction(in: context, amount: 1000.0 / 3.0, type: "Income", category: "B", year: 2025),
            makeTransaction(in: context, amount: 1000.0 / 3.0, type: "Income", category: "C", year: 2025),
            makeTransaction(in: context, amount: 10.005, type: "Expense", category: "X", year: 2025),
            makeTransaction(in: context, amount: 20.005, type: "Expense", category: "Y", year: 2025),
        ]

        let report = ReportGenerator(transactions: transactions, assets: [], targetYear: 2025)

        #expect(report.totalIncome == Money.sumOfRounded(report.incomeByCategory.map(\.total)))
        #expect(report.totalExpenses == Money.sumOfRounded(report.expensesByCategory.map(\.total)))
        #expect(report.netProfit == Money.roundToCents(report.totalIncome - report.totalExpenses))
    }

    @Test("depreciation reaches the expense side exactly once")
    func depreciationCountedOnce() {
        let context = makeContext()
        let asset = makeAsset(in: context, price: 1_000, rate: 20, linear: true, purchasedIn: 2025)
        let report = ReportGenerator(transactions: [], assets: [asset], targetYear: 2025)

        #expect(report.totalDepreciation == 200)
        let depreciationRow = report.expensesByCategory
            .first { $0.category == ReportGenerator.depreciationCategory }
        #expect(depreciationRow?.total == 200)
        #expect(report.totalExpenses == 200)
    }

    @Test("mileage is summed only from the car-expenses category")
    func mileage() {
        let context = makeContext()
        let transactions = [
            makeTransaction(in: context, amount: 50, type: "Expense",
                            category: ReportGenerator.carExpensesCategory, year: 2025, kilometers: 120),
            makeTransaction(in: context, amount: 50, type: "Expense",
                            category: ReportGenerator.carExpensesCategory, year: 2025, kilometers: 80),
            makeTransaction(in: context, amount: 50, type: "Expense",
                            category: "Office", year: 2025, kilometers: 999),
        ]
        let report = ReportGenerator(transactions: transactions, assets: [], targetYear: 2025)
        #expect(report.totalCarKilometers == 200)
    }

    @Test("an uncategorised entry is grouped rather than dropped")
    func uncategorisedIsGrouped() {
        let context = makeContext()
        let blank = makeTransaction(in: context, amount: 100, type: "Expense", category: "", year: 2025)
        let report = ReportGenerator(transactions: [blank], assets: [], targetYear: 2025)

        #expect(report.totalExpenses == 100)
        #expect(report.expensesByCategory.map(\.category) == [ReportGenerator.uncategorizedExpense])
    }

    @Test("the balance sheet's two sides agree")
    func balanceSheetBalances() {
        let context = makeContext()
        let asset = makeAsset(in: context, price: 5_000, rate: 40, linear: false, purchasedIn: 2025)
        var report = ReportGenerator(transactions: [], assets: [asset], targetYear: 2025)
        report.liquidAssets = 12_345.67
        report.liabilities = 2_000

        #expect(report.totalAktiven == Money.roundToCents(12_345.67 + report.totalAssetBookValue))
        #expect(
            abs(report.totalAktiven - (report.totalPassiven + report.eigenkapital)) < 0.001,
            "Aktiven must equal Passiven plus Eigenkapital"
        )
    }
}
