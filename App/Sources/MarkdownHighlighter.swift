import AppKit

/// Regex-based syntax colouring for the markdown editor.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private lazy var boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    private lazy var italicFont: NSFont = {
        let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }()

    private struct Rule {
        let regex: NSRegularExpression
        let group: Int
        let attributes: () -> [NSAttributedString.Key: Any]
    }

    private lazy var rules: [Rule] = [
        rule(#"^#{1,6}[ \t].*$"#) { [.font: self.boldFont, .foregroundColor: NSColor.systemBlue] },
        rule(#"^ {0,3}>.*$"#) { [.foregroundColor: NSColor.secondaryLabelColor] },
        rule(#"^\s*([-*+]|\d+[.)])[ \t]"#, group: 1) { [.foregroundColor: NSColor.systemOrange] },
        rule(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#) { [.foregroundColor: NSColor.tertiaryLabelColor] },
        rule(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#) { [.font: self.boldFont] },
        rule(#"(?<![*_\w])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*_\w])"#) { [.font: self.italicFont] },
        rule(#"~~(?=\S)(.+?)(?<=\S)~~"#) { [.strikethroughStyle: NSUnderlineStyle.single.rawValue] },
        rule(#"!?\[[^\]\n]*\](\([^)\n]*\))"#, group: 1) { [.foregroundColor: NSColor.linkColor] },
        rule(#"<(?:https?|mailto):[^>\s]+>"#) { [.foregroundColor: NSColor.linkColor] },
        rule(#"`[^`\n]+`"#) { [.foregroundColor: NSColor.systemPink] },
        rule(#"<!--.*?-->"#, dotAll: true) { [.foregroundColor: NSColor.tertiaryLabelColor] },
        // Fenced code last, so it overrides everything inside the block.
        rule(#"^ {0,3}(`{3,}|~{3,}).*?^ {0,3}\1[ \t]*$"#, dotAll: true) {
            [.font: self.font, .foregroundColor: NSColor.systemPink, .strikethroughStyle: 0]
        },
    ]

    private func rule(
        _ pattern: String, group: Int = 0, dotAll: Bool = false,
        _ attributes: @escaping () -> [NSAttributedString.Key: Any]
    ) -> Rule {
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if dotAll { options.insert(.dotMatchesLineSeparators) }
        return Rule(regex: try! NSRegularExpression(pattern: pattern, options: options), group: group, attributes: attributes)
    }

    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        highlight(textStorage)
    }

    /// Re-colours the whole document. Fenced blocks can span the file, so partial passes get it wrong,
    /// and a full pass is fast enough for typical markdown files.
    func highlight(_ textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string
        textStorage.setAttributes([.font: font, .foregroundColor: NSColor.textColor], range: fullRange)
        for rule in rules {
            let attributes = rule.attributes()
            rule.regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let range = match?.range(at: rule.group), range.location != NSNotFound else { return }
                textStorage.addAttributes(attributes, range: range)
            }
        }
    }
}
