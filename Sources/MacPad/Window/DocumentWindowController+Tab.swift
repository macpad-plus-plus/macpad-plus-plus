import AppKit

/// What Notepad++ offers on a tab's context menu. macOS draws the native tab
/// bar and its menu, so these live in the Tab menu of the menu bar, acting on
/// the front tab; the Classic theme, which draws its own tabs, also shows
/// them when a tab is right-clicked (see `TabMenu`).
extension DocumentWindowController: NSMenuItemValidation {
    private var textDocument: TextDocument? { document as? TextDocument }

    // MARK: Pin and color

    @objc func togglePinTab(_ sender: Any?) {
        guard let document = textDocument else { return }
        document.isPinned.toggle()
        if let window { TabOrder.keepPinnedFirst(in: window, moved: window) }
    }

    @objc func setTabColor(_ sender: NSMenuItem) {
        textDocument?.tabColor = (sender.representedObject as? String).flatMap(TabColor.init(rawValue:))
    }

    /// Shows the pin and the color in the native tab.
    @objc func updateTabAccessory() {
        guard let window, let document = textDocument else { return }
        var views: [NSView] = []
        if let color = document.tabColor {
            views.append(TabDot(color: color.color))
        }
        if document.isPinned, let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: String(localized: "Pinned")) {
            let image = NSImageView(image: pin)
            image.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
            image.contentTintColor = .secondaryLabelColor
            views.append(image)
        }
        if views.isEmpty {
            window.tab.accessoryView = nil
        } else {
            let stack = NSStackView(views: views)
            stack.spacing = 4
            window.tab.accessoryView = stack
        }
    }

    // MARK: Rename and read-only

    /// Untitled documents get a new name; saved ones are saved under one, as
    /// in Notepad++.
    @objc func renameTab(_ sender: Any?) {
        guard let document = textDocument, let window else { return }
        guard document.fileURL == nil else {
            document.saveAs(sender)
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Tab")
        alert.informativeText = String(localized: "The name shows on the tab until the document is saved.")
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(string: document.displayName)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard response == .alertFirstButtonReturn, !name.isEmpty else { return }
                document.customName = name
                self.synchronizeWindowTitleWithDocumentName()
            }
        }
    }

    @objc func toggleReadOnly(_ sender: Any?) {
        textDocument?.isReadOnly.toggle()
    }

    // MARK: File

    @objc func revealInFinder(_ sender: Any?) {
        guard let url = textDocument?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func openInTerminal(_ sender: Any?) {
        guard let folder = textDocument?.fileURL?.deletingLastPathComponent() else { return }
        do {
            try Terminal.open(folder, choice: Preferences.terminal, command: Preferences.terminalCommand)
        } catch {
            textDocument?.presentError(error)
        }
    }

    @objc func copyFolderPath(_ sender: Any?) {
        copyToPasteboard(textDocument?.fileURL?.deletingLastPathComponent().path)
    }

    @objc func copyFileName(_ sender: Any?) {
        copyToPasteboard(textDocument?.fileURL?.lastPathComponent)
    }

    @objc func copyFullPath(_ sender: Any?) {
        copyToPasteboard(textDocument?.fileURL?.path)
    }

    private func copyToPasteboard(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Revert

    /// Throws away the unsaved changes after the system's confirmation.
    @objc func revertTabToSaved(_ sender: Any?) {
        guard let window else { return }
        // The confirmation sheet belongs to this tab, so show it first.
        window.tabGroup?.selectedWindow = window
        textDocument?.revertToSaved(sender)
    }

    // MARK: Order

    @objc func moveTabToStart(_ sender: Any?) {
        guard let window else { return }
        TabOrder.move(window, toEnd: false)
    }

    @objc func moveTabToEnd(_ sender: Any?) {
        guard let window else { return }
        TabOrder.move(window, toEnd: true)
    }

    // MARK: Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let document = textDocument else { return false }
        let hasFile = document.fileURL != nil
        switch menuItem.action {
        case #selector(togglePinTab(_:)):
            menuItem.title = document.isPinned ? String(localized: "Unpin Tab") : String(localized: "Pin Tab")
        case #selector(setTabColor(_:)):
            menuItem.state = (menuItem.representedObject as? String) == (document.tabColor?.rawValue ?? "") ? .on : .off
        case #selector(renameTab(_:)):
            menuItem.title = hasFile ? String(localized: "Rename… (Save As)") : String(localized: "Rename…")
        case #selector(toggleReadOnly(_:)):
            menuItem.state = document.isReadOnly ? .on : .off
            return !document.isFollowing
        case #selector(revertTabToSaved(_:)):
            return hasFile && document.isDocumentEdited && !document.isFollowing
        case #selector(revealInFinder(_:)), #selector(openInTerminal(_:)),
             #selector(copyFolderPath(_:)), #selector(copyFileName(_:)), #selector(copyFullPath(_:)):
            return hasFile
        case #selector(moveTabToStart(_:)):
            return window.map { TabOrder.canMove($0, toEnd: false) } ?? false
        case #selector(moveTabToEnd(_:)):
            return window.map { TabOrder.canMove($0, toEnd: true) } ?? false
        default:
            break
        }
        return true
    }
}

/// A small dot in a tab's color.
private final class TabDot: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        setContentHuggingPriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 8, height: 8) }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
    }
}

/// Tab order in a window: pinned tabs stay first, like Notepad++'s, and each
/// tab moves within its kind (pinned or not).
@MainActor
enum TabOrder {
    private static func isPinned(_ window: NSWindow) -> Bool {
        (window.windowController?.document as? TextDocument)?.isPinned ?? false
    }

    /// The indexes a tab can move between: those of its kind.
    private static func bounds(of window: NSWindow, in windows: [NSWindow]) -> ClosedRange<Int> {
        let pinned = windows.filter(isPinned).count
        return isPinned(window) ? 0...max(0, pinned - 1) : pinned...max(pinned, windows.count - 1)
    }

    static func canMove(_ window: NSWindow, toEnd: Bool) -> Bool {
        guard let windows = window.tabGroup?.windows, let index = windows.firstIndex(of: window) else { return false }
        let range = bounds(of: window, in: windows)
        return index != (toEnd ? range.upperBound : range.lowerBound)
    }

    /// Moves a tab to `index`, kept within its kind. Used when dragging a tab.
    static func move(_ window: NSWindow, to index: Int) {
        guard let group = window.tabGroup else { return }
        let range = bounds(of: window, in: group.windows)
        place(window, at: min(max(index, range.lowerBound), range.upperBound), in: group)
    }

    static func move(_ window: NSWindow, toEnd: Bool) {
        guard let group = window.tabGroup else { return }
        let range = bounds(of: window, in: group.windows)
        place(window, at: toEnd ? range.upperBound : range.lowerBound, in: group)
    }

    /// Moves pinned tabs before the others, keeping each kind's order; a tab
    /// just pinned goes after those already pinned.
    static func keepPinnedFirst(in window: NSWindow, moved: NSWindow? = nil) {
        guard let group = window.tabGroup else { return }
        let windows = group.windows
        var pinned = windows.filter(isPinned)
        let others = windows.filter { !isPinned($0) }
        if let moved, let index = pinned.firstIndex(of: moved) {
            pinned.append(pinned.remove(at: index))
        }
        let order = pinned + others
        guard order != windows else { return }
        let selected = group.selectedWindow
        for (index, each) in order.enumerated() where group.windows.firstIndex(of: each) != index {
            place(each, at: index, in: group)
        }
        if let selected { group.selectedWindow = selected }
    }

    private static func place(_ window: NSWindow, at index: Int, in group: NSWindowTabGroup) {
        guard group.windows.firstIndex(of: window) != index else { return }
        let selected = group.selectedWindow
        group.removeWindow(window)
        group.insertWindow(window, at: min(index, group.windows.count))
        if let selected { group.selectedWindow = selected }
    }
}
