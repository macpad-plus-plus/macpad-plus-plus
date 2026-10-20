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
