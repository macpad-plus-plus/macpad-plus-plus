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
        self.toolbar = toolbar
        applyChrome()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyChrome),
            name: Preferences.didChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateSwitcherVisibility),
            name: DocumentSplitViewController.collapsedDidChange, object: nil)

        // Returning to the app, or switching to this tab, checks whether another
        // app changed or deleted the file.
        NotificationCenter.default.addObserver(
            self, selector: #selector(checkForExternalChanges),
            name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(checkForExternalChanges),
            name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    /// Kept while the Classic theme replaces the title bar, so it can come back.
    private var toolbar: NSToolbar?

    private var appliedClassic: Bool?

    /// Only on theme changes: toggling the tab bar writes a default, which
    /// would otherwise call back in here.
    @objc private func applyChrome() {
        guard let window, appliedClassic != Chrome.isClassic else { return }
        appliedClassic = Chrome.isClassic
        ClassicWindowFrame.apply(to: window, toolbar: toolbar)
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
        [.toggleSidebar, .flexibleSpace, SidebarSwitcher.itemIdentifier, .sidebarTrackingSeparator, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == SidebarSwitcher.itemIdentifier else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = SidebarSwitcher()
        item.label = String(localized: "Sidebar")
        item.isBordered = false
        switcherItem = item
        updateSwitcherVisibility()
        return item
    }

    private weak var switcherItem: NSToolbarItem?

    /// The switcher belongs to the sidebar; hide it while the sidebar is.
    @objc private func updateSwitcherVisibility() {
        guard #available(macOS 15.0, *), let item = switcherItem else { return }
        item.isHidden = UserDefaults.standard.object(forKey: DocumentSplitViewController.collapsedKey) as? Bool ?? true
    }
}
