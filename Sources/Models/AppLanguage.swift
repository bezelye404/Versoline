import AppKit

/// The language the app is shown in. "System" follows macOS; the other cases pin Versoline to one language
/// through the per-app `AppleLanguages` override, the same setting System Settings > Language & Region writes.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case turkish = "tr"

    var id: String { rawValue }

    /// Language names are shown in their own language so they can be found whatever the current one is.
    var nativeName: String? {
        switch self {
        case .system: return nil
        case .english: return "English"
        case .turkish: return "Türkçe"
        }
    }

    private static let overrideKey = "AppleLanguages"

    /// The override stored for this app, or `.system` when there is none.
    static func current(defaults: UserDefaults = .standard, bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> AppLanguage {
        guard let bundleIdentifier,
              let codes = defaults.persistentDomain(forName: bundleIdentifier)?[overrideKey] as? [String],
              let first = codes.first
        else { return .system }
        let base = first.split(separator: "-").first.map(String.init) ?? first
        return AppLanguage(rawValue: base) ?? .system
    }

    func apply(defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: Self.overrideKey)
        } else {
            defaults.set([rawValue], forKey: Self.overrideKey)
        }
    }

    /// Starts a fresh copy of the app and quits this one, so the new language is picked up.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
