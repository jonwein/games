import XCTest

/// Plays a game the way you would: tap it, tap Share in the game, and land back on the list with the result in.
@MainActor
final class PlayFlowTests: XCTestCase {
    /// A stand-in game page with a Share button that shares a result, like most daily games.
    private static let gamePage = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="font: 24px -apple-system; padding: 40px">
        <h1>Test Game</h1>
        <button style="font-size: 24px" onclick="navigator.share({ text: 'Test Game #12 3/6\\n\\n🟩🟩🟩' })">Share result</button>
        </body></html>
        """

    private func launch() -> XCUIApplication {
        let url = "data:text/html;charset=utf-8;base64," + Data(Self.gamePage.utf8).base64EncodedString()
        let games = [["id": "test", "name": "Test Game", "url": url], ["id": "other", "name": "Other Game", "url": url]]
        let app = XCUIApplication()
        app.launchEnvironment["DAILYGAMES_TEST_GAMES"] = String(data: try! JSONSerialization.data(withJSONObject: games), encoding: .utf8)
        app.launch()
        return app
    }

    func testSharingInTheGameAddsTheResult() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Send 0/2"].waitForExistence(timeout: 5))

        app.buttons["Test Game"].firstMatch.tap()
        let share = app.webViews.buttons["Share result"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "the game page should load")
        share.tap()

        // Back on the list, with the result in and the message ready to send.
        XCTAssertTrue(app.staticTexts["Test Game #12 3/6"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Send 1/2"].exists)
        XCTAssertFalse(share.exists)
    }

    func testClosingWithoutAResultChangesNothing() throws {
        let app = launch()
        app.buttons["Other Game"].firstMatch.tap()
        XCTAssertTrue(app.webViews.buttons["Share result"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Send 0/2"].waitForExistence(timeout: 5))
    }
}
