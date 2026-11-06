import AppKit
import WebKit
import Observation
import ShopdeckCore

@MainActor @Observable final class AdminBrowserSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView
    let home: URL
    var progress: Double = 0
    var loading = false
    var canGoBack = false
    var canGoForward = false
    var location = ""
    var error: String?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    init(shop: Shop, url:URL? = nil) throws {
        home = try url ?? ShopLinks.administration(shop)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: shop.id)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in Task { @MainActor in self?.progress = view.estimatedProgress } },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in Task { @MainActor in self?.loading = view.isLoading } },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in Task { @MainActor in self?.canGoBack = view.canGoBack } },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in Task { @MainActor in self?.canGoForward = view.canGoForward } },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in Task { @MainActor in self?.location = view.url?.absoluteString ?? "" } }
        ]
        webView.load(URLRequest(url: home))
    }
    func reload() { error = nil; webView.reload() }
    func goHome() { error = nil; webView.load(URLRequest(url: home)) }
    func openInBrowser() { NSWorkspace.shared.open(webView.url ?? home) }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { error = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { if (failure as NSError).code != NSURLErrorCancelled { error = failure.localizedDescription } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) { if (failure as NSError).code != NSURLErrorCancelled { error = failure.localizedDescription } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { error = T("Die Webseite wurde beendet. Lade die Administration erneut.") }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        decisionHandler(["https", "http", "about", "blob"].contains(scheme ?? "") ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection; panel.canChooseDirectories = parameters.allowsDirectories; panel.canChooseFiles = true
        panel.begin { response in completionHandler(response == .OK ? panel.urls : nil) }
    }
}

@MainActor final class AdminBrowserStore {
    private var sessions: [UUID: AdminBrowserSession] = [:]
    private var urls: [UUID: String] = [:]
    private var recent: [UUID] = []
    func session(for shop: Shop) throws -> AdminBrowserSession {
        if sessions[shop.id] == nil || urls[shop.id] != shop.url { sessions[shop.id] = try AdminBrowserSession(shop: shop); urls[shop.id] = shop.url }
        recent.removeAll { $0 == shop.id }; recent.append(shop.id)
        while recent.count > 3 { let expired = recent.removeFirst(); sessions[expired]?.webView.stopLoading(); sessions[expired] = nil; urls[expired] = nil }
        return sessions[shop.id]!
    }
}
