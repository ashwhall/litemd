import AppKit

final class Document: NSDocument {
    var text = ""
    private var encoding: String.Encoding = .utf8

    /// Called after the text is replaced from disk (open, revert, external change).
    var onTextReplaced: (() -> Void)?

    /// Classic save model: explicit Save, and a save/discard prompt on close or quit.
    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let data = text.data(using: encoding) ?? text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    override func read(from data: Data, ofType typeName: String) throws {
        (text, encoding) = MarkdownRenderer.decode(data)
        undoManager?.removeAllActions()
        onTextReplaced?()
    }

    // MARK: - Reload on external change

    override func presentedItemDidChange() {
        super.presentedItemDidChange()
        DispatchQueue.main.async { [weak self] in self?.reloadIfChangedOnDisk() }
    }

    /// Reloads silently when there are no unsaved edits. With unsaved edits, the next save warns instead.
    private func reloadIfChangedOnDisk() {
        guard !isDocumentEdited, let url = fileURL, let type = fileType,
              let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              modified != fileModificationDate else { return }
        try? revert(toContentsOf: url, ofType: type)
    }
}
