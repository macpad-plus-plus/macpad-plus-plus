import AppKit

/// The interface language: the system's by default, or one picked in Settings
/// (like Notepad++'s Localization setting). Translations live in
/// `Resources/Localization/<code>.lproj/Localizable.strings`.
enum AppLanguage {
    /// Language codes the app ships translations for, e.g. ["en", "pt-BR"].
    static var available: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }.sorted { name(of: $0) < name(of: $1) }
    }

    /// The language's own name ("Português (Brasil)"), so people can find theirs.
    static func name(of code: String) -> String {
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// The language picked in Settings; "" follows the system.
    static var selected: String {
        get {
            // Only an AppleLanguages value set in our own domain counts as a choice.
            let own = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            return (own?["AppleLanguages"] as? [String])?.first ?? ""
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
            }
        }
    }

    /// Quits (saving the session) and starts a new instance once this one has exited.
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
