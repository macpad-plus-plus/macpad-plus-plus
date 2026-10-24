import AppKit
import Scintilla
import SwiftUI

/// Tools ▸ Password Generator…: a floating panel that makes a password, copies
/// it or inserts it at the caret of the front document. Its options are kept
/// between launches.
final class PasswordGeneratorPanel: NSWindowController {
    static let shared = PasswordGeneratorPanel()

    private init() {
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: true)
        panel.title = String(localized: "Password Generator")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isRestorable = false
        panel.contentViewController = NSHostingController(rootView: PasswordGeneratorView().frame(width: 380).fixedSize())
        super.init(window: panel)
        panel.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The editor of the front document window, which a panel never replaces as main window.
    @MainActor static var frontEditor: ScintillaEditor? {
        (NSApp.mainWindow?.windowController as? DocumentWindowController)?.editorController?.editor
    }
}

private struct PasswordGeneratorView: View {
    @AppStorage("passwordLength") private var length = PasswordGenerator().length
    @AppStorage("passwordUppercase") private var uppercase = PasswordGenerator().minimumUppercase
    @AppStorage("passwordLowercase") private var lowercase = PasswordGenerator().minimumLowercase
    @AppStorage("passwordDigits") private var digits = PasswordGenerator().minimumDigits
    @AppStorage("passwordSymbols") private var symbols = PasswordGenerator().minimumSymbols
    @AppStorage("passwordExcludeAmbiguous") private var excludeAmbiguous = false

    @State private var password = ""
    @State private var copied = false

    private var generator: PasswordGenerator {
        PasswordGenerator(length: length, minimumUppercase: uppercase, minimumLowercase: lowercase,
                          minimumDigits: digits, minimumSymbols: symbols, excludeAmbiguous: excludeAmbiguous)
    }

    var body: some View {
        Form {
            Section {
                countRow("Length", value: lengthBinding, range: PasswordGenerator.lengthRange)
            }
            Section {
                countRow("Uppercase (A–Z)", value: countBinding(0), range: 0...length)
                countRow("Lowercase (a–z)", value: countBinding(1), range: 0...length)
                countRow("Numbers (0–9)", value: countBinding(2), range: 0...length)
                countRow("Symbols (!#$%…)", value: countBinding(3), range: 0...length)
            } footer: {
                Text("The length is shared out among the kinds of character. 0 leaves a kind out.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Exclude ambiguous characters", isOn: $excludeAmbiguous)
            }
            Section {
                result
            }
        }
        .formStyle(.grouped)
        // The panel is sized to fit; a grouped form would still scroll and bounce.
        .scrollDisabled(true)
        .onAppear(perform: regenerate)
        .onChange(of: generator) { regenerate() }
    }

    /// Changing the length shares it out again (see PasswordGenerator.setLength).
    private var lengthBinding: Binding<Int> {
        Binding(get: { length }, set: { newValue in
            var updated = generator
            updated.setLength(newValue)
            store(updated)
        })
    }

    /// Changing one kind adjusts the others (see PasswordGenerator.setCount).
    private func countBinding(_ index: Int) -> Binding<Int> {
        Binding(get: { generator.counts[index] }, set: { newValue in
            var updated = generator
            updated.setCount(newValue, at: index)
            store(updated)
        })
    }

    private func store(_ updated: PasswordGenerator) {
        length = updated.length
        (uppercase, lowercase, digits, symbols) = (updated.counts[0], updated.counts[1], updated.counts[2], updated.counts[3])
    }

    private func countRow(_ title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                Stepper(title, value: value, in: range)
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder private var result: some View {
        switch generator.problem {
        case .noKinds:
            Text("Choose at least one kind of character.")
                .foregroundStyle(.secondary)
        case .minimumsExceedLength:
            Text("The minimums add up to more than the length (\(length)).")
                .foregroundStyle(.secondary)
        case nil:
            VStack(alignment: .leading, spacing: 10) {
                Text(password)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button {
                        regenerate()
                    } label: {
                        Label("New Password", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    Button(copied ? "Copied" : "Copy", action: copy)
                    Button("Insert", action: insert)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func regenerate() {
        // The counts always add up to the length; older or odd settings are shared out again.
        if generator.counts.reduce(0, +) != length || generator.counts.contains(where: { $0 < 0 }) {
            var updated = generator
            updated.setLength(length)
            store(updated)
        }
        password = generator.generate() ?? ""
        copied = false
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)
        // Asks clipboard managers not to keep it (nspasteboard.org convention).
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        copied = true
    }

    private func insert() {
        guard let editor = PasswordGeneratorPanel.frontEditor, !editor.isReadOnly else {
            NSSound.beep()
            return
        }
        editor.send(SCI_REPLACESEL, 0, string: password)
        regenerate()
    }
}
