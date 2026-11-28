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

    func testTableOptionsOpenDetailsForTheSelectedTable() {
        let app = launch("restaurant-floor-plan")
        let more = app.buttons["restaurant-floor-table-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()

        let details = app.buttons["Détails de la table"]
        XCTAssertTrue(details.waitForExistence(timeout: 8))
        details.tap()

        XCTAssertTrue(app.navigationBars["Table 10"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Ouvrir une session"].exists)
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
