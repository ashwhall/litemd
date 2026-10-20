import Foundation

/// Rebuilds raw HTML from markdown using an allowlist of tags and attributes.
///
/// Tags are re-serialised rather than filtered, so anything not listed (event handlers,
/// `style`, `<script>`, comments, unknown tags) never reaches the output. Quick Look
/// ignores Content-Security-Policy, so this is the line of defence there.
enum HTMLSanitizer {
    private static let allowedTags: Set<String> = [
        "a", "abbr", "b", "blockquote", "br", "code", "dd", "del", "details", "div", "dl", "dt", "em",
        "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "img", "ins", "kbd", "li", "mark", "ol", "p",
        "picture", "pre", "q", "s", "samp", "small", "source", "span", "strong", "sub", "summary", "sup",
        "table", "tbody", "td", "tfoot", "th", "thead", "tr", "u", "ul", "var",
    ]
    private static let allowedAttributes: Set<String> = [
        "align", "alt", "colspan", "height", "href", "id", "name", "open", "rowspan", "src", "srcset",
        "start", "title", "type", "width", "media",
    ]
    private static let urlAttributes: Set<String> = ["href", "src", "srcset"]

    private static let tagPattern = try! NSRegularExpression(
        pattern: #"<(/?)([A-Za-z][A-Za-z0-9-]*)((?:\s+[^\s"'>/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*/?>"#)
    private static let commentPattern = try! NSRegularExpression(pattern: "<!--.*?-->", options: .dotMatchesLineSeparators)
    /// Elements whose contents are code or invisible, so they're removed along with their text.
    /// An unclosed one swallows the rest of the fragment.
    private static let droppedElementPattern = try! NSRegularExpression(
        pattern: #"<(script|style|iframe|noscript|textarea|title|xmp|noembed|noframes|template|object|embed|svg|math)\b.*?(?:</\1\s*>|\z)"#,
        options: [.dotMatchesLineSeparators, .caseInsensitive])
    private static let attributePattern = try! NSRegularExpression(
        pattern: #"([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#)

    /// Sanitises a raw HTML fragment. Text outside recognised tags is escaped.
    static func sanitize(_ html: String) -> String {
        var withoutComments = html
        for pattern in [commentPattern, droppedElementPattern] {
            withoutComments = pattern.stringByReplacingMatches(
                in: withoutComments, range: NSRange(location: 0, length: (withoutComments as NSString).length), withTemplate: "")
        }
        let source = withoutComments as NSString
        var output = ""
        var cursor = 0
        for match in tagPattern.matches(in: withoutComments, range: NSRange(location: 0, length: source.length)) {
            output += escapeText(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = NSMaxRange(match.range)

            let isClosing = match.range(at: 1).length > 0
            let name = source.substring(with: match.range(at: 2)).lowercased()
            guard allowedTags.contains(name) else { continue }
            if isClosing {
                output += "</\(name)>"
            } else {
                output += "<\(name)\(sanitizeAttributes(source.substring(with: match.range(at: 3))))>"
            }
        }
        output += escapeText(source.substring(from: cursor))
        return output
    }

    /// Allows http(s), mailto, in-page anchors, and relative paths. Values containing `&` or `:`
    /// that don't start with an allowed scheme are rejected, which rules out entity-encoded schemes.
    static func isSafeURL(_ url: String) -> Bool {
        let lowered = url.lowercased()
        if ["http://", "https://", "mailto:", "#"].contains(where: lowered.hasPrefix) { return true }
        return !url.contains(":") && !url.contains("&")
    }

    private static func sanitizeAttributes(_ attributes: String) -> String {
        let source = attributes as NSString
        var output = ""
        for match in attributePattern.matches(in: attributes, range: NSRange(location: 0, length: source.length)) {
            let name = source.substring(with: match.range(at: 1)).lowercased()
            guard allowedAttributes.contains(name) else { continue }
            let valueRange = (2...4).map { match.range(at: $0) }.first { $0.location != NSNotFound }
            guard let valueRange else {
                output += " \(name)"
                continue
            }
            let value = source.substring(with: valueRange)
            if urlAttributes.contains(name) {
                let urls = name == "srcset"
                    ? value.split(separator: ",").compactMap { $0.split(separator: " ").first.map(String.init) }
                    : [value.trimmingCharacters(in: .whitespaces)]
                guard urls.allSatisfy(isSafeURL) else { continue }
            }
            output += " \(name)=\"\(value.replacingOccurrences(of: "\"", with: "&quot;"))\""
        }
        return output
    }

    private static func escapeText(_ text: String) -> String {
        text.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
