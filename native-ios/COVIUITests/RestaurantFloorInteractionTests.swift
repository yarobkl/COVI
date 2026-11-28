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

    func testAllEightTablesRemainTouchableWithTheSummaryOpen() {
        let app = launch("restaurant-floor-plan")
        let start = app.buttons["Prendre une commande"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertTrue(start.isHittable)
        for number in [1, 2, 3, 4, 5, 6, 8, 10] {
            let table = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Table \(number), ")).firstMatch
            XCTAssertTrue(table.isHittable, "Table \(number) doit rester accessible")
        }
        let roomOptions = app.buttons["Gérer les espaces"]
        XCTAssertTrue(roomOptions.exists)
        for status in ["Disponible (5)", "Occupée (1)", "En service (1)", "À encaisser (1)"] {
            let filter = app.buttons[status]
            XCTAssertTrue(filter.isHittable, status)
            XCTAssertGreaterThanOrEqual(filter.frame.minY, roomOptions.frame.maxY,
                                        "\(status) doit être entièrement sous le sélecteur de salle")
        }
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Table 1, ")).firstMatch
        first.tap()
        XCTAssertTrue(app.staticTexts["Table 1"].exists)
        XCTAssertTrue(start.isHittable)
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
