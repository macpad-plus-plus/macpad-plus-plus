import AppKit
import SwiftUI

/// The Settings window (⌘,): toolbar tabs, each a SwiftUI form.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        // No crossfade: the content swaps at once and only the window animates,
        // as in Safari's settings.
        tabs.transitionOptions = [.allowUserInteraction]
        tabs.canPropagateSelectedChildViewControllerTitle = true
        tabs.addTabViewItem(Self.tab(String(localized: "General"), symbol: "gearshape", GeneralSettings()))
        tabs.addTabViewItem(Self.tab(String(localized: "Editor"), symbol: "character.cursor.ibeam", EditorSettingsView()))
        tabs.addTabViewItem(Self.tab(String(localized: "Appearance"), symbol: "paintpalette", AppearanceSettings()))
        tabs.addTabViewItem(Self.tab(String(localized: "New Documents"), symbol: "doc.badge.plus", NewDocumentSettings()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isRestorable = false
        super.init(window: window)
        if let first = tabs.tabViewItems.first {
            window.setContentSize(SettingsTabViewController.contentSize(of: first))
        }
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func tab(_ title: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: AnyView(view.frame(width: 480).fixedSize()))
        // The tab controller sizes the window itself (see SettingsTabViewController);
        // letting SwiftUI publish a preferred size would add a second, later resize.
        host.sizingOptions = []
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

/// Resizes the window to the incoming tab's measured size in one animation,
/// at the moment the tab is chosen.
private final class SettingsTabViewController: NSTabViewController {
    /// The SwiftUI form's ideal size at the settings width.
    static func contentSize(of item: NSTabViewItem) -> NSSize {
        guard let host = item.viewController as? NSHostingController<AnyView> else { return NSSize(width: 480, height: 300) }
        return host.sizeThatFits(in: NSSize(width: 480, height: 2000))
    }

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, willSelect: tabViewItem)
        guard let tabViewItem, let window = view.window else { return }
        let size = Self.contentSize(of: tabViewItem)
        let current = window.contentRect(forFrameRect: window.frame)
        // Keep the top edge in place, as macOS settings windows do.
        let target = NSRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height)
        let frame = window.frameRect(forContentRect: target)
        guard window.isVisible else { return window.setFrame(frame, display: false) }
        // Non-blocking, short animation; setFrame(_:display:animate:) blocks while it runs.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }
}

private struct GeneralSettings: View {
    @AppStorage(Preferences.Key.restoreSession) private var restoreSession = true
    @AppStorage(Preferences.Key.showHiddenFiles) private var showHiddenFiles = false
    @State private var language = AppLanguage.selected
    @State private var confirmRelaunch = false

    var body: some View {
        Form {
            Section {
                Picker("Interface Language", selection: $language) {
                    Text("System Default").tag("")
                    Divider()
                    ForEach(AppLanguage.available, id: \.self) { code in
                        Text(verbatim: AppLanguage.name(of: code)).tag(code)
                    }
                }
                .onChange(of: language) { _, newValue in
                    AppLanguage.selected = newValue
                    confirmRelaunch = true
                }
            } header: {
                Text("Interface Language")
            } footer: {
                Text("Missing a language? Translations are simple text files that anyone can add. See TRANSLATING.md in the project repository.")
            }
            Section {
                Toggle("Remember open documents and unsaved changes", isOn: $restoreSession)
                Text("Quitting never asks to save: open tabs, unsaved edits and untitled documents come back at the next launch, like Notepad++'s session snapshot. Unsaved changes are backed up every \(Int(SessionStore.backupInterval)) seconds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Session")
            }
            Section {
                Toggle("Show hidden files", isOn: $showHiddenFiles)
            } header: {
                Text("Folder Workspace")
            }
        }
        .formStyle(.grouped)
        .alert("Relaunch MacPad++ to change the language?", isPresented: $confirmRelaunch) {
            Button("Relaunch Now") { AppLanguage.relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            if restoreSession {
                Text("Your open documents, including unsaved changes, will come back.")
            } else {
                Text("You will be asked to save any unsaved changes first.")
            }
        }
    }
}

private struct EditorSettingsView: View {
    @AppStorage(Preferences.Key.fontName) private var fontName = ""
    @AppStorage(Preferences.Key.fontSize) private var fontSize = 13.0
    @AppStorage(Preferences.Key.tabWidth) private var tabWidth = 4
    @AppStorage(Preferences.Key.insertSpaces) private var insertSpaces = false
    @AppStorage(Preferences.Key.showLineNumbers) private var showLineNumbers = true
    @AppStorage(Preferences.Key.highlightCurrentLine) private var highlightCurrentLine = true
    @AppStorage(Preferences.Key.showIndentGuides) private var showIndentGuides = true
    @AppStorage(Preferences.Key.wrapLines) private var wrapLines = false

    private let families = Preferences.monospacedFontFamilies

    var body: some View {
        Form {
            Section {
                // Plain titles: rendering every family in its own face loads dozens of fonts.
                Picker("Font", selection: $fontName) {
                    Text("Automatic").tag("")
                    Divider()
                    ForEach(families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Stepper(value: $fontSize, in: 8...36, step: 1) {
                    LabeledContent("Size", value: String(localized: "\(Int(fontSize)) pt"))
                }
                Text(verbatim: "func greet() { return \"0O 1lI {}[]\" }")
                    .font(.custom(fontName.isEmpty ? "SF Mono" : fontName, size: min(fontSize, 18)))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Font")
            } footer: {
                Text("Automatic uses SF Mono, or Monaco with the Classic theme.")
            }
            Section {
                Stepper(value: $tabWidth, in: 1...16) {
                    LabeledContent("Tab width", value: String(localized: "Spaces: \(tabWidth)"))
                }
                Toggle("Insert spaces instead of tabs", isOn: $insertSpaces)
            } header: {
                Text("Indentation")
            }
            Section {
                Toggle("Show line numbers", isOn: $showLineNumbers)
                Toggle("Highlight current line", isOn: $highlightCurrentLine)
                Toggle("Show indentation guides", isOn: $showIndentGuides)
                Toggle("Wrap lines in new windows", isOn: $wrapLines)
            } header: {
                Text("Display")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @AppStorage(Preferences.Key.theme) private var theme = Preferences.Theme.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(Preferences.Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Classic recreates the Mac OS 9 Platinum look: Monaco, lavender highlight, platinum bars and the Chicago font.")
            }
            Section("Preview") {
                ThemePreview(theme: Preferences.Theme(rawValue: theme) ?? .system)
            }
        }
        .formStyle(.grouped)
    }
}

/// A few lines of Swift rendered with the selected theme's colours.
private struct ThemePreview: View {
    let theme: Preferences.Theme
    @Environment(\.colorScheme) private var colorScheme

    private var palette: EditorTheme {
        switch theme {
        case .classic: .classic
        case .light: .light
        case .dark: .dark
        case .system: colorScheme == .dark ? .dark : .light
        }
    }

    var body: some View {
        let p = palette
        let font = Font.custom(p.preferredFont ?? "SF Mono", size: 12)
        VStack(alignment: .leading, spacing: 2) {
            (color(p, .comment, "// Greets the world\n")
                + color(p, .keyword, "func ") + text(p, "greet(")
                + color(p, .type, "name") + text(p, ": ") + color(p, .type, "String") + text(p, ") {\n    ")
                + color(p, .keyword, "let ") + text(p, "count = ") + color(p, .number, "42") + text(p, "\n    print(")
                + color(p, .string, "\"Hello, \\(name)!\"") + text(p, ")\n}"))
                .font(font)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: p.background))
        .clipShape(RoundedRectangle(cornerRadius: theme == .classic ? 0 : 6))
    }

    private func text(_ p: EditorTheme, _ string: String) -> Text {
        Text(string).foregroundColor(Color(rgb: p.foreground))
    }

    private func color(_ p: EditorTheme, _ kind: TokenKind, _ string: String) -> Text {
        let style = p.tokens[kind]
        var text = Text(string).foregroundColor(Color(rgb: style?.color ?? p.foreground))
        if style?.bold == true { text = text.bold() }
        if style?.italic == true { text = text.italic() }
        return text
    }
}

private struct NewDocumentSettings: View {
    @AppStorage(Preferences.Key.defaultEncoding) private var encoding = TextEncoding.utf8.rawValue
    @AppStorage(Preferences.Key.defaultLineEnding) private var lineEnding = LineEnding.lf.rawValue

    var body: some View {
        Form {
            Picker("Encoding", selection: $encoding) {
                ForEach(TextEncoding.allCases, id: \.rawValue) { encoding in
                    Text(encoding.displayName).tag(encoding.rawValue)
                }
            }
            Picker("Line endings", selection: $lineEnding) {
                ForEach(LineEnding.allCases, id: \.rawValue) { lineEnding in
                    Text(lineEnding.displayName).tag(lineEnding.rawValue)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB, red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}
