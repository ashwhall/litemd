import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private lazy var settings = SettingsWindowController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        NSApp.appearance = Preferences.appearance.nsAppearance
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Files opened from Finder arrive around launch; only prompt if none did.
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.openDocument(nil)
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { NSDocumentController.shared.openDocument(nil) }
        return false
    }

    // MARK: - Actions

    @objc func showSettings(_ sender: Any?) {
        settings.showWindow(sender)
    }

    @objc func setAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let setting = AppearanceSetting(rawValue: raw) else { return }
        Preferences.appearance = setting
    }

    /// Flips between light and dark, starting from whatever is currently showing.
    @objc func toggleAppearance(_ sender: Any?) {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        Preferences.appearance = isDark ? .light : .dark
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(setAppearance(_:)) {
            item.state = item.representedObject as? String == Preferences.appearance.rawValue ? .on : .off
        }
        return true
    }
}
