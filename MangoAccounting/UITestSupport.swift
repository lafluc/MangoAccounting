// UITestSupport.swift
//
// Support for driving the app from XCUITest against a known, throwaway database.
//
// Compiled only into Debug: the whole file is inside `#if DEBUG`, so nothing here
// reaches the build that goes to users.

#if DEBUG

import CoreData
import Foundation

enum UITestSupport {

    /// Launch argument that switches the app onto a disposable store.
    static let launchArgument = "-MangoUITestStore"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// A fresh store for each launch, so a test never inherits the previous one's
    /// edits and never touches the user's real container.
    static func makeCleanStoreURL() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MangoUITestStore", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("MangoAccounting.sqlite")
    }

    /// Also clears the archived-document folder and the defaults the tests assert
    /// on, so each run starts from the same place.
    static func resetSupportingState() {
        let documents = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        if let documents {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent("SavedDocuments"))
        }
        for key in ["tabOrder", "appearance", "language", "balanceSheetInputs",
                    "usedCurrencies", "incomeCategories", "expenseCategories",
                    "name", "address", "iban", "uid"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Rows the UI tests assert against. Titles repeat on purpose — that is what
    /// the suggestion chips are built from.
    static func seed(into context: NSManagedObjectContext) {
        let year = FiscalCalendar.year(of: Date())

        func day(_ monthsBack: Int, _ dayOfMonth: Int) -> Date {
            var components = DateComponents()
            components.year = year
            components.month = max(1, 12 - monthsBack)
            components.day = dayOfMonth
            return FiscalCalendar.calendar.date(from: components) ?? Date()
        }

        let rows: [(String, Double, String, String, Date, Double)] = [
            ("Coffee with client", 12.50, "Expense", "Client Entertainment", day(0, 3), 0),
            ("Coffee with client", 18.00, "Expense", "Client Entertainment", day(0, 11), 0),
            ("Coffee with client", 9.80, "Expense", "Client Entertainment", day(0, 19), 0),
            ("Train ticket", 88.00, "Expense", "Car Expenses", day(1, 22), 240),
            ("Studio rent", 1_200.00, "Expense", "Office Supplies", day(0, 1), 0),
            ("Project A milestone", 4_800.00, "Income", "Project A", day(0, 15), 0),
        ]

        for (details, amount, type, category, date, kilometres) in rows {
            let item = TransactionItem(context: context)
            item.id = UUID()
            item.details = details
            item.amount = amount
            item.originalAmount = amount
            item.currencyCode = "CHF"
            item.type = type
            item.category = category
            item.date = date
            item.carKilometers = kilometres
        }

        let asset = AssetItem(context: context)
        asset.id = UUID()
        asset.name = "RED Komodo"
        asset.purchasePrice = 9_500
        asset.originalPrice = 9_500
        asset.currencyCode = "CHF"
        asset.depreciationRate = 30
        asset.isLinear = false
        asset.purchaseDate = day(6, 4)

        try? context.save()

        // Categories the seeded rows use, so the pickers can select them.
        let manager = CategoryManager.shared
        for name in ["Client Entertainment", "Office Supplies"]
        where !manager.expenseCategories.contains(name) {
            manager.expenseCategories.append(name)
        }
        if !manager.incomeCategories.contains("Project A") {
            manager.incomeCategories.append("Project A")
        }
    }
}

#endif
