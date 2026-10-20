import AppKit

/// User preferences, stored in UserDefaults. The Settings window writes them
/// through @AppStorage; views pick up changes via `Preferences.didChange`.
enum Preferences {
    enum Key {
        static let theme = "theme"
        static let fontName = "fontName"
        static let fontSize = "fontSize"
        static let tabWidth = "tabWidth"
        static let insertSpaces = "insertSpaces"
        static let showLineNumbers = "showLineNumbers"
        static let highlightCurrentLine = "highlightCurrentLine"
        static let showIndentGuides = "showIndentGuides"
        static let wrapLines = "wrapLines"
        static let restoreSession = "restoreSession"
        static let defaultEncoding = "defaultEncoding"
        static let defaultLineEnding = "defaultLineEnding"
        static let showHiddenFiles = "showHiddenFiles"
        static let terminal = "terminal"
        static let terminalCommand = "terminalCommand"
    }

    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark, classic

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: String(localized: "Match System")
            case .light: String(localized: "Light")
            case .dark: String(localized: "Dark")
            case .classic: String(localized: "Classic (Mac OS 9 Platinum)")
            }
        }

        /// The appearance forced on the whole app; nil follows the system.
        /// Classic dresses dialogs and menus in dark, which sits better next to
        /// Platinum grey; document windows keep a light content view.
        var appearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark, .classic: NSAppearance(named: .darkAqua)
            }
        }
    }

    nonisolated(unsafe) static let defaults: [String: Any] = [
        Key.theme: Theme.system.rawValue,
        Key.fontName: "",
        Key.fontSize: 13.0,
        Key.tabWidth: 4,
        Key.insertSpaces: false,
        Key.showLineNumbers: true,
        Key.highlightCurrentLine: true,
        Key.showIndentGuides: true,
        Key.wrapLines: false,
        Key.restoreSession: true,
        Key.defaultEncoding: TextEncoding.utf8.rawValue,
        Key.defaultLineEnding: LineEnding.lf.rawValue,
        Key.showHiddenFiles: false,
        Key.terminal: "terminal",
        Key.terminalCommand: "",
    ]

    /// Posted on the main queue after any preference changes.
    static let didChange = Notification.Name("MacPadPreferencesDidChange")

    @MainActor
    static func register() {
        UserDefaults.standard.register(defaults: defaults)
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if NSApp.appearance?.name != theme.appearance?.name {
                    NSApp.appearance = theme.appearance
                }
                NotificationCenter.default.post(name: didChange, object: nil)
            }
        }
        NSApp.appearance = theme.appearance
    }

    private static var store: UserDefaults { .standard }

    static var theme: Theme { Theme(rawValue: store.string(forKey: Key.theme) ?? "") ?? .system }
    static var restoreSession: Bool { store.bool(forKey: Key.restoreSession) }
    static var showHiddenFiles: Bool { store.bool(forKey: Key.showHiddenFiles) }
    /// The terminal that opens a file's folder: a `Terminal.App` id, or `Terminal.custom`.
    static var terminal: String { store.string(forKey: Key.terminal) ?? "terminal" }
    /// The custom terminal's command line; `{dir}` is the folder.
    static var terminalCommand: String { store.string(forKey: Key.terminalCommand) ?? "" }

    static var newDocumentFormat: TextFormat {
        TextFormat(
            encoding: TextEncoding(rawValue: store.string(forKey: Key.defaultEncoding) ?? "") ?? .utf8,
            lineEnding: LineEnding(rawValue: store.string(forKey: Key.defaultLineEnding) ?? "") ?? .lf)
    }

    /// Everything the editor view needs, compared to skip redundant re-styling.
    struct EditorSettings: Equatable {
        var theme: Theme
        var fontName: String
        var fontSize: Double
        var tabWidth: Int
        var insertSpaces: Bool
        var showLineNumbers: Bool
        var highlightCurrentLine: Bool
        var showIndentGuides: Bool
        var wrapLines: Bool
    }

    static var editor: EditorSettings {
        EditorSettings(
            theme: theme,
            fontName: store.string(forKey: Key.fontName) ?? "",
            fontSize: min(max(store.double(forKey: Key.fontSize), 6), 72),
            tabWidth: min(max(store.integer(forKey: Key.tabWidth), 1), 16),
            insertSpaces: store.bool(forKey: Key.insertSpaces),
            showLineNumbers: store.bool(forKey: Key.showLineNumbers),
            highlightCurrentLine: store.bool(forKey: Key.highlightCurrentLine),
            showIndentGuides: store.bool(forKey: Key.showIndentGuides),
            wrapLines: store.bool(forKey: Key.wrapLines))
    }

    /// Installed monospaced font families, for the font picker. Computed once:
    /// it instantiates every fixed-pitch font.
    @MainActor static let monospacedFontFamilies: [String] = {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        let families = Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName }.filter { !$0.hasPrefix(".") })
        return families.sorted()
    }()
}

/// Fonts and colours for window chrome (find bar, status bar, sidebar), which
/// the Classic theme restyles as Mac OS 9 Platinum.
enum Chrome {
    static var isClassic: Bool { Preferences.theme == .classic }

    /// Platinum greys and highlight, from the Mac OS 9 Appearance defaults.
    enum Platinum {
        static let bar = NSColor(srgbRed: 0xDD / 255, green: 0xDD / 255, blue: 0xDD / 255, alpha: 1)
        static let panel = NSColor(srgbRed: 0xEE / 255, green: 0xEE / 255, blue: 0xEE / 255, alpha: 1)
        static let shadow = NSColor(srgbRed: 0x99 / 255, green: 0x99 / 255, blue: 0x99 / 255, alpha: 1)
        static let highlight = NSColor(srgbRed: 0xCC / 255, green: 0xCC / 255, blue: 0xFF / 255, alpha: 1)
        static let accent = NSColor(srgbRed: 0x33 / 255, green: 0x33 / 255, blue: 0x99 / 255, alpha: 1)
        /// Window frame and title bar.
        static let frame = NSColor(srgbRed: 0xCC / 255, green: 0xCC / 255, blue: 0xCC / 255, alpha: 1)
        static let dark = NSColor(srgbRed: 0x55 / 255, green: 0x55 / 255, blue: 0x55 / 255, alpha: 1)
        static let pressed = NSColor(srgbRed: 0x88 / 255, green: 0x88 / 255, blue: 0x88 / 255, alpha: 1)
        static let boxShade = NSColor(srgbRed: 0xAA / 255, green: 0xAA / 255, blue: 0xAA / 255, alpha: 1)
        static let stripe = NSColor(srgbRed: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255, alpha: 1)
        static let inactiveText = NSColor(srgbRed: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255, alpha: 1)
        /// Scroll thumb, tinted with the highlight colour as in Mac OS 9.
        static let thumb = NSColor(srgbRed: 0xCC / 255, green: 0xCC / 255, blue: 0xFF / 255, alpha: 1)
        static let thumbShadow = NSColor(srgbRed: 0x66 / 255, green: 0x66 / 255, blue: 0x99 / 255, alpha: 1)
    }

    static let classicFontName = "ChicagoFLF"

    static func font(ofSize size: CGFloat = NSFont.smallSystemFontSize) -> NSFont {
        if isClassic, let chicago = NSFont(name: classicFontName, size: size) {
            return chicago
        }
        return .systemFont(ofSize: size)
    }

    /// Registers the bundled ChicagoFLF font (public domain) for this process.
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "ChicagoFLF", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
