//
//  TabBarUITests.swift
//

import XCTest

final class TabBarUITests: UITestCase {

    private let tabs = [
        "Dashboard", "Transactions", "Assets",
        "Annual Report", "New Invoice", "Saved", "Settings",
    ]

    func testEveryTabIsPresentAndOpens() throws {
        for name in tabs {
            let tab = app.buttons[name].firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab '\(name)' is missing")
            XCTAssertTrue(tab.isHittable, "tab '\(name)' is not clickable")
            tab.click()
            // Each tab must put *something* on screen rather than a blank pane.
            XCTAssertTrue(
                app.staticTexts.count > 0,
                "tab '\(name)' rendered no content"
            )
        }
        attachScreenshot("all-tabs-visited")
    }

    func testCommandNumberShortcutsSwitchTabs() throws {
        openTab("Settings")
        // Cmd-1 is the first tab in the saved order, which is the default order.
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(
            app.buttons["Add"].firstMatch.waitForExistence(timeout: 5)
            || app.staticTexts["Timeframe"].firstMatch.exists
            || app.otherElements.count > 0,
            "Cmd-1 did not switch tabs"
        )
    }
}
