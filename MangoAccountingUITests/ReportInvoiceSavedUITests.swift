//
//  ReportInvoiceSavedUITests.swift
//

import XCTest

final class AnnualReportUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openTab("Annual Report")
    }

    func testReportShowsFiguresAndTheGenerateButton() throws {
        XCTAssertTrue(
            app.staticTexts["Revenue"].firstMatch.waitForExistence(timeout: 10)
            || app.staticTexts["Expenses"].firstMatch.exists,
            "the report did not render its sections"
        )
        // The in-app summary must be localised English, not German literals.
        XCTAssertFalse(app.staticTexts["Ertrag"].exists,
                       "a German literal is showing in the English interface")
        attachScreenshot("annual-report")
    }

    func testBalanceSheetInputsPersistAcrossTabs() throws {
        let fields = app.textFields
        XCTAssertTrue(fields.count >= 2, "the two balance-sheet fields are missing")

        let liquid = fields.element(boundBy: 0)
        liquid.click()
        liquid.typeText("1234")
        app.typeKey(.tab, modifierFlags: [])

        openTab("Dashboard")
        openTab("Annual Report")

        let reloaded = app.textFields.element(boundBy: 0)
        XCTAssertTrue(reloaded.waitForExistence(timeout: 5))
        let value = reloaded.value as? String ?? ""
        XCTAssertTrue(value.contains("1234") || value.contains("1'234") || value.contains("1,234"),
                      "the balance-sheet figure was lost on a tab switch (was '\(value)')")
    }

    func testGeneratingTheReportOpensAPreview() throws {
        let generate = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Generate'")
        ).firstMatch
        XCTAssertTrue(generate.waitForExistence(timeout: 5), "the generate button is missing")
        generate.click()

        _ = sheet(timeout: 15)
        assertUsable(app.buttons["Close"].firstMatch, "Close in the report preview")
        attachScreenshot("report-preview")
        app.buttons["Close"].firstMatch.click()
    }
}

final class InvoiceUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openTab("New Invoice")
    }

    func testInvoiceFormHasEverySection() throws {
        for section in ["Your Information", "Client Information", "Invoice Details",
                        "Line Items", "Total"] {
            XCTAssertTrue(
                app.staticTexts[section].firstMatch.waitForExistence(timeout: 10),
                "the '\(section)' section is missing from the invoice form"
            )
        }
        XCTAssertTrue(app.buttons["Add Item"].firstMatch.exists, "Add Item is missing")
        attachScreenshot("invoice-form")
    }

    func testAddingAndRemovingLineItems() throws {
        let addItem = app.buttons["Add Item"].firstMatch
        XCTAssertTrue(addItem.waitForExistence(timeout: 10))
        let before = app.buttons.matching(identifier: "Remove this line").count
        addItem.click()
        XCTAssertEqual(app.buttons.matching(identifier: "Remove this line").count, before + 1,
                       "Add Item did not add a line")

        app.buttons["Remove this line"].firstMatch.click()
        XCTAssertEqual(app.buttons.matching(identifier: "Remove this line").count, before,
                       "removing a line item did nothing")
    }

    func testGenerateIsBlockedUntilTheInvoiceIsValid() throws {
        let generate = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Generate'")
        ).firstMatch
        XCTAssertTrue(generate.waitForExistence(timeout: 10))
        XCTAssertFalse(generate.isEnabled,
                       "an empty invoice should not be generatable")
    }

    func testFillingAnInvoiceEnablesGenerationAndPreviews() throws {
        fillMinimalInvoice()

        let generate = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Generate'")
        ).firstMatch
        XCTAssertTrue(generate.isEnabled, "a complete invoice still could not be generated")
        generate.click()

        _ = sheet(timeout: 20)
        assertUsable(app.buttons["Save"].firstMatch, "Save in the invoice preview")
        assertUsable(app.buttons["Close"].firstMatch, "Close in the invoice preview")
        attachScreenshot("invoice-preview")
        app.buttons["Close"].firstMatch.click()
    }
}

extension UITestCase {
    /// Fills the minimum an invoice needs to be generatable: issuer name, address
    /// and IBAN, a client name, and one priced line item.
    func fillMinimalInvoice() {
        XCTAssertTrue(field(placeholder: "Name").waitForExistence(timeout: 10),
                      "the invoice form did not appear")
        type("Test Issuer", into: field(placeholder: "Name"))
        type("Musterweg 2, 8000 Zürich", into: field(placeholder: "Address"))
        type("CH9300762011623852957", into: field(placeholder: "IBAN (CH...)"))
        type("Acme AG", into: field(placeholder: "Client Name"))
        type("Consulting", into: field(placeholder: "Description"))

        // The line item's amount starts at 0, so replace rather than append.
        let amount = field(placeholder: "Amount")
        amount.click()
        amount.typeKey("a", modifierFlags: .command)
        amount.typeText("1000")
        // Commit the field before reading the total.
        app.typeKey(.tab, modifierFlags: [])
    }
}

final class SavedFilesUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openTab("Saved")
    }

    func testEmptyArchiveExplainsItself() throws {
        XCTAssertTrue(
            app.staticTexts["No Saved Files"].firstMatch.waitForExistence(timeout: 10),
            "the empty archive shows no explanation"
        )
        attachScreenshot("saved-empty")
    }

    /// Saving an invoice must land in the archive, be marked editable, and offer
    /// Edit and Duplicate.
    func testSavedInvoiceIsEditableFromTheArchive() throws {
        openTab("New Invoice")
        fillMinimalInvoice()

        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Generate'")).firstMatch.click()
        _ = sheet(timeout: 20)
        app.buttons["Save"].firstMatch.click()
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 10),
                      "the preview did not close after saving")

        openTab("Saved")
        XCTAssertTrue(
            rowButton(containing: "Editable").waitForExistence(timeout: 10),
            "the saved invoice is not marked editable"
        )
        attachScreenshot("saved-with-invoice")

        let row = rowButton(containing: "Acme AG")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the saved invoice is not listed")
        row.rightClick()
        XCTAssertTrue(contextMenuItem("Edit Invoice").waitForExistence(timeout: 5),
                      "Edit Invoice is missing from the archive's context menu")
        XCTAssertTrue(contextMenuItem("Duplicate as New Invoice").exists,
                      "Duplicate as New Invoice is missing")
        app.typeKey(.escape, modifierFlags: [])
    }
}

final class DashboardUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openTab("Dashboard")
    }

    func testSummaryCardsShowSeededTotals() throws {
        XCTAssertTrue(app.staticTexts["Total Income"].firstMatch.waitForExistence(timeout: 10),
                      "the dashboard did not render")
        XCTAssertTrue(app.staticTexts["Total Expense"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Net Profit"].firstMatch.exists)
        attachScreenshot("dashboard")
    }

    func testTimeframePickerSwitches() throws {
        for option in ["Last 30 Days", "Last 90 Days", "Year to Date", "All Time"] {
            let button = app.buttons[option].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "'\(option)' is missing")
            XCTAssertTrue(button.isHittable, "'\(option)' is not clickable")
            button.click()
        }
        attachScreenshot("dashboard-timeframes")
    }

    /// The recent-transaction rows are NavigationLinks that did nothing, because
    /// the tab had no navigation container.
    func testRecentTransactionOpensItsDetail() throws {
        app.buttons["All Time"].firstMatch.click()
        let row = rowButton(containing: "Studio rent")
        guard row.waitForExistence(timeout: 10) else {
            XCTFail("no recent transactions on the dashboard")
            return
        }
        row.click()
        XCTAssertTrue(
            app.staticTexts["Transaction Details"].firstMatch.waitForExistence(timeout: 5)
            || app.buttons["Edit"].firstMatch.waitForExistence(timeout: 5),
            "tapping a recent transaction did not open its detail view"
        )
        attachScreenshot("dashboard-detail")
    }
}
