import AppKit

/// Builds the main menu in code (no MainMenu.xib).
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        for menu in [appMenu(), fileMenu(), editMenu(), searchMenu(), viewMenu(), languageMenu(), formatMenu(), windowMenu(), helpMenu()] {
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            item.submenu = menu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    private static let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MacPad++"

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: appName)
        menu.addItem(withTitle: String(localized: "About \(appName)"), action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        let services = menu.addItem(withTitle: String(localized: "Services"), action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: String(localized: "Services"))
        NSApp.servicesMenu = services.submenu
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Hide \(appName)"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(withTitle: String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit \(appName)"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "File"))
        menu.addItem(withTitle: String(localized: "New"), action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        menu.addItem(withTitle: String(localized: "Open…"), action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        menu.addItem(withTitle: String(localized: "Open Folder…"), action: #selector(DocumentSplitViewController.openFolder(_:)), keyEquivalent: "O")
        let recent = menu.addItem(withTitle: String(localized: "Open Recent"), action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: String(localized: "Open Recent"))
        recentMenu.delegate = RecentDocumentsMenu.shared
        recent.submenu = recentMenu
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(withTitle: String(localized: "Save"), action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        menu.addItem(withTitle: String(localized: "Save As…"), action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        menu.addItem(withTitle: String(localized: "Revert to Saved"), action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Edit"))
        menu.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: String(localized: "Delete"), action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    /// A top-level Search menu, as in Notepad++ and BBEdit.
    private static func searchMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Search"))
        menu.addItem(withTitle: String(localized: "Find…"), action: #selector(EditorViewController.showFind(_:)), keyEquivalent: "f")
        menu.addItem(withTitle: String(localized: "Find and Replace…"), action: #selector(EditorViewController.showFindAndReplace(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: String(localized: "Find Next"), action: #selector(EditorViewController.findNextMatch(_:)), keyEquivalent: "g")
        menu.addItem(withTitle: String(localized: "Find Previous"), action: #selector(EditorViewController.findPreviousMatch(_:)), keyEquivalent: "G")
        menu.addItem(withTitle: String(localized: "Use Selection for Find"), action: #selector(EditorViewController.useSelectionForFind(_:)), keyEquivalent: "e")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Replace"), action: #selector(EditorViewController.replaceMatch(_:)), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Replace All"), action: #selector(EditorViewController.replaceAllMatches(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Go to Line…"), action: #selector(EditorViewController.goToLine(_:)), keyEquivalent: "l")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Hide Find Bar"), action: #selector(EditorViewController.hideFindBar(_:)), keyEquivalent: "")
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "View"))
        menu.addItem(withTitle: String(localized: "Show Sidebar"), action: #selector(DocumentSplitViewController.toggleSidebarPane(_:)), keyEquivalent: "s")
            .keyEquivalentModifierMask = [.command, .control]
        menu.addItem(withTitle: String(localized: "Folder Workspace"), action: #selector(DocumentSplitViewController.showFolderWorkspace(_:)), keyEquivalent: "1")
            .keyEquivalentModifierMask = [.command, .control]
        menu.addItem(withTitle: String(localized: "Function List"), action: #selector(DocumentSplitViewController.showFunctionList(_:)), keyEquivalent: "2")
            .keyEquivalentModifierMask = [.command, .control]
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Word Wrap"), action: #selector(EditorViewController.toggleWordWrap(_:)), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Show Whitespace"), action: #selector(EditorViewController.toggleShowWhitespace(_:)), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Show Line Endings"), action: #selector(EditorViewController.toggleShowLineEndings(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Zoom In"), action: #selector(EditorViewController.zoomInText(_:)), keyEquivalent: "+")
        menu.addItem(withTitle: String(localized: "Zoom Out"), action: #selector(EditorViewController.zoomOutText(_:)), keyEquivalent: "-")
        menu.addItem(withTitle: String(localized: "Actual Size"), action: #selector(EditorViewController.resetTextZoom(_:)), keyEquivalent: "0")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Show Tab Bar"), action: #selector(NSWindow.toggleTabBar(_:)), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Show All Tabs"), action: #selector(NSWindow.toggleTabOverview(_:)), keyEquivalent: "\\")
            .keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Enter Full Screen"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]
        return menu
    }

    private static func languageMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Language"))
        func addItem(for language: Language, to menu: NSMenu) {
            let item = menu.addItem(withTitle: language.name, action: #selector(EditorViewController.selectLanguage(_:)), keyEquivalent: "")
            item.representedObject = language.id
        }

        // Grouped by first letter, as in Notepad++.
        let languages = Language.all.filter { $0 != .normalText }
        let groups = Dictionary(grouping: languages) { String($0.name.prefix(1)).uppercased() }
        addItem(for: .normalText, to: menu)
        menu.addItem(.separator())
        for letter in groups.keys.sorted() {
            let submenu = NSMenu(title: letter)
            for language in groups[letter] ?? [] {
                addItem(for: language, to: submenu)
            }
            menu.addItem(withTitle: letter, action: nil, keyEquivalent: "").submenu = submenu
        }
        return menu
    }

    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Format"))
        menu.addItem(withTitle: String(localized: "Line Endings"), action: nil, keyEquivalent: "").isEnabled = false
        for lineEnding in LineEnding.allCases {
            let item = menu.addItem(withTitle: lineEnding.displayName, action: #selector(EditorViewController.selectLineEnding(_:)), keyEquivalent: "")
            item.representedObject = lineEnding.rawValue
            item.indentationLevel = 1
        }
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Window"))
        menu.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Show Previous Tab"), action: #selector(NSWindow.selectPreviousTab(_:)), keyEquivalent: "\t")
            .keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(withTitle: String(localized: "Show Next Tab"), action: #selector(NSWindow.selectNextTab(_:)), keyEquivalent: "\t")
            .keyEquivalentModifierMask = [.control]
        menu.addItem(withTitle: String(localized: "Move Tab to New Window"), action: #selector(NSWindow.moveTabToNewWindow(_:)), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Merge All Windows"), action: #selector(NSWindow.mergeAllWindows(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = menu
        return menu
    }

    private static func helpMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Help"))
        menu.addItem(withTitle: String(localized: "\(appName) Website"), action: #selector(AppDelegate.openWebsite(_:)), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Source Code on GitHub"), action: #selector(AppDelegate.openRepository(_:)), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Report an Issue…"), action: #selector(AppDelegate.reportIssue(_:)), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Release Notes"), action: #selector(AppDelegate.openReleaseNotes(_:)), keyEquivalent: "")
        NSApp.helpMenu = menu
        return menu
    }
}

/// Fills "Open Recent" from NSDocumentController using public API only.
@MainActor
final class RecentDocumentsMenu: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = menu.addItem(withTitle: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: String(localized: "Clear Menu"), action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSApp.presentError(error)
            }
        }
    }
}
