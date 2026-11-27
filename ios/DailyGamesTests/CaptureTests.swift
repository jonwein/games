import Foundation
import Testing
import WebKit
@testable import DailyGames

/// Checks Capture.js hands over what a game shares or copies, in each of the ways games do it.
@MainActor
struct CaptureTests {
    private func page(_ body: String = "") async throws -> (GamePage, () -> [GamePage.Capture]) {
        let page = GamePage(url: nil)
        var captures: [GamePage.Capture] = []
        page.onCapture = { captures.append($0) }
        page.webView.loadHTMLString("<!doctype html><html><body>\(body)</body></html>", baseURL: URL(string: "https://example.com/"))
        for _ in 0..<200 where page.webView.isLoading || page.webView.url == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        return (page, { captures })
    }

    private func run(_ page: GamePage, _ script: String) async throws {
        _ = try await page.webView.callAsyncJavaScript(script, contentWorld: .page)
    }

    private func waitFor(_ captures: () -> [GamePage.Capture]) async throws -> GamePage.Capture? {
        for _ in 0..<100 where captures().isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        return captures().first
    }

    @Test func shareSendsTheTextAndLink() async throws {
        let (page, captures) = try await page()
        try await run(page, #"await navigator.share({ title: "Spotle", text: "Spotle #800 🟩", url: "https://spotle.io" })"#)
        let capture = try #require(try await waitFor(captures))
        #expect(capture.kind == .share)
        #expect(capture.text == "Spotle #800 🟩\nhttps://spotle.io")
    }

    @Test func shareDoesNotRepeatALinkAlreadyInTheText() async throws {
        let (page, captures) = try await page()
        try await run(page, #"await navigator.share({ text: "Songless #1 🟩\nhttps://lessgames.com/songless", url: "https://lessgames.com/songless" })"#)
        #expect(try await waitFor(captures)?.text == "Songless #1 🟩\nhttps://lessgames.com/songless")
    }

    @Test func sharingLooksAvailable() async throws {
        let (page, _) = try await page()
        let canShare = try await page.webView.callAsyncJavaScript(
            #"return typeof navigator.share === "function" && navigator.canShare({ text: "x" })"#, contentWorld: .page
        )
        #expect(canShare as? Bool == true)
    }

    @Test func clipboardWriteText() async throws {
        let (page, captures) = try await page()
        try await run(page, #"await navigator.clipboard.writeText("Wordle 1,621 3/6\n\n🟩🟩🟩🟩🟩")"#)
        let capture = try #require(try await waitFor(captures))
        #expect(capture.kind == .copy)
        #expect(capture.text == "Wordle 1,621 3/6\n\n🟩🟩🟩🟩🟩")
    }

    @Test func execCommandCopiesTheSelection() async throws {
        let (page, captures) = try await page(#"<textarea id="t">Krillion #95 🦐 4/6</textarea>"#)
        try await run(page, #"const t = document.getElementById("t"); t.focus(); t.select(); document.execCommand("copy")"#)
        #expect(try await waitFor(captures)?.text == "Krillion #95 🦐 4/6")
    }

    @Test func execCommandCopiesWhatACopyEventSets() async throws {
        let (page, captures) = try await page()
        try await run(page, """
            document.addEventListener("copy", (e) => { e.clipboardData.setData("text/plain", "Perceptle #42 - A (87)"); e.preventDefault(); });
            document.execCommand("copy");
            """)
        #expect(try await waitFor(captures)?.text == "Perceptle #42 - A (87)")
    }
}
