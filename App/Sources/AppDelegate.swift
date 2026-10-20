import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private lazy var settings = SettingsWindowController()

    /// Set when launched only to hand a file to the external editor, so no open panel appears.
    private var launchedForURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        NSApp.appearance = Preferences.appearance.nsAppearance
        // A URL-event handler, rather than application(_:open:), leaves file opening to NSDocumentController.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Files opened from Finder arrive around launch; only prompt if none did.
        DispatchQueue.main.async { [self] in
            if !launchedForURL && NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.openDocument(nil)
            }
        }
    }

    /// Handles `litemd://edit?path=…` from the Quick Look preview's "Edit" link.
    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let components = URLComponents(string: string), components.host == "edit",
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value else { return }
        let fileURL = URL(fileURLWithPath: path)
        // Only markdown files that exist, so a web page can't use the scheme to open arbitrary files.
        guard UTType(filenameExtension: fileURL.pathExtension)?.conforms(to: UTType(importedAs: "net.daringfireball.markdown")) == true,
              FileManager.default.fileExists(atPath: path) else { return }

        // With no windows open, LiteMD was only needed for the hand-off, so it quits afterwards.
        let isIdle = NSDocumentController.shared.documents.isEmpty
        launchedForURL = launchedForURL || isIdle
        let finish = { if isIdle { NSApp.terminate(nil) } }
        if let appURL = Preferences.editorAppURL {
            ExternalEditor.open(fileURL, with: appURL, completion: finish)
        } else {
            NSApp.activate()
            ExternalEditor.chooseApp(for: nil) { appURL in
                guard let appURL else { return finish() }
                ExternalEditor.open(fileURL, with: appURL, completion: finish)
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
