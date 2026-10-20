import AppKit

enum AppearanceSetting: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension Notification.Name {
    static let preferencesDidChange = Notification.Name("LiteMDPreferencesDidChange")
}

/// Persistent settings, stored in UserDefaults.
enum Preferences {
    private static let defaults = UserDefaults.standard

    static var appearance: AppearanceSetting {
        get { AppearanceSetting(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: "appearance")
            NSApp.appearance = newValue.nsAppearance
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// The app used by "Edit in…". The bundle ID is kept as a fallback in case the app moves.
    static var editorAppURL: URL? {
        get {
            if let path = defaults.string(forKey: "editorAppPath"), FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
            guard let bundleID = defaults.string(forKey: "editorAppBundleID") else { return nil }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }
        set {
            defaults.set(newValue?.path, forKey: "editorAppPath")
            defaults.set(newValue.flatMap { Bundle(url: $0)?.bundleIdentifier }, forKey: "editorAppBundleID")
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    static var editorAppName: String? {
        editorAppURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }
}
