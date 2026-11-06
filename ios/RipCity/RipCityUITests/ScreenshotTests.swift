//  ScreenshotTests.swift — walks the main screens against a local
//  `wrangler dev` and saves screenshots. Skipped unless RIPCITY_TOKEN is set:
//    TEST_RUNNER_RIPCITY_BASE=http://127.0.0.1:8799 TEST_RUNNER_RIPCITY_TOKEN=… \
//    TEST_RUNNER_RIPCITY_SHOTS=/some/dir xcodebuild test -only-testing:RipCityUITests …

import XCTest

final class ScreenshotTests: XCTestCase {
    private var shots: String { ProcessInfo.processInfo.environment["RIPCITY_SHOTS"] ?? NSTemporaryDirectory() }
    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: shots).appendingPathComponent(name + ".png"))
    }

    func testWalkThrough() throws {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["RIPCITY_TOKEN"] else { throw XCTSkip("needs a local server") }
        let app = XCUIApplication()
        app.launchEnvironment["RIPCITY_TOKEN"] = token
        app.launchEnvironment["RIPCITY_BASE"] = env["RIPCITY_BASE"] ?? "http://127.0.0.1:8799"
        app.launch()
        XCTAssertTrue(app.staticTexts["Season leaderboard".uppercased()].waitForExistence(timeout: 10))
        shot("01-home")

        app.buttons["Menu"].tap(); sleep(1); shot("02-menu-open")
        app.buttons["Yearbook"].tap(); sleep(3); shot("03-yearbook")
        XCTAssertTrue(app.staticTexts["YEARBOOK"].waitForExistence(timeout: 5), "menu opens the yearbook")
        app.buttons["Number 91, Sidy Cissoko"].tap(); sleep(1); shot("04-yearbook-91")

        app.buttons["Menu"].tap(); sleep(1)
        app.buttons["Standings"].tap(); sleep(1); shot("05-standings")

        app.buttons["Menu"].tap(); sleep(1)
        app.buttons["Tonight"].tap(); sleep(1); shot("06-cards")
        let card = app.otherElements.containing(.staticText, identifier: "WHO WINS? · STRAIGHT UP").firstMatch
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 260, dy: 0)))
        sleep(1); shot("07-after-swipe")
        _ = card
        if app.buttons["List"].exists { app.buttons["List"].tap(); sleep(1); shot("08-list") }
    }
}
