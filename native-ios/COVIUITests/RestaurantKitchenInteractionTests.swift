import XCTest

@MainActor
final class RestaurantKitchenInteractionTests: XCTestCase {
    func testActiveTicketCountIsIndependentOfTheSelectedFilter() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--covi-diagnostic-scenario", "restaurant-kitchen", "--covi-diagnostic-interactive",
            "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR",
        ]
        app.launch()

        let activeTickets = app.staticTexts["kitchen-active-ticket-count"]
        XCTAssertTrue(activeTickets.waitForExistence(timeout: 15))
        XCTAssertEqual(activeTickets.label, "3 tickets actifs")
        XCTAssertEqual(app.buttons["Mes espaces"].value as? String, "Le Brazza Grill, Restaurant")

        let ready = app.buttons["Prêts (1)"]
        XCTAssertTrue(ready.isHittable)
        ready.tap()
        XCTAssertTrue(app.buttons["Marquer servi"].waitForExistence(timeout: 8))
        XCTAssertEqual(activeTickets.label, "3 tickets actifs")

        app.buttons["Marquer servi"].tap()
        XCTAssertTrue(app.staticTexts["Aucun ticket"].waitForExistence(timeout: 8))
        XCTAssertEqual(activeTickets.label, "3 tickets actifs")
    }
}
