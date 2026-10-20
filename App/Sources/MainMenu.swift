import AppKit

/// Builds the menu bar in code, since the app has no nib.
enum MainMenu {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()
        for submenu in [appMenu(), fileMenu(), editMenu(), formatMenu(), viewMenu(), windowMenu()] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    private static func appMenu() -> NSMenu {
        let name = ProcessInfo.processInfo.processName
        return menu(name, [
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
        ])
    }

    private static func fileMenu() -> NSMenu {
        // NSDocumentController fills in any submenu that holds a "Clear Menu" item.
        let recent = menu("Open Recent", [item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))])
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        return menu("File", [
            item("New", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
            recentItem,
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save", #selector(NSDocument.save(_:)), "s"),
            item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]),
            item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))),
            .separator(),
            item("Edit in…", #selector(DocumentViewController.openInExternalEditor(_:)), "e", [.command, .shift]),
        ])
    }

    private static func editMenu() -> NSMenu {
        let find = menu("Find", [
            item("Find…", #selector(NSTextView.performTextFinderAction(_:)), "f", tag: NSTextFinder.Action.showFindInterface.rawValue),
            item("Find and Replace…", #selector(NSTextView.performTextFinderAction(_:)), "f", [.command, .option],
                 tag: NSTextFinder.Action.showReplaceInterface.rawValue),
            item("Find Next", #selector(NSTextView.performTextFinderAction(_:)), "g", tag: NSTextFinder.Action.nextMatch.rawValue),
            item("Find Previous", #selector(NSTextView.performTextFinderAction(_:)), "g", [.command, .shift],
                 tag: NSTextFinder.Action.previousMatch.rawValue),
        ])
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findItem.submenu = find
        return menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            findItem,
        ])
    }

    private static func formatMenu() -> NSMenu {
        menu("Format", [
            item("Bold", #selector(DocumentViewController.formatBold(_:)), "b"),
            item("Italic", #selector(DocumentViewController.formatItalic(_:)), "i"),
            item("Code", #selector(DocumentViewController.formatCode(_:)), "c", [.command, .shift]),
            item("Link", #selector(DocumentViewController.formatLink(_:)), "k"),
            item("Heading", #selector(DocumentViewController.formatHeading(_:)), "h", [.command, .shift]),
        ])
    }

    private static func viewMenu() -> NSMenu {
        let appearance = menu("Appearance", AppearanceSetting.allCases.map {
            let item = item($0.title, #selector(AppDelegate.setAppearance(_:)))
            item.representedObject = $0.rawValue
            return item
        } + [.separator(), item("Toggle Light/Dark", #selector(AppDelegate.toggleAppearance(_:)), "l", [.command, .shift])])
        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        appearanceItem.submenu = appearance
        return menu("View", [
            item("Edit", #selector(DocumentViewController.toggleMode(_:)), "e"),
            .separator(),
            appearanceItem,
            .separator(),
            item("Show Toolbar", #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option]),
            item("Customize Toolbar…", #selector(NSWindow.runToolbarCustomizationPalette(_:))),
        ])
    }

    private static func windowMenu() -> NSMenu {
        let windowMenu = menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = windowMenu
        return windowMenu
    }

    // MARK: - Helpers

    private static func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        return menu
    }

    private static func item(
        _ title: String, _ action: Selector, _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        return item
    }
}
