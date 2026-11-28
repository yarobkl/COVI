import XCTest

@MainActor
final class RestaurantFloorInteractionTests: XCTestCase {
    func testCancelThenConfirmOpensTheComposerForTheSelectedTable() {
        let app = launch("restaurant-floor-plan")
        let start = app.buttons["Prendre une commande"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let confirm = app.buttons["Confirmer"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        app.buttons["Annuler"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()

        XCTAssertTrue(app.navigationBars["Commander · Table 10"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["Ajouter une unité de Poulet braisé"].exists)
    }

    func testCheckoutButtonOpensTheBillForTheSelectedTable() {
        let app = launch("restaurant-floor-checkout")
        let checkout = app.buttons["Encaisser"]
        XCTAssertTrue(checkout.waitForExistence(timeout: 15))
        checkout.tap()

        XCTAssertTrue(app.staticTexts["Encaissement · Table 6"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Confirmer le solde"].exists)
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--covi-diagnostic-scenario", scenario, "--covi-diagnostic-interactive",
            "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR",
        ]
        app.launch()
        return app
    }
}
