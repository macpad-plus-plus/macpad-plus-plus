import AppKit

/// The Tab menu: what Notepad++ has on a tab's context menu. In the menu bar
/// it acts on the front tab through the responder chain; for the Classic
/// theme's tabs it is built with an explicit target, the clicked tab.
@MainActor
enum TabMenu {
    /// The items, sent to `target` or, when nil, along the responder chain.
    static func items(target: AnyObject? = nil, keyEquivalents: Bool) -> [NSMenuItem] {
        func item(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalents ? key : "")
            if keyEquivalents, !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
            item.target = target
            return item
        }
        var items: [NSMenuItem] = []
        if target != nil {
            items.append(item(String(localized: "Close Tab"), #selector(NSWindow.performClose(_:))))
            items.append(.separator())
        }
        items.append(item(String(localized: "Pin Tab"), #selector(DocumentWindowController.togglePinTab(_:)), "p", [.command, .option]))
        items.append(item(String(localized: "Rename…"), #selector(DocumentWindowController.renameTab(_:))))
        items.append(item(String(localized: "Read-Only"), #selector(DocumentWindowController.toggleReadOnly(_:))))
        items.append(item(String(localized: "Revert to Saved"), #selector(DocumentWindowController.revertTabToSaved(_:))))

        let colors = NSMenu(title: String(localized: "Tab Color"))
        let none = item(String(localized: "None"), #selector(DocumentWindowController.setTabColor(_:)))
        none.representedObject = ""
        colors.addItem(none)
        colors.addItem(.separator())
        for color in TabColor.allCases {
            let colorItem = item(color.displayName, #selector(DocumentWindowController.setTabColor(_:)))
            colorItem.representedObject = color.rawValue
            colorItem.image = swatch(color.color)
            colors.addItem(colorItem)
        }
        let colorMenu = NSMenuItem(title: colors.title, action: nil, keyEquivalent: "")
        colorMenu.submenu = colors
        items.append(colorMenu)

        let compare = NSMenuItem(title: String(localized: "Compare With"), action: nil, keyEquivalent: "")
        compare.submenu = CompareMenu(source: (target as? NSWindowController)?.window)
        items.append(compare)

        items.append(.separator())
        items.append(item(String(localized: "Reveal in Finder"), #selector(DocumentWindowController.revealInFinder(_:)), "r", [.command, .option]))
        items.append(item(String(localized: "Open in Terminal"), #selector(DocumentWindowController.openInTerminal(_:))))
        let copy = NSMenu(title: String(localized: "Copy Path"))
        copy.addItem(item(String(localized: "Folder Path"), #selector(DocumentWindowController.copyFolderPath(_:))))
        copy.addItem(item(String(localized: "File Name"), #selector(DocumentWindowController.copyFileName(_:))))
        copy.addItem(item(String(localized: "Full Path"), #selector(DocumentWindowController.copyFullPath(_:)), "c", [.command, .control]))
        let copyMenu = NSMenuItem(title: copy.title, action: nil, keyEquivalent: "")
        copyMenu.submenu = copy
        items.append(copyMenu)

        items.append(.separator())
        items.append(item(String(localized: "Move Tab to Start"), #selector(DocumentWindowController.moveTabToStart(_:))))
        items.append(item(String(localized: "Move Tab to End"), #selector(DocumentWindowController.moveTabToEnd(_:))))
        let moveToWindow = NSMenuItem(title: String(localized: "Move Tab to Window"), action: nil, keyEquivalent: "")
        moveToWindow.submenu = MoveToWindowMenu(source: (target as? NSWindowController)?.window)
        items.append(moveToWindow)
        if target != nil {
            items.append(item(String(localized: "Move Tab to New Window"), #selector(NSWindow.moveTabToNewWindow(_:))))
        }
        return items
    }

    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}

/// "Move Tab to Window": the other windows, to send a tab back to one of them
/// (dragging tabs between windows is not available with the drawn tab bar).
/// Built each time it opens, for `source`'s tab (the front tab when nil).
@MainActor
final class MoveToWindowMenu: NSMenu, NSMenuDelegate {
    private weak var source: NSWindow?

    init(source: NSWindow?) {
        self.source = source
        super.init(title: String(localized: "Move Tab to Window"))
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// One window per tab group other than the source's, front to back.
    static func destinations(for window: NSWindow) -> [NSWindow] {
        var seen: Set<ObjectIdentifier> = [ObjectIdentifier(window.tabGroup ?? window)]
        return NSApp.orderedWindows.filter { candidate in
            candidate.tabbingIdentifier == DocumentWindowController.tabbingIdentifier
                && seen.insert(ObjectIdentifier(candidate.tabGroup ?? candidate)).inserted
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        removeAllItems()
        guard let window = source ?? NSApp.mainWindow else { return }
        let destinations = Self.destinations(for: window)
        if destinations.isEmpty {
            addItem(withTitle: String(localized: "No Other Windows"), action: nil, keyEquivalent: "").isEnabled = false
        }
        for destination in destinations {
            let front = destination.tabGroup?.selectedWindow ?? destination
            let count = destination.tabGroup?.windows.count ?? 1
            let title = count > 1 ? String(localized: "\(front.title) (\(count) tabs)") : front.title
            let item = addItem(withTitle: title, action: #selector(move(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = destination
        }
    }

    @objc private func move(_ sender: NSMenuItem) {
        guard let window = source ?? NSApp.mainWindow, let destination = sender.representedObject as? NSWindow else { return }
        let last = destination.tabGroup?.windows.last ?? destination
        last.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        TabOrder.keepPinnedFirst(in: window)
    }
}
