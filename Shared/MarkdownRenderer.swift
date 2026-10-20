import Foundation
import UniformTypeIdentifiers
import cmark_gfm
import cmark_gfm_extensions

/// Markdown -> HTML via cmark-gfm. Shared by the app and the Quick Look extension.
enum MarkdownRenderer {
    private static let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]
    private static let options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_VALIDATE_UTF8
    private static let registerExtensions: Void = cmark_gfm_core_extensions_ensure_registered()

    /// Renders markdown to an HTML fragment. Raw HTML is kept but rebuilt from an
    /// allowlist, and link and image URLs are limited to safe schemes.
    ///
    /// With `sourcePositions`, block elements carry `data-sourcepos="line:col-line:col"`, which
    /// the app uses to map a clicked task checkbox back to its line.
    static func html(from markdown: String, sourcePositions: Bool = false) -> String {
        _ = registerExtensions
        let (frontMatter, body) = splitFrontMatter(markdown)
        let options = sourcePositions ? options | CMARK_OPT_SOURCEPOS : options

        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        body.withCString { cmark_parser_feed(parser, $0, strlen($0)) }
        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }
        sanitize(document)
        guard let rendered = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(rendered) }

        var html = addHeadingAnchors(String(cString: rendered))
        if let frontMatter {
            html = "<pre class=\"front-matter\"><code class=\"language-yaml\">\(escape(frontMatter))</code></pre>\n" + html
        }
        return html
    }

    /// A self-contained page for Quick Look: stylesheet inlined, local images embedded as data URLs,
    /// and an "Edit" link that asks the app to open the file in the user's chosen editor.
    static func standalonePage(for markdown: String, fileURL: URL) -> String {
        var editLink = URLComponents()
        editLink.scheme = "litemd"
        editLink.host = "edit"
        editLink.queryItems = [URLQueryItem(name: "path", value: fileURL.path)]
        let body = embedLocalImages(in: html(from: markdown), relativeTo: fileURL.deletingLastPathComponent())
        return """
            <!doctype html>
            <html><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline'">
            <style>\(stylesheet)</style>
            </head><body>
            <a class="edit-link" href="\(escape(editLink.string ?? ""))" title="Open in your chosen editor">Edit ↗</a>
            <article class="markdown-body">\(body)</article></body></html>
            """
    }

    private static let imageSourcePattern = try! NSRegularExpression(pattern: #"(<img\b[^>]*?\bsrc=")([^"]+)(")"#)
    private static let maxEmbeddedImageBytes = 20_000_000

    /// Replaces relative image paths with data URLs, since Quick Look can't load neighbouring files itself.
    private static func embedLocalImages(in html: String, relativeTo directory: URL) -> String {
        let source = html as NSString
        let result = NSMutableString()
        var cursor = 0
        for match in imageSourcePattern.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let srcRange = match.range(at: 2)
            result.append(source.substring(with: NSRange(location: cursor, length: srcRange.location - cursor)))
            cursor = NSMaxRange(srcRange)
            let src = source.substring(with: srcRange)
            result.append(dataURL(forImageAt: src, relativeTo: directory) ?? src)
        }
        result.append(source.substring(from: cursor))
        return result as String
    }

    private static func dataURL(forImageAt src: String, relativeTo directory: URL) -> String? {
        guard !src.contains(":"),
              let path = src.replacingOccurrences(of: "&amp;", with: "&").removingPercentEncoding else { return nil }
        let fileURL = URL(fileURLWithPath: path, relativeTo: path.hasPrefix("/") ? nil : directory).standardizedFileURL
        guard let type = UTType(filenameExtension: fileURL.pathExtension), type.conforms(to: .image),
              let mimeType = type.preferredMIMEType,
              let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxEmbeddedImageBytes,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    static let stylesheet: String = {
        guard let url = Bundle.main.url(forResource: "markdown", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return css
    }()

    /// Decodes file contents, preferring UTF-8 and falling back to Foundation's detection.
    static func decode(_ data: Data) -> (text: String, encoding: String.Encoding) {
        if let text = String(data: data, encoding: .utf8) { return (text, .utf8) }
        var converted: NSString?
        var lossy: ObjCBool = false
        let raw = NSString.stringEncoding(for: data, encodingOptions: [:], convertedString: &converted, usedLossyConversion: &lossy)
        if raw != 0, let converted { return (converted as String, String.Encoding(rawValue: raw)) }
        return (String(decoding: data, as: UTF8.self), .utf8)
    }

    // MARK: - Helpers

    private static let inlineDroppedOpenTag = try! NSRegularExpression(
        pattern: #"^<(script|style|iframe|noscript|textarea|title|xmp|noembed|noframes|template|object|embed|svg|math)\b"#,
        options: .caseInsensitive)

    /// Rewrites raw HTML nodes through the sanitizer and blanks unsafe link and image URLs.
    private static func sanitize(_ document: UnsafeMutablePointer<cmark_node>) {
        guard let iterator = cmark_iter_new(document) else { return }
        defer { cmark_iter_free(iterator) }
        // Inline `<script>x</script>` arrives as separate nodes, so text between them is blanked here.
        var droppingUntilClosingTag: String?
        while cmark_iter_next(iterator) != CMARK_EVENT_DONE {
            guard let node = cmark_iter_get_node(iterator) else { continue }
            let isEnter = cmark_iter_get_event_type(iterator) == CMARK_EVENT_ENTER
            switch cmark_node_get_type(node) {
            case CMARK_NODE_PARAGRAPH, CMARK_NODE_HEADING:
                // Inline HTML can't span blocks.
                droppingUntilClosingTag = nil
            case _ where String(cString: cmark_node_get_type_string(node)) == "table_cell":
                droppingUntilClosingTag = nil
            case CMARK_NODE_TEXT, CMARK_NODE_CODE:
                if droppingUntilClosingTag != nil { cmark_node_set_literal(node, "") }
            case CMARK_NODE_HTML_INLINE:
                guard let literal = cmark_node_get_literal(node).map({ String(cString: $0) }) else { continue }
                if let closing = droppingUntilClosingTag {
                    if literal.lowercased().hasPrefix(closing) { droppingUntilClosingTag = nil }
                    cmark_node_set_literal(node, "")
                    continue
                }
                let range = NSRange(location: 0, length: (literal as NSString).length)
                if let match = inlineDroppedOpenTag.firstMatch(in: literal, range: range) {
                    droppingUntilClosingTag = "</" + (literal as NSString).substring(with: match.range(at: 1)).lowercased()
                }
                cmark_node_set_literal(node, HTMLSanitizer.sanitize(literal))
            case CMARK_NODE_HTML_BLOCK:
                guard let literal = cmark_node_get_literal(node) else { continue }
                cmark_node_set_literal(node, HTMLSanitizer.sanitize(String(cString: literal)))
            case CMARK_NODE_LINK, CMARK_NODE_IMAGE:
                guard isEnter, let url = cmark_node_get_url(node),
                      !HTMLSanitizer.isSafeURL(String(cString: url)) else { continue }
                cmark_node_set_url(node, "")
            default:
                continue
            }
        }
    }

    /// Separates a leading YAML front-matter block so it shows as code rather than as a rule and heading.
    /// The body keeps blank lines in its place, so source line numbers still match the file.
    private static func splitFrontMatter(_ markdown: String) -> (String?, String) {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else { return (nil, markdown) }
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        for index in lines.indices.dropFirst() {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" || line == "..." {
                let frontMatter = lines[1..<index].joined(separator: "\n")
                let body = String(repeating: "\n", count: index + 1) + lines[(index + 1)...].joined(separator: "\n")
                return (frontMatter, body)
            }
        }
        return (nil, markdown)
    }

    private static let headingPattern = try! NSRegularExpression(pattern: "<h([1-6])((?: [^>]*)?)>(.*?)</h\\1>")
    private static let tagPattern = try! NSRegularExpression(pattern: "<[^>]+>")

    /// Adds GitHub-style `id`s to headings so in-document links work.
    private static func addHeadingAnchors(_ html: String) -> String {
        let source = html as NSString
        let result = NSMutableString()
        var used: [String: Int] = [:]
        var cursor = 0
        for match in headingPattern.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let level = source.substring(with: match.range(at: 1))
            let attributes = source.substring(with: match.range(at: 2))
            let inner = source.substring(with: match.range(at: 3))
            var slug = slugify(inner)
            if let count = used[slug] {
                used[slug] = count + 1
                slug += "-\(count)"
            } else {
                used[slug] = 1
            }
            result.append(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            result.append("<h\(level) id=\"\(slug)\"\(attributes)>\(inner)</h\(level)>")
            cursor = match.range.location + match.range.length
        }
        result.append(source.substring(from: cursor))
        return result as String
    }

    private static func slugify(_ headingHTML: String) -> String {
        let text = tagPattern.stringByReplacingMatches(
            in: headingHTML, range: NSRange(location: 0, length: (headingHTML as NSString).length), withTemplate: "")
        let decoded = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        let kept = decoded.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" || $0 == "_"
        }
        return String(String.UnicodeScalarView(kept)).replacingOccurrences(of: " ", with: "-")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
