import XCTest

/// Regression coverage for swipe-to-switch-tabs (paging TabView +
/// custom tab bar). Swiping must move Today → History → Settings and
/// back, and the tab bar must always reflect the visible page.
final class TabSwipeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.buttons["tab.today"].waitForExistence(timeout: 10),
            "Tab bar should appear after launch"
        )
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testSwipeMovesBetweenTabs() {
        XCTAssertTrue(tabIsSelected("tab.today"), "App should start on Today")

        app.swipeLeft()
        XCTAssertTrue(tabIsSelected("tab.history"), "Swipe left should show History")

        app.swipeLeft()
        XCTAssertTrue(tabIsSelected("tab.settings"), "Swipe left should show Settings")

        app.swipeRight()
        XCTAssertTrue(tabIsSelected("tab.history"), "Swipe right should return to History")
    }

    func testTabBarTapsSelectTabs() {
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(tabIsSelected("tab.settings"))

        app.buttons["tab.today"].tap()
        XCTAssertTrue(tabIsSelected("tab.today"))
    }

    private func tabIsSelected(_ identifier: String, timeout: TimeInterval = 5) -> Bool {
        let element = app.buttons[identifier]
        let predicate = NSPredicate(format: "isSelected == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

