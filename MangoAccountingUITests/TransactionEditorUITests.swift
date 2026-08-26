//
//  TransactionEditorUITests.swift
//  MangoAccountingUITests
//
//  Guards the reported bug: opening a transaction for editing showed only the
//  Cancel button, because Save was plain content at the bottom of a collapsible
//  stack inside a sheet with no size of its own.
//

import XCTest

final class TransactionEditorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "app did not come to the front")
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAddSheetKeepsSaveReachable() throws {
        let app = launch()

        app.buttons["Transactions"].firstMatch.click()

        // The toolbar's add button.
        let add = app.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "could not find the Add button")
        add.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the add sheet did not open")
        attach(app, "add-sheet")

        // Both controls must be present — the bug was that only Cancel was.
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists, "Cancel is missing")

        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3), "Save is not present in the sheet")
        XCTAssertTrue(save.isHittable, "Save exists but is clipped out of reach")

        app.buttons["Cancel"].firstMatch.click()
    }

    func testEditSheetKeepsUpdateReachable() throws {
        let app = launch()

        // Give the window room first: the list is the sidebar of a split view, and
        // in a short window its rows sit partly below the edge and are unclickable.
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        window.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 1.0)).press(
            forDuration: 0.2,
            thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 2.2, dy: 3.0))
        )

        app.buttons["Transactions"].firstMatch.click()

        // Click near the top of the list rather than matching a row by its text:
        // the sidebar truncates labels, so the accessibility value is unreliable.
        let list = app.outlines.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "the transaction list did not appear")
        XCTAssertGreaterThan(
            list.outlineRows.count, 0,
            "no transaction rows — seed the store before running this test"
        )
        list.outlineRows.element(boundBy: 0).coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()

        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "could not find the Edit button")
        edit.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the edit sheet did not open")
        attach(app, "edit-sheet")

        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists, "Cancel is missing")

        // Labelled Update in edit mode.
        let update = app.buttons["Update"].firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 3), "Update is not present in the edit sheet")
        XCTAssertTrue(update.isHittable, "Update exists but is clipped out of reach")

        app.buttons["Cancel"].firstMatch.click()
    }

    /// The original failure only showed up once the window was small enough that
    /// the sheet had to compress, so squeeze it deliberately.
    func testSaveSurvivesASmallWindow() throws {
        let app = launch()
        app.buttons["Transactions"].firstMatch.click()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        // Drag the bottom-right corner as far up and left as the window allows.
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 1.0))
        corner.press(
            forDuration: 0.2,
            thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.05))
        )

        let add = app.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.click()

        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        attach(app, "add-sheet-small-window")

        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3), "Save vanished when the window was squeezed")
        XCTAssertTrue(save.isHittable, "Save was clipped when the window was squeezed")
    }
}
