import SwiftUI
import UIKit
import WebKit

/// A game, open in the app. When the game shares or copies something that looks like a result, the browser
/// closes and hands it over, so there's nothing to copy and paste.
struct GameBrowser: View {
    let game: Game
    let onResult: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var page: GamePage
    @State private var passOn: SharedText?
    @State private var finished = false

    init(game: Game, onResult: @escaping (String) -> Void) {
        self.game = game
        self.onResult = onResult
        _page = State(initialValue: GamePage(url: URL(string: game.url)))
    }

    var body: some View {
        NavigationStack {
            WebView(page: page)
                .ignoresSafeArea(.container, edges: .bottom)
                .overlay(alignment: .top) {
                    if page.isLoading {
                        ProgressView(value: page.progress)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                    }
                }
                .overlay {
                    if let failure = page.failure {
                        ContentUnavailableView {
                            Label("Couldn't Open \(game.name)", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(failure)
                        } actions: {
                            Button("Try Again") { page.reload() }
                                .buttonStyle(.borderedProminent)
                        }
                        .background(Color.page)
                    }
                }
                .navigationTitle(game.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .onAppear {
            page.onCapture = handle
            page.start()
        }
        .sheet(item: $passOn) { shared in
            ShareSheet(text: shared.text)
                .presentationDetents([.medium, .large])
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Done") { dismiss() }
                .fontWeight(.semibold)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if page.canGoBack {
                Button { page.goBack() } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel("Back")
            }
            Menu {
                Button { page.reload() } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                if let url = page.currentURL {
                    Button { openURL(url) } label: {
                        Label("Open in Safari", systemImage: "safari")
                    }
                    ShareLink(item: url) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    private func handle(_ capture: GamePage.Capture) {
        guard !finished else { return }
        if Matching.looksLikeResult(capture.text) {
            finished = true
            onResult(capture.text)
            dismiss()
        } else if capture.kind == .share {
            // Not a result, like a link to the game: share it the usual way.
            passOn = SharedText(text: capture.text)
        }
    }
}

private struct SharedText: Identifiable {
    let id = UUID()
    let text: String
}

/// The web view and what the toolbar shows about it.
@Observable
final class GamePage {
    struct Capture {
        enum Kind { case share, copy }
        let kind: Kind
        let text: String
    }

    let startURL: URL?
    private(set) var currentURL: URL?
    private(set) var isLoading = false
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var failure: String?

    @ObservationIgnored var onCapture: (Capture) -> Void = { _ in }
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private lazy var delegate = WebDelegate(page: self)
    @ObservationIgnored private(set) lazy var webView = makeWebView()

    init(url: URL?) {
        startURL = url
        currentURL = url
    }

    func start() {
        guard !started, let startURL else { return }
        started = true
        webView.load(URLRequest(url: startURL))
    }

    func reload() {
        failure = nil
        if webView.url == nil, let startURL {
            webView.load(URLRequest(url: startURL))
        } else {
            webView.reload()
        }
    }

    func goBack() { webView.goBack() }

    fileprivate func received(_ capture: Capture) { onCapture(capture) }

    fileprivate func failed(_ error: Error) {
        let error = error as NSError
        // Stopped on purpose, or handed off to another app.
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain" && error.code == 102 { return }
        failure = error.localizedDescription
    }

    fileprivate func startedLoading() { failure = nil }

    private static let captureScript: String = {
        guard let url = Bundle.main.url(forResource: "Capture", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Look like Safari, so games treat the page as they would there.
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        config.applicationNameForUserAgent = "Version/\(major).0 Mobile/15E148 Safari/604.1"
        config.userContentController.addUserScript(
            WKUserScript(source: Self.captureScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        config.userContentController.add(delegate, name: "dailyGames")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif

        observations = [
            webView.observe(\.estimatedProgress) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.progress = web.estimatedProgress }
            },
            webView.observe(\.isLoading) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.isLoading = web.isLoading }
            },
            webView.observe(\.canGoBack) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.canGoBack = web.canGoBack }
            },
            webView.observe(\.url) { [weak self] web, _ in
                MainActor.assumeIsolated {
                    if let url = web.url { self?.currentURL = url }
                }
            },
        ]
        return webView
    }
}

/// Handles the web view's callbacks. It holds the page weakly, since the web view keeps its script handler alive.
private final class WebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var page: GamePage?

    init(page: GamePage) {
        self.page = page
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let text = body["text"] as? String else { return }
        let kind: GamePage.Capture.Kind = (body["kind"] as? String) == "share" ? .share : .copy
        page?.received(GamePage.Capture(kind: kind, text: text))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return decisionHandler(.allow) }
        if ["http", "https", "about", "blob", "data", "javascript"].contains(scheme) { return decisionHandler(.allow) }
        // mailto:, sms:, app links and the like. Only follow them when you tapped one in the page itself.
        if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame ?? true {
            UIApplication.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        page?.startedLoading()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        page?.failed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        page?.failed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    /// Links that open a new window open in this one instead.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        guard present(alert, from: webView) else { return completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        guard present(alert, from: webView) else { return completionHandler(false) }
    }

    private func present(_ alert: UIAlertController, from webView: WKWebView) -> Bool {
        guard var top = webView.window?.rootViewController else { return false }
        while let next = top.presentedViewController { top = next }
        top.present(alert, animated: true)
        return true
    }
}

struct WebView: UIViewRepresentable {
    let page: GamePage

    func makeUIView(context: Context) -> WKWebView { page.webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

/// The system share sheet, for a share that isn't a result.
struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
