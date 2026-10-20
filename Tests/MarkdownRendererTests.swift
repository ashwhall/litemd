import XCTest

final class MarkdownRendererTests: XCTestCase {
    private func render(_ markdown: String) -> String { MarkdownRenderer.html(from: markdown) }

    // MARK: - GFM features

    func testTable() {
        let html = render("| a | b |\n|---|---|\n| 1 | 2 |")
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<td>2</td>"))
    }

    func testTaskList() {
        XCTAssertTrue(render("- [x] done").contains("checked"))
    }

    func testStrikethroughAndAutolink() {
        let html = render("~~gone~~ https://example.com")
        XCTAssertTrue(html.contains("<del>gone</del>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">"))
    }

    func testFootnote() {
        XCTAssertTrue(render("Text[^1]\n\n[^1]: Note").contains("class=\"footnotes\""))
    }

    func testFencedCodeKeepsLanguageClass() {
        XCTAssertTrue(render("```swift\nlet x = 1\n```").contains("<code class=\"language-swift\">"))
    }

    func testHeadingAnchors() {
        let html = render("# Hello, World!\n\n## Hello, World!")
        XCTAssertTrue(html.contains("<h1 id=\"hello-world\">"))
        XCTAssertTrue(html.contains("<h2 id=\"hello-world-1\">"))
    }

    func testSourcePositionsMatchFileLinesAfterFrontMatter() {
        let html = MarkdownRenderer.html(from: "---\na: 1\n---\n# Title\n\n- [ ] task", sourcePositions: true)
        XCTAssertTrue(html.contains("<li data-sourcepos=\"6:1-6:10\">"), html)
        XCTAssertTrue(html.contains("<h1 id=\"title\" data-sourcepos=\"4:1-4:7\">"), html)
    }

    func testFrontMatterRendersAsCode() {
        let html = render("---\ntitle: x\n---\n# Body")
        XCTAssertTrue(html.contains("class=\"front-matter\""))
        XCTAssertTrue(html.contains("title: x"))
        XCTAssertTrue(html.contains("<h1 id=\"body\">"))
    }

    // MARK: - Allowed raw HTML

    func testAllowedHTMLIsKept() {
        let html = render("<details open><summary>More</summary>\n\nHidden\n\n</details>\n\nPress <kbd>⌘</kbd><br>")
        XCTAssertTrue(html.contains("<details open>"))
        XCTAssertTrue(html.contains("<summary>More</summary>"))
        XCTAssertTrue(html.contains("<kbd>⌘</kbd>"))
        XCTAssertTrue(html.contains("<br>"))
    }

    func testImageAttributesKept() {
        let html = render("<img src=\"pic.png\" width=\"100\" alt='A \"quoted\" pic'>")
        XCTAssertTrue(html.contains("<img src=\"pic.png\" width=\"100\" alt=\"A &quot;quoted&quot; pic\">"))
    }

    func testCommentsDropped() {
        XCTAssertFalse(render("<!-- secret -->\n\nText").contains("secret"))
    }

    // MARK: - Script injection

    func testEventHandlersStripped() {
        let html = render("<img src=x onerror=\"alert(1)\"> <a href=\"#\" onclick='alert(2)'>x</a>")
        XCTAssertFalse(html.contains("onerror"))
        XCTAssertFalse(html.contains("onclick"))
    }

    func testScriptAndStyleTagsRemoved() {
        let html = render("<script>alert(1)</script>\n\n<style>body{display:none}</style>\n\n<iframe src=\"https://x\"></iframe>")
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<style"))
        XCTAssertFalse(html.contains("<iframe"))
        XCTAssertFalse(html.contains("alert"), "script contents should be dropped, not shown")
        XCTAssertFalse(html.contains("display:none"))
    }

    func testInlineScriptContentsDropped() {
        let html = render("Before <script>steal()</script> after")
        XCTAssertFalse(html.contains("steal"))
        XCTAssertTrue(html.contains("after"))
    }

    func testStyleAttributeStripped() {
        XCTAssertFalse(render("<div style=\"position:fixed\">x</div>").contains("style="))
    }

    func testJavaScriptURLsRemoved() {
        let cases = [
            "[x](javascript:alert(1))",
            "<a href=\"javascript:alert(1)\">x</a>",
            "<a href=\"JaVaScRiPt:alert(1)\">x</a>",
            "<a href=\"jav&#x61;script:alert(1)\">x</a>",
            "<a href=\" javascript:alert(1)\">x</a>",
            "![x](javascript:alert(1))",
            "<img srcset=\"javascript:alert(1) 2x\">",
            "[x](data:text/html,<script>alert(1)</script>)",
        ]
        for markdown in cases {
            let html = render(markdown).lowercased()
            XCTAssertFalse(html.contains("javascript:"), markdown)
            XCTAssertFalse(html.contains("jav&#x61;script"), markdown)
            XCTAssertFalse(html.contains("data:text"), markdown)
        }
    }

    func testMalformedTagsAreEscaped() {
        let html = render("<img src=x onerror=alert(1)//")
        XCTAssertFalse(html.contains("<img"))
    }

    func testSafeURLs() {
        XCTAssertTrue(HTMLSanitizer.isSafeURL("https://example.com"))
        XCTAssertTrue(HTMLSanitizer.isSafeURL("mailto:a@b.c"))
        XCTAssertTrue(HTMLSanitizer.isSafeURL("#section"))
        XCTAssertTrue(HTMLSanitizer.isSafeURL("docs/other.md"))
        XCTAssertFalse(HTMLSanitizer.isSafeURL("file:///etc/passwd"))
        XCTAssertFalse(HTMLSanitizer.isSafeURL("vbscript:x"))
    }
}
