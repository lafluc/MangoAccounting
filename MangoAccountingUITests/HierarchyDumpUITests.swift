//
//  HierarchyDumpUITests.swift
//
//  Diagnostic only: prints the accessibility tree so test queries are written
//  against what the app actually exposes rather than a guess.
//

import XCTest

final class HierarchyDumpUITests: UITestCase {

    private func dump(_ label: String) {
        print("\n===== HIERARCHY \(label) =====")
        print(app.debugDescription)
        print("===== END \(label) =====\n")
    }

    func testDumpAfterAssetRowClick() throws {
        openTab("Assets")
        let row = rowButton(containing: UITestCase.seededAssetName)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        Thread.sleep(forTimeInterval: 2)
        dump("AFTER-ASSET-ROW-CLICK")
    }

    func testDumpAfterTabOrderLinkClick() throws {
        openTab("Settings")
        let link = app.buttons["Customize Tab Order"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()
        Thread.sleep(forTimeInterval: 2)
        dump("AFTER-TAB-ORDER-CLICK")
    }

    func testDumpAfterDashboardRowClick() throws {
        openTab("Dashboard")
        app.buttons["All Time"].firstMatch.click()
        let row = rowButton(containing: "Studio rent")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        Thread.sleep(forTimeInterval: 2)
        dump("AFTER-DASHBOARD-ROW-CLICK")
    }

    func testDumpOpenContextMenu() throws {
        openTab("Transactions")
        let row = rowButton(containing: "Studio rent")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        Thread.sleep(forTimeInterval: 2)
        dump("CONTEXT-MENU-OPEN")
    }

    func testDumpAfterDeletingATransaction() throws {
        openTab("Transactions")
        let row = rowButton(containing: "Studio rent")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()
        contextMenuItem("Delete").click()
        Thread.sleep(forTimeInterval: 2)
        dump("AFTER-DELETE-MENU-CLICK")
    }

    func testDumpAfterSavingAnInvoice() throws {
        openTab("New Invoice")
        fillMinimalInvoice()
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Generate'")).firstMatch.click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 20), "no preview")
        dump("INVOICE-PREVIEW")
        app.buttons["Save"].firstMatch.click()
        Thread.sleep(forTimeInterval: 3)
        openTab("Saved")
        Thread.sleep(forTimeInterval: 2)
        dump("SAVED-AFTER-INVOICE")
    }
}
