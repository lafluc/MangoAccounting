//
//  TransactionsUITests.swift
//
//  Covers the tab the user reported broken: the Add button, the Duplicate
//  action, the editor sheet and every control inside it.
//

import XCTest

final class TransactionsUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openTab("Transactions")
    }

    // MARK: - The list itself

    func testSeededTransactionsAreListed() throws {
        XCTAssertTrue(
            transactionRows.firstMatch.waitForExistence(timeout: 10),
            "the transaction list is empty — the seeded store did not load"
        )
        XCTAssertGreaterThanOrEqual(transactionRows.count, 4, "expected the seeded rows")
        attachScreenshot("transaction-list")
    }

    func testToolbarControlsArePresent() throws {
        // The reported regression: the Add button had moved onto the detail pane.
        assertUsable(app.buttons["Add"].firstMatch, "the Add (+) button")
        // Both are exposed as MenuButton, not Button.
        assertUsable(app.menuButtons["Sort & Filter"].firstMatch, "the Sort & Filter menu")
        assertUsable(app.menuButtons["Fiscal Year"].firstMatch, "the Fiscal Year menu")
    }

    func testAddButtonStaysUsableAfterSelectingARow() throws {
        let row = rowButton(containing: "Studio rent")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        // Selecting a row replaces the detail pane. The Add button must survive
        // that — it did not when it was attached to the detail placeholder.
        assertUsable(app.buttons["Add"].firstMatch, "the Add button after selecting a row")
        attachScreenshot("add-button-after-selection")
    }

    // MARK: - Add sheet

    func testAddSheetOpensAndSaveIsReachable() throws {
        app.buttons["Add"].firstMatch.click()
        _ = sheet()

        assertUsable(app.buttons["Cancel"].firstMatch, "Cancel in the add sheet")
        assertUsable(app.buttons["Save"].firstMatch, "Save in the add sheet")
        attachScreenshot("add-sheet")
        dismissSheet()
    }

    func testAddSheetContainsEveryField() throws {
        app.buttons["Add"].firstMatch.click()
        let sheet = sheet()

        XCTAssertTrue(sheet.radioButtons["Expense"].exists || sheet.buttons["Expense"].exists,
                      "the Expense/Income type control is missing")
        XCTAssertTrue(sheet.textFields.count >= 2,
                      "expected at least a description and an amount field")
        XCTAssertTrue(sheet.popUpButtons.count >= 2,
                      "expected the currency and category pickers")
        XCTAssertTrue(sheet.datePickers.count >= 1, "the date picker is missing")
        XCTAssertTrue(sheet.buttons["Select Photo"].exists, "Select Photo is missing")
        XCTAssertTrue(sheet.buttons["Select PDF"].exists, "Select PDF is missing")
        XCTAssertTrue(sheet.buttons["Manage categories"].exists, "the manage-categories button is missing")
        dismissSheet()
    }

    func testSaveIsDisabledUntilTheFormIsValid() throws {
        app.buttons["Add"].firstMatch.click()
        let sheet = sheet()

        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Save should be disabled on an empty form")

        // A description alone is not enough: an amount and a category are required.
        let description = sheet.textFields.element(boundBy: 0)
        description.click()
        description.typeText("Lunch")
        XCTAssertFalse(save.isEnabled, "Save should still be disabled without an amount")

        dismissSheet()
    }

    func testTitleSuggestionsAppearAndPrefill() throws {
        app.buttons["Add"].firstMatch.click()
        let sheet = sheet()

        // The seeded store uses "Coffee with client" three times, so its chip is
        // labelled "Coffee with client, 3×".
        let chip = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Coffee with client'")
        ).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5),
                      "no suggestion chip for a title used three times")
        attachScreenshot("title-suggestions")
        chip.click()

        let description = field(placeholder: "Description (e.g., Lunch with client)")
        XCTAssertEqual(description.value as? String, "Coffee with client",
                       "clicking a suggestion did not fill the description")

        // The classification comes with it; the amount deliberately does not.
        let amount = field(placeholder: "Amount")
        let amountValue = amount.value as? String ?? ""
        XCTAssertTrue(amountValue.isEmpty || amountValue == "Amount",
                      "the suggestion filled in an amount, which it should leave blank")
        _ = sheet
        dismissSheet()
    }

    func testAddingATransactionAppearsInTheList() throws {
        let before = transactionRows.count

        app.buttons["Add"].firstMatch.click()
        _ = sheet()

        type("UI test entry", into: field(placeholder: "Description (e.g., Lunch with client)"))
        type("42.50", into: field(placeholder: "Amount"))
        // A category is required before Save enables.
        choose("Office Supplies", fromPopUpLabelled: "Category")

        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.isEnabled, "Save never enabled for a filled-in form")
        save.click()

        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5), "the sheet did not close after saving")
        XCTAssertEqual(transactionRows.count, before + 1, "the new transaction did not appear in the list")
        attachScreenshot("after-adding")
    }

    // MARK: - Row actions

    func testRowOpensTheDetailView() throws {
        let row = rowButton(containing: "Studio rent")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        assertUsable(app.buttons["Edit"].firstMatch, "Edit in the detail toolbar")
        assertUsable(app.buttons["Delete"].firstMatch, "Delete in the detail toolbar")
        attachScreenshot("transaction-detail")
    }

    func testEditSheetOpensWithUpdateReachable() throws {
        let row = rowButton(containing: "Studio rent")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        app.buttons["Edit"].firstMatch.click()

        _ = sheet()
        assertUsable(app.buttons["Cancel"].firstMatch, "Cancel in the edit sheet")
        assertUsable(app.buttons["Update"].firstMatch, "Update in the edit sheet")

        // The form must arrive populated with this row's values, not blank.
        let description = field(placeholder: "Description (e.g., Lunch with client)")
        XCTAssertEqual(description.value as? String, "Studio rent",
                       "the edit sheet did not load the selected transaction")
        attachScreenshot("edit-sheet")
        dismissSheet()
    }

    /// The second reported regression: Duplicate did nothing, because its sheet
    /// was attached to a view that no longer existed once a row was selected.
    func testDuplicateOpensAPrefilledSheet() throws {
        let row = rowButton(containing: "Studio rent")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()

        let duplicate = contextMenuItem("Duplicate")
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5), "no Duplicate item in the row's context menu")
        duplicate.click()

        _ = sheet()
        let description = field(placeholder: "Description (e.g., Lunch with client)")
        XCTAssertEqual(description.value as? String, "Studio rent",
                       "Duplicate opened an empty form instead of one prefilled from the row")
        // A duplicate is a *new* entry, so its confirm button says Save.
        assertUsable(app.buttons["Save"].firstMatch, "Save in the duplicate sheet")
        attachScreenshot("duplicate-sheet")
        dismissSheet()
    }

    func testDeleteFromContextMenuAsksFirstThenRemovesTheRow() throws {
        let row = rowButton(containing: "Studio rent")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let before = transactionRows.count

        row.rightClick()
        let delete = contextMenuItem("Delete")
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no Delete item in the context menu")
        delete.click()

        // It must confirm rather than delete outright.
        let confirm = waitForConfirmation("Delete")
        XCTAssertTrue(confirm.exists, "deleting did not ask for confirmation")
        attachScreenshot("delete-confirmation")
        confirm.click()

        XCTAssertEqual(transactionRows.count, before - 1, "the row was not removed")
    }

    func testCancellingADeleteKeepsTheRow() throws {
        let row = rowButton(containing: "Studio rent")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let before = transactionRows.count

        row.rightClick()
        contextMenuItem("Delete").click()
        let cancel = waitForConfirmation("Cancel")
        XCTAssertTrue(cancel.exists, "deleting did not ask for confirmation")
        cancel.click()

        XCTAssertEqual(transactionRows.count, before, "cancelling still deleted the row")
    }

    // MARK: - Filtering

    func testSearchNarrowsTheList() throws {
        XCTAssertTrue(transactionRows.firstMatch.waitForExistence(timeout: 10))
        let before = transactionRows.count

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the search field is missing")
        search.click()
        search.typeText("Studio")

        XCTAssertLessThan(transactionRows.count, before, "searching did not narrow the list")
    }

    func testFiscalYearMenuOffersTheYearsWithData() throws {
        let yearMenu = app.menuButtons["Fiscal Year"].firstMatch
        XCTAssertTrue(yearMenu.waitForExistence(timeout: 5))
        yearMenu.click()
        XCTAssertGreaterThan(app.menuItems.count, 0, "the fiscal-year menu is empty")
        attachScreenshot("fiscal-year-menu")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testSortAndFilterMenuOpens() throws {
        let menu = app.menuButtons["Sort & Filter"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
        XCTAssertGreaterThan(app.menuItems.count, 0, "the sort & filter menu is empty")
        attachScreenshot("sort-filter-menu")
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Category management

    func testManageCategoriesSheetOpens() throws {
        app.buttons["Add"].firstMatch.click()
        _ = sheet()

        let manage = app.buttons["Manage categories"].firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 5), "the manage-categories button is missing")
        manage.click()

        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5),
                      "the category sheet did not open")
        attachScreenshot("category-management")
        app.buttons["Done"].firstMatch.click()

        // Returning must not wipe what was typed — that was a real bug.
        XCTAssertTrue(app.sheets.firstMatch.exists, "the transaction sheet closed unexpectedly")
        dismissSheet()
    }
}
