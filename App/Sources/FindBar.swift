import AppKit

/// A Safari-style find bar for the rendered view, which has no system find bar.
final class FindBar: NSVisualEffectView, NSSearchFieldDelegate {
    static let height: CGFloat = 36

    let field = NSSearchField()
    private let notFound = NSTextField(labelWithString: "Not found")

    /// Called with the query, whether to search backwards, and whether to restart from the top.
    var onSearch: ((String, Bool, Bool) -> Void)?
    var onClose: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .headerView
        blendingMode = .withinWindow

        field.placeholderString = "Find"
        field.sendsSearchStringImmediately = true
        field.delegate = self
        field.target = self
        field.action = #selector(searchChanged(_:))

        notFound.textColor = .secondaryLabelColor
        notFound.isHidden = true

        let arrows = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")!,
                NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")!,
            ],
            trackingMode: .momentary, target: self, action: #selector(arrowClicked(_:)))
        arrows.setToolTip("Previous (⇧⌘G)", forSegment: 0)
        arrows.setToolTip("Next (⌘G)", forSegment: 1)
        arrows.controlSize = .small
        let done = NSButton(title: "Done", target: self, action: #selector(close(_:)))
        done.controlSize = .small
        field.controlSize = .small

        let stack = NSStackView(views: [field, notFound, arrows, done])
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.widthAnchor.constraint(equalToConstant: 220),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showNotFound(_ isNotFound: Bool) {
        notFound.isHidden = !isNotFound
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        onSearch?(sender.stringValue, false, true)
    }

    @objc private func arrowClicked(_ sender: NSSegmentedControl) {
        onSearch?(field.stringValue, sender.selectedSegment == 0, false)
    }

    @objc private func close(_ sender: Any?) {
        onClose?()
    }

    /// Return finds the next match, Shift-Return the previous, and Escape closes the bar.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onSearch?(field.stringValue, NSEvent.modifierFlags.contains(.shift), false)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }
}
