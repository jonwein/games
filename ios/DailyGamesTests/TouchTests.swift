import Foundation
import Testing
import WebKit
@testable import DailyGames

/// Checks Touch.js: game pages don't zoom, and taps don't select text, except in text fields.
@MainActor
struct TouchTests {
    private func page(viewport: String) async throws -> GamePage {
        let page = GamePage(url: nil)
        let html = """
            <!doctype html><html><head><meta name="viewport" content="\(viewport)"></head>
            <body><p>Tap here</p><input><p class="own">Selectable</p>
            <style>.own { -webkit-user-select: text }</style></body></html>
            """
        page.webView.loadHTMLString(html, baseURL: URL(string: "https://example.com/"))
        for _ in 0..<200 where page.webView.isLoading || page.webView.url == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        return page
    }

    private func value(_ page: GamePage, _ script: String) async throws -> String? {
        try await page.webView.callAsyncJavaScript(script, contentWorld: .page) as? String
    }

    @Test func phonePagesDoNotZoom() async throws {
        let page = try await page(viewport: "width=device-width, initial-scale=1")
        #expect(try await value(page, #"return document.querySelector("meta[name=viewport]").content"#)
            == "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no")
        #expect(try await value(page, "return getComputedStyle(document.documentElement).touchAction") == "manipulation")
    }

    @Test func pagesThatSetTheirOwnZoomKeepIt() async throws {
        let page = try await page(viewport: "width=device-width, maximum-scale=5")
        #expect(try await value(page, #"return document.querySelector("meta[name=viewport]").content"#)
            == "width=device-width, maximum-scale=5")
    }

    @Test func onlyTextFieldsSelect() async throws {
        let page = try await page(viewport: "width=device-width")
        let select = { (selector: String) in
            try await self.value(page, #"return getComputedStyle(document.querySelector("\#(selector)")).webkitUserSelect"#)
        }
        #expect(try await select("p") == "none")
        #expect(try await select("input") == "text")
        #expect(try await select(".own") == "text")
    }
}
