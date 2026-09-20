//
//  AssetsAndSettingsUITests.swift
//

import XCTest

final class AssetsUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openTab("Assets")
    }

    func testSeededAssetIsListedAndAddIsUsable() throws {
        // Like transaction rows, an asset row is a button carrying the whole row
        // as one combined label.
        XCTAssertTrue(
            rowButton(containing: UITestCase.seededAssetName).waitForExistence(timeout: 10),
            "the seeded asset is not listed"
        )
        assertUsable(app.buttons["Add"].firstMatch, "the Add asset button")
        attachScreenshot("assets-list")
    }

    /// Two `.sheet` modifiers were stacked here, so only one of Add and Edit
    /// could ever open.
    func testAddAssetSheetOpens() throws {
        app.buttons["Add"].firstMatch.click()
        let sheet = sheet()

        assertUsable(app.buttons["Cancel"].firstMatch, "Cancel in the add-asset sheet")
        assertUsable(app.buttons["Save Asset"].firstMatch, "Save Asset")
        XCTAssertTrue(sheet.textFields.count >= 2, "the asset form is missing fields")
        XCTAssertTrue(sheet.datePickers.count >= 1, "the purchase-date picker is missing")
        XCTAssertTrue(sheet.checkBoxes["Linear Depreciation"].exists
                      || sheet.switches["Linear Depreciation"].exists,
                      "the linear-depreciation toggle is missing")
        attachScreenshot("add-asset-sheet")
        dismissSheet()
    }

    func testEditAssetSheetOpensPopulated() throws {
        let row = rowButton(containing: UITestCase.seededAssetName)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        _ = sheet()
        assertUsable(app.buttons["Update Asset"].firstMatch, "Update Asset")
        let name = field(placeholder: "Asset Name (e.g., RED Komodo)")
        XCTAssertEqual(name.value as? String, UITestCase.seededAssetName,
                       "the edit sheet did not load the asset")
        assertUsable(app.buttons["Delete Asset"].firstMatch, "Delete Asset inside the editor")
        attachScreenshot("edit-asset-sheet")
        dismissSheet()
    }

    /// Editing a 30% degressive asset and saving must leave it 30% degressive.
    /// Assigning the matched class used to fire the picker's onChange and rewrite
    /// the rate.
    func testEditingAnAssetDoesNotRewriteItsRate() throws {
        let row = rowButton(containing: UITestCase.seededAssetName)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        _ = sheet()

        app.buttons["Update Asset"].firstMatch.click()
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5))

        // The row's combined label carries "Degressive • 30.0%". Opening and
        // saving used to rewrite that to 40% linear.
        let unchanged = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Degressive' AND label CONTAINS '30'")
        ).firstMatch
        XCTAssertTrue(unchanged.waitForExistence(timeout: 5),
                      "the asset's rate or method changed after an untouched edit")
        attachScreenshot("asset-after-roundtrip")
    }

    func testDeleteAssetAsksFirst() throws {
        let row = rowButton(containing: UITestCase.seededAssetName)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.rightClick()

        let delete = contextMenuItem("Delete Asset")
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no Delete item in the asset context menu")
        delete.click()

        let cancel = waitForConfirmation("Cancel")
        XCTAssertTrue(cancel.exists, "deleting an asset did not ask for confirmation")
        attachScreenshot("asset-delete-confirmation")
        cancel.click()

        XCTAssertTrue(rowButton(containing: UITestCase.seededAssetName).exists,
                      "cancelling still removed the asset")
    }
}

final class SettingsUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openTab("Settings")
    }

    func testBusinessDetailFieldsAreEditable() throws {
        let name = field(placeholder: "Name")
        type("Test Issuer", into: name)
        XCTAssertEqual(name.value as? String, "Test Issuer", "the name field did not accept input")
        for placeholder in ["Address", "UID (CHE-...)", "IBAN (CH…)"] {
            XCTAssertTrue(field(placeholder: placeholder).exists,
                          "the '\(placeholder)' field is missing from Settings")
        }
        attachScreenshot("settings")
    }

    func testLanguagePickerHasAllThreeLanguages() throws {
        for language in ["English", "German", "Oberfränkisch"] {
            XCTAssertTrue(
                app.radioButtons[language].firstMatch.waitForExistence(timeout: 5),
                "the \(language) option is missing from the language picker"
            )
        }
    }

    func testAppearancePickerSwitchesTheApp() throws {
        for option in ["System", "Light", "Dark"] {
            XCTAssertTrue(
                app.radioButtons[option].firstMatch.waitForExistence(timeout: 5),
                "the \(option) appearance option is missing"
            )
        }

        app.radioButtons["Light"].firstMatch.click()
        XCTAssertEqual(app.radioButtons["Light"].firstMatch.value as? Int, 1,
                       "selecting Light did not take effect")
        attachScreenshot("settings-light")

        app.radioButtons["Dark"].firstMatch.click()
        XCTAssertEqual(app.radioButtons["Dark"].firstMatch.value as? Int, 1,
                       "selecting Dark did not take effect")
        attachScreenshot("settings-dark")
    }

    /// The tab-order editor was gated to iOS even though macOS is the only
    /// platform that uses the custom tab bar.
    func testTabOrderEditorIsReachable() throws {
        let link = app.buttons["Customize Tab Order"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "the tab-order link is missing on macOS")
        link.click()
        XCTAssertTrue(
            app.staticTexts["Customize Tab Order"].firstMatch.waitForExistence(timeout: 5)
            || app.outlines.firstMatch.waitForExistence(timeout: 5),
            "the tab-order editor did not open"
        )
        attachScreenshot("tab-order")
    }
}
