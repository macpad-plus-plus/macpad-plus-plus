import AppKit

/// One window per document. Documents open as native macOS window tabs, which
/// play the role of Notepad++'s tab bar; the sidebar holds its side panels.
final class DocumentWindowController: NSWindowController, NSToolbarDelegate {
    static let tabbingIdentifier = "com.doclaudio.MacPad.document"

    init(document: TextDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingIdentifier
        // Open tabs come back through SessionStore, which also restores unsaved
        // content; AppKit's own window restoration would duplicate them.
        window.isRestorable = false
        window.contentViewController = DocumentSplitViewController(editorController: EditorViewController(document: document))
        window.setContentSize(NSSize(width: 1000, height: 680))
        window.center()
        super.init(window: window)
        windowFrameAutosaveName = "DocumentWindow"

        let toolbar = NSToolbar(identifier: "DocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        // Returning to the app, or switching to this tab, checks whether another
        // app changed or deleted the file.
        NotificationCenter.default.addObserver(
            self, selector: #selector(checkForExternalChanges),
            name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(checkForExternalChanges),
            name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func checkForExternalChanges() {
        guard let window, window.isKeyWindow, let document = document as? TextDocument else { return }
        document.checkForExternalChanges(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var editorController: EditorViewController? {
        (contentViewController as? DocumentSplitViewController)?.editorController
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Keep the tab bar visible even with a single document, like Notepad++.
        if let window, let group = window.tabGroup, !group.isTabBarVisible {
            window.toggleTabBar(nil)
        }
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        nil
    }
}
