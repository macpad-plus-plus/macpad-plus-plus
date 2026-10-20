import AppKit

/// Opens a folder in the terminal chosen in Settings: one of the usual Mac
/// terminals, or a command line of the user's own.
enum Terminal {
    struct App: Identifiable, Equatable {
        /// Stored in the preferences.
        let id: String
        let name: String
        /// The application's name, as `open -a` takes it.
        let application: String
    }

    static let apps: [App] = [
        App(id: "terminal", name: "Terminal", application: "Terminal"),
        App(id: "iterm", name: "iTerm", application: "iTerm"),
        App(id: "warp", name: "Warp", application: "Warp"),
        App(id: "ghostty", name: "Ghostty", application: "Ghostty"),
    ]

    /// The preference value for "your own command".
    static let custom = "custom"

    /// The terminals installed here; Terminal always is.
    static var installed: [App] {
        apps.filter { $0.id == "terminal" || NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID($0)) != nil }
    }

    private static func bundleID(_ app: App) -> String {
        switch app.id {
        case "iterm": "com.googlecode.iterm2"
        case "warp": "dev.warp.Warp-Stable"
        case "ghostty": "com.mitchellh.ghostty"
        default: "com.apple.Terminal"
        }
    }

    /// Opens `folder` in the terminal `choice` names (an app's id, `custom`
    /// with `command`, or empty for Terminal).
    static func open(_ folder: URL, choice: String, command: String) throws {
        let process = Process()
        if choice == custom {
            let words = splitWords(command).map { $0.replacingOccurrences(of: "{dir}", with: folder.path) }
            guard let program = words.first else {
                throw TerminalError(message: String(localized: "No terminal command is set. Enter one in Settings."))
            }
            // Through env, so the program is looked up on the PATH.
            process.executableURL = URL(filePath: "/usr/bin/env")
            process.arguments = [program] + words.dropFirst()
        } else if choice == "ghostty" {
            process.executableURL = URL(filePath: "/usr/bin/open")
            process.arguments = ["-na", "Ghostty", "--args", "--working-directory=\(folder.path)"]
        } else {
            let app = apps.first { $0.id == choice } ?? apps[0]
            process.executableURL = URL(filePath: "/usr/bin/open")
            process.arguments = ["-a", app.application, folder.path]
        }
        process.currentDirectoryURL = folder
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    struct TerminalError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Splits a command line on spaces, keeping "quoted parts" together.
    static func splitWords(_ line: String) -> [String] {
        var words: [String] = []
        var word = ""
        var quote: Character?
        var inWord = false
        for character in line {
            if let open = quote {
                if character == open { quote = nil } else { word.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                inWord = true
            } else if character.isWhitespace {
                if inWord {
                    words.append(word)
                    word = ""
                    inWord = false
                }
            } else {
                word.append(character)
                inWord = true
            }
        }
        if inWord { words.append(word) }
        return words
    }
}
