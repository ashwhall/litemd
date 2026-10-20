import AppKit

/// Picks and launches the user's preferred editor for "Edit in…".
enum ExternalEditor {
    static func chooseApp(for window: NSWindow?, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Choose"
        panel.message = "Choose the app that \"Edit in…\" opens markdown files with."
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return completion(nil) }
            Preferences.editorAppURL = url
            completion(url)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    static func open(_ fileURL: URL, with appURL: URL) {
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            DispatchQueue.main.async { NSApp.presentError(error) }
        }
    }
}
