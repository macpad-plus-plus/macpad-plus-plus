import AppKit

/// A comparison of two open documents, shown as a tab next to the first one,
/// as in OxyPad. It compares snapshots; Compare Again takes new ones.
final class CompareWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    /// Open comparisons; a window controller is not otherwise retained.
    private static var open: Set<CompareWindowController> = []

    private weak var leftDocument: TextDocument?
    private weak var rightDocument: TextDocument?
    private let compareController = CompareViewController()
    private var toolbar: NSToolbar?
    private var appliedClassic: Bool?

    /// Opens a comparison of `left` with `right` as a tab after `left`'s.
    static func compare(_ left: TextDocument, with right: TextDocument) {
        guard let sources = sources(left, right) else { return NSSound.beep() }
        let controller = CompareWindowController(left: left, right: right)
        controller.compareController.show(left: sources.0, right: sources.1)
        open.insert(controller)
        guard let window = controller.window else { return }
        if let sourceWindow = left.windowControllers.first?.window {
            window.setFrame(sourceWindow.frame, display: false)
            sourceWindow.addTabbedWindow(window, ordered: .above)
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// Current text, title and language of both documents; nil if one has no editor.
    private static func sources(_ left: TextDocument, _ right: TextDocument) -> (CompareViewController.Source, CompareViewController.Source)? {
        guard let leftEditor = left.editor, let rightEditor = right.editor else { return nil }
        func source(_ document: TextDocument, _ editor: ScintillaEditor) -> CompareViewController.Source {
            CompareViewController.Source(title: document.displayName, text: String(decoding: editor.utf8Text(), as: UTF8.self),
                                         language: editor.language)
        }
        return (source(left, leftEditor), source(right, rightEditor))
    }

    private init(left: TextDocument, right: TextDocument) {
        leftDocument = left
        rightDocument = right
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = DocumentWindowController.tabbingIdentifier
        window.isRestorable = false
        window.title = "\(left.displayName ?? "") ↔ \(right.displayName ?? "")"
        window.contentViewController = compareController
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "CompareToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        self.toolbar = toolbar

        compareController.reload = { [weak self] in
            guard let left = self?.leftDocument, let right = self?.rightDocument else { return nil }
            self?.window?.title = "\(left.displayName ?? "") ↔ \(right.displayName ?? "")"
            return Self.sources(left, right)
        }
        applyChrome()
        NotificationCenter.default.addObserver(self, selector: #selector(applyChrome), name: Preferences.didChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The Classic theme dresses this tab like the documents' (see DocumentWindowController).
    @objc private func applyChrome() {
        guard let window, appliedClassic != Chrome.isClassic else { return }
        appliedClassic = Chrome.isClassic
        ClassicWindowFrame.apply(to: window, toolbar: toolbar)
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.remove(self)
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarItems.previousDifference, ToolbarItems.nextDifference, ToolbarItems.compareAgain, ToolbarItems.settings]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        ToolbarItems.make(itemIdentifier, window: window)
    }
}

/// "Compare With": the other open documents, for the toolbar button and the
/// Tab menu. Built each time it opens, for the document of `source`'s window
/// (the front window when nil).
final class CompareMenu: NSMenu, NSMenuDelegate {
    private weak var source: NSWindow?

    init(source: NSWindow?) {
        self.source = source
        super.init(title: String(localized: "Compare With"))
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var sourceDocument: TextDocument? {
        (source ?? NSApp.mainWindow)?.windowController?.document as? TextDocument
    }

    /// Open documents other than `document`: its window's tabs first, in tab order.
    static func candidates(for document: TextDocument) -> [TextDocument] {
        let window = document.windowControllers.first?.window
        let tabs = (window?.tabGroup?.windows ?? []).compactMap { $0.windowController?.document as? TextDocument }
        let others = NSDocumentController.shared.documents.compactMap { $0 as? TextDocument }.filter { !tabs.contains($0) }
        return (tabs + others).filter { $0 !== document && $0.editor != nil }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        removeAllItems()
        guard let document = sourceDocument else { return }
        let header = addItem(withTitle: String(localized: "Compare “\(document.displayName ?? "")” with"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        let candidates = Self.candidates(for: document)
        if candidates.isEmpty {
            addItem(withTitle: String(localized: "No Other Open Documents"), action: nil, keyEquivalent: "").isEnabled = false
        }
        for candidate in candidates {
            let item = addItem(withTitle: candidate.displayName, action: #selector(compare(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate
            item.toolTip = candidate.fileURL?.path
            item.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        }
    }

    @objc private func compare(_ sender: NSMenuItem) {
        guard let document = sourceDocument, let other = sender.representedObject as? TextDocument else { return }
        CompareWindowController.compare(document, with: other)
    }
}
