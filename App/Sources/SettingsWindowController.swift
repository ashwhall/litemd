import AppKit

final class SettingsWindowController: NSWindowController {
    private let appearancePopup = NSPopUpButton()
    private let editorLabel = NSTextField(labelWithString: "")
    private var observer: NSObjectProtocol?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 120),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        super.init(window: window)

        appearancePopup.addItems(withTitles: AppearanceSetting.allCases.map(\.title))
        appearancePopup.target = self
        appearancePopup.action = #selector(appearanceChanged(_:))

        editorLabel.lineBreakMode = .byTruncatingMiddle
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseEditor(_:)))
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearEditor(_:)))
        let editorRow = NSStackView(views: [editorLabel, choose, clear])
        editorRow.spacing = 8

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Appearance:"), appearancePopup],
            [NSTextField(labelWithString: "Edit in:"), editorRow],
        ])
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            editorLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        window.contentView = contentView
        window.center()

        observer = NotificationCenter.default.addObserver(
            forName: .preferencesDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func refresh() {
        appearancePopup.selectItem(at: AppearanceSetting.allCases.firstIndex(of: Preferences.appearance) ?? 0)
        editorLabel.stringValue = Preferences.editorAppName ?? "Not set"
        editorLabel.textColor = Preferences.editorAppURL == nil ? .secondaryLabelColor : .labelColor
    }

    @objc private func appearanceChanged(_ sender: NSPopUpButton) {
        Preferences.appearance = AppearanceSetting.allCases[sender.indexOfSelectedItem]
    }

    @objc private func chooseEditor(_ sender: Any?) {
        ExternalEditor.chooseApp(for: window) { _ in }
    }

    @objc private func clearEditor(_ sender: Any?) {
        Preferences.editorAppURL = nil
    }
}
