import AppKit
import SwiftUI

/// Project links and the About window.
@MainActor
enum AboutPanel {
    /// The official website.
    static let websiteURL = infoURL("MacPadWebsiteURL", fallback: "https://macpad-plus-plus.org")
    /// Source code, issues and releases.
    static let repositoryURL = infoURL("MacPadRepositoryURL", fallback: "https://github.com/macpad-plus-plus/macpad-plus-plus")
    static var issuesURL: URL { repositoryURL.appending(path: "issues/new") }
    static var releasesURL: URL { repositoryURL.appending(path: "releases") }
    static var translatingURL: URL { repositoryURL.appending(path: "blob/main/TRANSLATING.md") }

    private static func infoURL(_ key: String, fallback: String) -> URL {
        URL(string: Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback)!
    }

    /// The semantic version, e.g. "0.1.0" (the build number is not shown).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }

    private static var window: NSWindow?

    /// Shows the About window, with the axolotl mascot.
    static func show() {
        if window == nil {
            let host = NSHostingController(rootView: AboutView())
            host.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

/// About MacPad++: mascot, name, version, links and credits.
private struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image("MascotPlusPlus")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 168)
                .accessibilityLabel(Text("MacPad++ axolotl"))
                .padding(.top, 28)

            Text(verbatim: "MacPad++")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 14)
            Text("Version \(AboutPanel.version)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)

            Link(destination: AboutPanel.websiteURL) {
                Text(verbatim: "macpad-plus-plus.org")
            }
            .font(.callout.weight(.medium))
            .padding(.top, 14)

            HStack(spacing: 6) {
                Link("Source Code", destination: AboutPanel.repositoryURL)
                Text(verbatim: "·").foregroundStyle(.tertiary)
                Link("Release Notes", destination: AboutPanel.releasesURL)
                Text(verbatim: "·").foregroundStyle(.tertiary)
                Link("Report an Issue", destination: AboutPanel.issuesURL)
            }
            .font(.caption)
            .padding(.top, 4)

            VStack(spacing: 3) {
                Text("A macOS take on [Notepad++](https://notepad-plus-plus.org) by Don Ho.")
                Text("Editing engine: [Scintilla & Lexilla](https://www.scintilla.org) by Neil Hodgson.")
                Text(verbatim: AboutPanel.copyright)
                    .padding(.top, 6)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 16)
            .padding(.bottom, 22)
        }
        .padding(.horizontal, 32)
        .frame(width: 380)
        .fixedSize()
    }
}
