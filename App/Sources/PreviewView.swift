import AppKit
import UniformTypeIdentifiers
import WebKit

/// The rendered view. One web view per window is loaded once with a shell page,
/// then updated in place, which avoids WebKit's page-load cost on every render.
final class PreviewView: NSView, WKNavigationDelegate {
    static let scheme = "litemd-file"
    private static let shellURL = URL(string: "\(scheme):///")!

    let webView: WKWebView
    private var isShellLoaded = false
    private var isHighlighterLoaded = false
    private var current: (html: String, base: String)?

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
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        addSubview(webView)
        webView.loadHTMLString(Self.shellHTML, baseURL: Self.shellURL)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(markdown: String, directory: URL?) {
        current = (MarkdownRenderer.html(from: markdown, sourcePositions: true), directory.map(Self.localURL(for:)) ?? Self.shellURL.absoluteString)
        pushContent()
    }

    private func pushContent() {
        guard isShellLoaded, let current else { return }
        if !isHighlighterLoaded, current.html.contains("<code class=\"language-") {
            webView.evaluateJavaScript(Self.highlighterScript)
            isHighlighterLoaded = true
        }
        webView.callAsyncJavaScript(
            "render(html, base)", arguments: ["html": current.html, "base": current.base], in: nil, in: .page)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isShellLoaded = true
        isHighlighterLoaded = false
        pushContent()
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if action.navigationType != .linkActivated {
            // Only the shell page itself may load; content can't navigate the view away.
            return decisionHandler(url == Self.shellURL ? .allow : .cancel)
        }
        decisionHandler(.cancel)
        openLink(url)
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

    private static func resource(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static let highlighterScript = resource("highlight.min", "js")

    // Document content can't run script: innerHTML never executes <script>, and the
    // CSP blocks inline handlers. Only the nonce'd shell script and injected code run.
    private static let shellHTML = """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(scheme): https: http: data:; media-src \(scheme): https:; style-src 'unsafe-inline'; script-src 'nonce-shell'">
        <base href="\(shellURL.absoluteString)">
        <style>
        \(MarkdownRenderer.stylesheet)
        \(resource("hljs-light", "css"))
        @media (prefers-color-scheme: dark) { \(resource("hljs-dark", "css")) }
        pre code.hljs { padding: 0; background: transparent; }
        li > input[type="checkbox"] { cursor: pointer; }
        </style>
        </head><body><article class="markdown-body" id="content"></article>
        <script nonce="shell">
        function render(html, base) {
          document.querySelector('base').href = base;
          const content = document.getElementById('content');
          content.innerHTML = html;
          if (window.hljs) {
            content.querySelectorAll('pre code[class*="language-"]').forEach(block => hljs.highlightElement(block));
          }
          content.querySelectorAll('li[data-sourcepos] > input[type="checkbox"]').forEach(box => box.disabled = false);
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
