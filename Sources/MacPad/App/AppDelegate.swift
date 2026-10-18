import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Unit tests run inside the app; keep them away from the user's session.
    nonisolated static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func applicationWillFinishLaunching(_ notification: Notification) {
        Preferences.register()
        Chrome.registerFonts()
        guard !Self.isRunningTests, Preferences.restoreSession else { return }
        // Before files passed from Finder are opened, so they join the restored tabs.
        SessionStore.shared.restore()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        SessionStore.shared.startPeriodicBackups()
    }

    @objc func showAbout(_ sender: Any?) {
        AboutPanel.show()
    }

    @objc func openWebsite(_ sender: Any?) {
        NSWorkspace.shared.open(AboutPanel.websiteURL)
    }

    @objc func openRepository(_ sender: Any?) {
        NSWorkspace.shared.open(AboutPanel.repositoryURL)
    }

    @objc func reportIssue(_ sender: Any?) {
        NSWorkspace.shared.open(AboutPanel.issuesURL)
    }

    @objc func openReleaseNotes(_ sender: Any?) {
        NSWorkspace.shared.open(AboutPanel.releasesURL)
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(sender)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.documents.isEmpty
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
