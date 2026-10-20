import AppKit
import UniformTypeIdentifiers
import WebKit

/// The rendered view. One web view per window is loaded once with a shell page,
/// then updated in place, which avoids WebKit's page-load cost on every render.
final class PreviewView: NSView, WKNavigationDelegate {
    static let scheme = "litemd-file"
    private static let shellURL = URL(string: "\(scheme):///")!

    let webView: WKWebView
    private let findBar = FindBar()
    private var isShellLoaded = false
    private var isHighlighterLoaded = false
    private var current: (html: String, base: String, scrollToLine: Int?)?

    /// Called with the 1-based source line of a task-list checkbox the user clicked.
    var onToggleTask: ((Int) -> Void)?

    override init(frame: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: Self.scheme)
        let taskHandler = TaskToggleHandler()
        configuration.userContentController.add(taskHandler, name: "toggleTask")
        webView = WKWebView(frame: frame, configuration: configuration)
        super.init(frame: frame)
        taskHandler.onToggle = { [weak self] line in self?.onToggleTask?(line) }
        webView.navigationDelegate = self
        addSubview(webView)
        findBar.isHidden = true
        findBar.onSearch = { [weak self] query, backwards, restart in self?.find(query, backwards: backwards, restart: restart) }
        findBar.onClose = { [weak self] in self?.hideFindBar() }
        addSubview(findBar)
        webView.loadHTMLString(Self.shellHTML, baseURL: Self.shellURL)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let barHeight = findBar.isHidden ? 0 : FindBar.height
        findBar.frame = NSRect(x: 0, y: bounds.height - barHeight, width: bounds.width, height: barHeight)
        webView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - barHeight)
    }

    /// Renders the markdown. With `scrollToLine`, scrolls so that source line is at the top.
    func show(markdown: String, directory: URL?, scrollToLine: Int? = nil) {
        current = (
            MarkdownRenderer.html(from: markdown, sourcePositions: true),
            directory.map(Self.localURL(for:)) ?? Self.shellURL.absoluteString,
            scrollToLine)
        pushContent()
    }

    /// The source line of the first block visible at the top of the view.
    func topVisibleLine(completion: @escaping (Int) -> Void) {
        guard isShellLoaded else { return completion(1) }
        webView.evaluateJavaScript("topLine()") { result, _ in completion(result as? Int ?? 1) }
    }

    private func pushContent() {
        guard isShellLoaded, let current else { return }
        if !isHighlighterLoaded, MarkdownRenderer.needsHighlighter(current.html) {
            webView.evaluateJavaScript(MarkdownRenderer.highlighterScript)
            isHighlighterLoaded = true
        }
        webView.callAsyncJavaScript(
            "render(html, base, line)",
            arguments: ["html": current.html, "base": current.base, "line": current.scrollToLine ?? 0],
            in: nil, in: .page)
        // Scroll once; later re-renders (checkbox clicks, reloads) keep the reader's position.
        self.current?.scrollToLine = nil
    }

    // MARK: - Find

    var isFindBarVisible: Bool { !findBar.isHidden }

    func showFindBar() {
        findBar.isHidden = false
        needsLayout = true
        window?.makeFirstResponder(findBar.field)
        findBar.field.selectText(nil)
    }

    func hideFindBar() {
        guard !findBar.isHidden else { return }
        findBar.isHidden = true
        needsLayout = true
        window?.makeFirstResponder(webView)
    }

    /// Next or previous match for the find bar's text; opens the bar if there's nothing to search for.
    func findAgain(backwards: Bool) {
        guard !findBar.field.stringValue.isEmpty else { return showFindBar() }
        find(findBar.field.stringValue, backwards: backwards, restart: false)
    }

    private func find(_ query: String, backwards: Bool, restart: Bool) {
        guard !query.isEmpty else { return findBar.showNotFound(false) }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        let search = { [weak self] in
            self?.webView.find(query, configuration: configuration) { result in
                self?.findBar.showNotFound(!result.matchFound)
            }
        }
        // While typing, search from the top rather than from the previous match.
        if restart {
            webView.evaluateJavaScript("window.getSelection().removeAllRanges()") { _, _ in search() }
        } else {
            search()
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isShellLoaded = true
        isHighlighterLoaded = false
        pushContent()
    }

    // The async form has the same signature in every SDK, so it can't silently stop matching.
    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if action.navigationType != .linkActivated {
            // Only the shell page itself may load; content can't navigate the view away.
            return url == Self.shellURL ? .allow : .cancel
        }
        openLink(url)
        return .cancel
    }

    private func openLink(_ url: URL) {
        switch url.scheme?.lowercased() {
        case Self.scheme:
            let fileURL = URL(fileURLWithPath: url.path)
            let type = UTType(filenameExtension: fileURL.pathExtension)
            if type?.conforms(to: UTType(importedAs: "net.daringfireball.markdown")) == true {
                NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            } else if let type, type.conforms(to: .content), !type.conforms(to: .executable), !type.conforms(to: .script) {
                NSWorkspace.shared.open(fileURL)
            } else {
                // Don't launch apps or scripts from a link; show them in Finder instead.
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        case "http", "https", "mailto":
            NSWorkspace.shared.open(url)
        default:
            break
        }
    }

    // MARK: - Page assets

    private static func localURL(for directory: URL) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = ""
        components.path = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return components.string ?? shellURL.absoluteString
    }

    // Document content can't run script: innerHTML never executes <script>, and the
    // CSP blocks inline handlers. Only the nonce'd shell script and injected code run.
    private static let shellHTML = """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(scheme): https: http: data:; media-src \(scheme): https:; style-src 'unsafe-inline'; script-src 'nonce-shell'">
        <base href="\(shellURL.absoluteString)">
        <style>
        \(MarkdownRenderer.stylesheet)
        \(MarkdownRenderer.highlightStylesheet)
        li > input[type="checkbox"] { cursor: pointer; }
        </style>
        </head><body><article class="markdown-body" id="content"></article>
        <script nonce="shell">
        function render(html, base, line) {
          document.querySelector('base').href = base;
          const content = document.getElementById('content');
          content.innerHTML = html;
          if (window.hljs) { \(MarkdownRenderer.highlightCall) }
          content.querySelectorAll('li[data-sourcepos] > input[type="checkbox"]').forEach(box => box.disabled = false);
          if (line > 0) scrollToLine(line);
        }
        function startLine(element) { return parseInt(element.dataset.sourcepos, 10); }
        // Scrolls to the last block starting at or before the line. Blocks are in source order.
        function scrollToLine(line) {
          let target = null;
          for (const element of document.querySelectorAll('#content [data-sourcepos]')) {
            if (startLine(element) > line) break;
            target = element;
          }
          if (target) target.scrollIntoView({ block: 'start' }); else window.scrollTo(0, 0);
        }
        // The first innermost block still visible at the top of the view.
        function topLine() {
          for (const element of document.querySelectorAll('#content [data-sourcepos]')) {
            if (element.getBoundingClientRect().bottom <= 0) continue;
            if (element.querySelector('[data-sourcepos]')) continue;
            return startLine(element);
          }
          return 1;
        }
        document.addEventListener('change', event => {
          const item = event.target.closest('li[data-sourcepos]');
          if (event.target.type !== 'checkbox' || !item) return;
          window.webkit.messageHandlers.toggleTask.postMessage(parseInt(item.dataset.sourcepos, 10));
        });
        document.addEventListener('click', event => {
          const link = event.target.closest('a[href^="#"]');
          if (!link) return;
          event.preventDefault();
          document.getElementById(decodeURIComponent(link.getAttribute('href').slice(1)))?.scrollIntoView();
        });
        </script>
        </body></html>
        """
}

/// Receives checkbox clicks. A separate object, because the content controller retains its handlers.
private final class TaskToggleHandler: NSObject, WKScriptMessageHandler {
    var onToggle: ((Int) -> Void)?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let line = message.body as? Int, line > 0 else { return }
        onToggle?(line)
    }
}

/// Serves images next to the document (relative `![](img.png)` paths) to the web view.
private final class LocalImageSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let fileURL = URL(fileURLWithPath: url.path)
        guard let type = UTType(filenameExtension: fileURL.pathExtension),
              type.conforms(to: .image) || type.conforms(to: .audiovisualContent),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        task.didReceive(URLResponse(
            url: url, mimeType: type.preferredMIMEType, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
