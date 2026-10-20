import AppKit

final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private let content: DocumentViewController
    private var modeControl: NSSegmentedControl?
    private var editInItem: NSToolbarItem?
    private var preferencesObserver: NSObjectProtocol?

    init(document: Document) {
        content = DocumentViewController(document: document)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.contentViewController = content
        window.setContentSize(NSSize(width: 820, height: 900))
        window.minSize = NSSize(width: 420, height: 300)
        window.toolbarStyle = .unified
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true

        let toolbar = NSToolbar(identifier: "DocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar

        content.onModeChange = { [weak self] mode in self?.modeDidChange(mode) }
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: .preferencesDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.updateEditInItem() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        document?.undoManager
    }

    private func modeDidChange(_ mode: DocumentViewController.Mode) {
        modeControl?.selectedSegment = mode.rawValue
    }

    private func updateEditInItem() {
        editInItem?.title = Preferences.editorAppName.map { "Edit in \($0)" } ?? "Edit in…"
    }

    // MARK: - Toolbar

    private enum Item {
        static let mode = NSToolbarItem.Identifier("mode")
        static let save = NSToolbarItem.Identifier("save")
        static let appearance = NSToolbarItem.Identifier("appearance")
        static let editIn = NSToolbarItem.Identifier("editIn")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.mode, .flexibleSpace, Item.save, Item.appearance, Item.editIn]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Item.mode:
            let control = NSSegmentedControl(
                labels: ["Read", "Edit"], trackingMode: .selectOne, target: self, action: #selector(modeSelected(_:)))
            control.setToolTip("Read (⌘E)", forSegment: 0)
            control.setToolTip("Edit (⌘E)", forSegment: 1)
            control.selectedSegment = content.mode.rawValue
            modeControl = control
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Mode"
            item.view = control
            return item
        case Item.save:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Save"
            item.title = "Save"
            item.toolTip = "Save (⌘S)"
            item.isBordered = true
            item.action = #selector(NSDocument.save(_:))
            return item
        case Item.appearance:
            return button(identifier, "Light/Dark", symbol: "circle.lefthalf.filled",
                          action: #selector(AppDelegate.toggleAppearance(_:)))
        case Item.editIn:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Edit In"
            item.toolTip = "Open in your chosen editor"
            item.isBordered = true
            item.action = #selector(DocumentViewController.openInExternalEditor(_:))
            editInItem = item
            updateEditInItem()
            return item
        default:
            return nil
        }
    }

    private func button(_ identifier: NSToolbarItem.Identifier, _ label: String, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.action = action
        return item
    }

    @objc private func modeSelected(_ sender: NSSegmentedControl) {
        guard let mode = DocumentViewController.Mode(rawValue: sender.selectedSegment) else { return }
        content.setMode(mode)
    }
}
