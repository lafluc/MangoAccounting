//
//  UITestCase.swift
//  MangoAccountingUITests
//
//  Shared harness. Every test launches the app against a disposable, seeded
//  store (see UITestSupport in the app target) so runs are reproducible and the
//  user's real database is never touched.
//

import XCTest

class UITestCase: XCTestCase {

    var app: XCUIApplication!

    /// Titles the seeded store contains, for assertions.
    static let seededTitles = [
        "Coffee with client", "Train ticket", "Studio rent", "Project A milestone",
    ]
    static let seededAssetName = "RED Komodo"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MangoUITestStore"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "app never came to the front")
        resizeWindow(width: 1440, height: 940)
    }

    override func tearDownWithError() throws {
        if let app, app.state == .runningForeground {
            app.terminate()
        }
        app = nil
    }

    // MARK: - Helpers

    /// A generous window, so nothing under test is off-screen or unhittable.
    func resizeWindow(width: CGFloat, height: CGFloat) {
        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: 10) else { return }
        let current = window.frame
        guard current.width > 0, current.height > 0 else { return }
        let dx = width / current.width
        let dy = height / current.height
        window.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 1.0)).press(
            forDuration: 0.1,
            thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
        )
    }

    func openTab(_ name: String) {
        let tab = app.buttons[name].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab '\(name)' is missing from the tab bar")
        tab.click()
    }

    /// Asserts a control exists and can actually be clicked, which is the failure
    /// the Save button had: present in the hierarchy but clipped out of reach.
    @discardableResult
    func assertUsable(_ element: XCUIElement, _ description: String,
                      file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(description) does not exist", file: file, line: line)
            return false
        }
        XCTAssertTrue(element.isHittable, "\(description) exists but is not clickable", file: file, line: line)
        return element.isHittable
    }

    /// A button inside the frontmost alert or sheet.
    ///
    /// `app.buttons[...]` searches the whole application, which can resolve to a
    /// Touch Bar element that XCUITest then refuses to click.
    func dialogButton(_ label: String) -> XCUIElement {
        let inSheet = app.sheets.firstMatch.buttons[label].firstMatch
        if inSheet.exists { return inSheet }
        let inDialog = app.dialogs.firstMatch.buttons[label].firstMatch
        if inDialog.exists { return inDialog }
        return app.windows.firstMatch.buttons[label].firstMatch
    }

    /// Waits for a confirmation alert carrying the given button.
    func waitForConfirmation(_ label: String, timeout: TimeInterval = 8) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let button = dialogButton(label)
            if button.exists && button.isHittable { return button }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return dialogButton(label)
    }

    /// An item in the context menu that is currently open.
    ///
    /// `app.menuItems["Delete"]` is ambiguous: the menu bar has its own
    /// Edit ▸ Delete, which is disabled and off-screen, and `firstMatch` picks
    /// that one — so the click silently does nothing. The pop-up menu lives under
    /// the window, so scoping there resolves the right item.
    func contextMenuItem(_ title: String) -> XCUIElement {
        let scoped = app.windows.firstMatch.menuItems[title].firstMatch
        if scoped.waitForExistence(timeout: 3) { return scoped }
        return app.menuItems.matching(
            NSPredicate(format: "title == %@ AND enabled == YES", title)
        ).firstMatch
    }

    func sheet(timeout: TimeInterval = 5) -> XCUIElement {
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: timeout), "no sheet opened")
        return sheet
    }

    func dismissSheet() {
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.click()
        } else {
            let close = app.buttons["Close"].firstMatch
            if close.exists && close.isHittable { close.click() }
        }
        XCTAssertTrue(
            app.sheets.firstMatch.waitForNonExistence(timeout: 5),
            "the sheet did not close"
        )
    }

    func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The transaction list's rows.
    var transactionRows: XCUIElementQuery {
        app.outlines.firstMatch.outlineRows
    }

    /// The clickable control inside a list row.
    ///
    /// SwiftUI exposes each row as a *disabled* `OutlineRow` container wrapping a
    /// button that carries the whole row as one combined label, e.g.
    /// "Expense, Studio rent, Client Entertainment, CHF 9.80, December 19, 2026".
    /// Clicking the row element itself fails as "not hittable"; the button works.
    func rowButton(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// A text field addressed by its placeholder, which is stable where an index
    /// into `app.textFields` is not.
    func field(placeholder: String) -> XCUIElement {
        app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@", placeholder)
        ).firstMatch
    }

    func type(_ text: String, into element: XCUIElement,
              file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("field not found", file: file, line: line)
            return
        }
        element.click()
        element.typeText(text)
    }

    /// Picks a value from a macOS pop-up button.
    func choose(_ option: String, fromPopUpLabelled label: String,
                file: StaticString = #filePath, line: UInt = #line) {
        let popUp = app.popUpButtons.matching(
            NSPredicate(format: "label CONTAINS %@", label)
        ).firstMatch
        guard popUp.waitForExistence(timeout: 5) else {
            XCTFail("no pop-up labelled '\(label)'", file: file, line: line)
            return
        }
        popUp.click()
        let item = app.menuItems[option].firstMatch
        guard item.waitForExistence(timeout: 5) else {
            XCTFail("'\(option)' is not offered by '\(label)'", file: file, line: line)
            app.typeKey(.escape, modifierFlags: [])
            return
        }
        item.click()
    }
}
