import AppKit

/// Hosts the rendered view and the editor, and switches between them.
final class DocumentViewController: NSViewController, NSTextViewDelegate, NSMenuItemValidation {
    enum Mode: Int {
        case rendered, edit
    }

    private unowned let document: Document
    private let preview = PreviewView(frame: NSRect(x: 0, y: 0, width: 820, height: 900))
    private let scrollView = NSTextView.scrollableTextView()
    private let highlighter = MarkdownHighlighter()
    private var textView: NSTextView { scrollView.documentView as! NSTextView }

    private(set) var mode: Mode = .rendered
    var onModeChange: ((Mode) -> Void)?

    init(document: Document) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = NSView(frame: preview.frame)
        for subview in [preview, scrollView] {
            subview.frame = container.bounds
            subview.autoresizingMask = [.width, .height]
            container.addSubview(subview)
        }
        view = container
        configureTextView()
        textView.string = document.text
        document.onTextReplaced = { [weak self] in self?.documentTextReplaced() }
        preview.onToggleTask = { [weak self] line in self?.toggleTask(atLine: line) }
    }

    private var hasAppeared = false

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !hasAppeared else { return }
        hasAppeared = true
        setMode(document.fileURL == nil ? .edit : .rendered)
    }

    private func configureTextView() {
        textView.delegate = self
        textView.textStorage?.delegate = highlighter
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = highlighter.font
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.typingAttributes = [.font: highlighter.font, .foregroundColor: NSColor.textColor]
    }

    private func documentTextReplaced() {
        guard isViewLoaded else { return }
        if textView.string != document.text {
            textView.string = document.text
        }
        if mode == .rendered { render() }
    }

    func textDidChange(_ notification: Notification) {
        document.text = textView.string
        // Edits can land while rendered: checkbox toggles, and undoing them.
        if mode == .rendered { render() }
    }

    private static let taskPattern = try! NSRegularExpression(pattern: #"^[ \t]*(?:>[ \t]*)*(?:[-*+]|\d+[.)])[ \t]+\[([ xX])\]"#)

    /// Flips `[ ]` / `[x]` on a source line, as an undoable edit.
    private func toggleTask(atLine line: Int) {
        let string = textView.string as NSString
        var lineStart = 0
        for _ in 1..<line {
            lineStart = NSMaxRange(string.lineRange(for: NSRange(location: lineStart, length: 0)))
            guard lineStart < string.length else { return }
        }
        let lineRange = string.lineRange(for: NSRange(location: lineStart, length: 0))
        let lineText = string.substring(with: lineRange)
        guard let match = Self.taskPattern.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length)) else {
            return render() // Out of sync; redraw from the source.
        }
        let mark = match.range(at: 1)
        let isChecked = (lineText as NSString).substring(with: mark) != " "
        replace(NSRange(location: lineRange.location + mark.location, length: 1), with: isChecked ? " " : "x")
    }

    // MARK: - Mode

    func setMode(_ newMode: Mode) {
        mode = newMode
        scrollView.isHidden = newMode != .edit
        preview.isHidden = newMode != .rendered
        switch newMode {
        case .rendered:
            render()
            view.window?.makeFirstResponder(preview.webView)
        case .edit:
            view.window?.makeFirstResponder(textView)
        }
        onModeChange?(newMode)
    }

    private func render() {
        preview.show(markdown: document.text, directory: document.fileURL?.deletingLastPathComponent())
    }

    @objc func toggleMode(_ sender: Any?) {
        setMode(mode == .edit ? .rendered : .edit)
    }

    // MARK: - Edit in…

    @objc func openInExternalEditor(_ sender: Any?) {
        guard let appURL = Preferences.editorAppURL else {
            ExternalEditor.chooseApp(for: view.window) { [weak self] url in
                if url != nil { self?.openInExternalEditor(sender) }
            }
            return
        }
        guard let fileURL = document.fileURL, !document.isDocumentEdited else {
            confirmSaveThenOpen(with: appURL)
            return
        }
        ExternalEditor.open(fileURL, with: appURL)
    }

    private func confirmSaveThenOpen(with appURL: URL) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        let appName = Preferences.editorAppName ?? "the editor"
        alert.messageText = "Save changes before opening in \(appName)?"
        alert.informativeText = document.fileURL == nil
            ? "The document needs to be saved before another app can open it."
            : "Otherwise \(appName) opens the last saved version."
        alert.addButton(withTitle: "Save")
        if document.fileURL != nil { alert.addButton(withTitle: "Open Saved Version") }
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                document.save(withDelegate: self, didSave: #selector(document(_:didSave:contextInfo:)), contextInfo: nil)
            case .alertSecondButtonReturn where document.fileURL != nil:
                ExternalEditor.open(document.fileURL!, with: appURL)
            default:
                break
            }
        }
    }

    @objc private func document(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard didSave, let fileURL = document.fileURL, let appURL = Preferences.editorAppURL else { return }
        ExternalEditor.open(fileURL, with: appURL)
    }

    // MARK: - Formatting

    @objc func formatBold(_ sender: Any?) { wrapSelection("**", "**", placeholder: "bold text") }
    @objc func formatItalic(_ sender: Any?) { wrapSelection("*", "*", placeholder: "italic text") }
    @objc func formatCode(_ sender: Any?) { wrapSelection("`", "`", placeholder: "code") }

    @objc func formatLink(_ sender: Any?) {
        wrapSelection("[", "](https://)", placeholder: "link text")
        // Select the URL so it can be typed straight over.
        let linkText = textView.selectedRange()
        textView.setSelectedRange(NSRange(location: NSMaxRange(linkText) + 2, length: "https://".utf16.count))
    }

    /// Adds a heading level to the current line, cycling back to plain text after `######`.
    @objc func formatHeading(_ sender: Any?) {
        let string = textView.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: textView.selectedRange().location, length: 0))
        let line = string.substring(with: lineRange)
        let hashes = line.prefix { $0 == "#" }.count
        let (range, replacement): (NSRange, String)
        switch hashes {
        case 0: (range, replacement) = (NSRange(location: lineRange.location, length: 0), "# ")
        case 6..<Int.max:
            let markerLength = line.hasPrefix("###### ") ? 7 : hashes
            (range, replacement) = (NSRange(location: lineRange.location, length: markerLength), "")
        default: (range, replacement) = (NSRange(location: lineRange.location, length: 0), "#")
        }
        replace(range, with: replacement)
    }

    private func wrapSelection(_ prefix: String, _ suffix: String, placeholder: String) {
        let range = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: range)
        let inner = selected.isEmpty ? placeholder : selected
        guard replace(range, with: prefix + inner + suffix) else { return }
        textView.setSelectedRange(NSRange(location: range.location + prefix.utf16.count, length: inner.utf16.count))
    }

    /// Replaces text through the text view so the change is undoable.
    @discardableResult
    private func replace(_ range: NSRange, with replacement: String) -> Bool {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return false }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        return true
    }

    // MARK: - Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleMode(_:)):
            item.title = mode == .edit ? "Read" : "Edit"
            return true
        case #selector(openInExternalEditor(_:)):
            item.title = Preferences.editorAppName.map { "Edit in \($0)" } ?? "Edit in…"
            return true
        case #selector(formatBold(_:)), #selector(formatItalic(_:)), #selector(formatCode(_:)),
             #selector(formatLink(_:)), #selector(formatHeading(_:)):
            return mode == .edit
        default:
            return true
        }
    }
}
