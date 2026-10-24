import AppKit
import Scintilla

/// Shortcut buttons on the right of the document window's toolbar. They send
/// the same actions as the menus, through the responder chain, so each one
/// works on the front tab and is disabled when its menu item would be.
@MainActor
enum ToolbarItems {
    static let convertCase = NSToolbarItem.Identifier("ConvertCase")
    static let find = NSToolbarItem.Identifier("Find")
    static let compare = NSToolbarItem.Identifier("Compare")
    static let previousDifference = NSToolbarItem.Identifier("PreviousDifference")
    static let nextDifference = NSToolbarItem.Identifier("NextDifference")
    static let compareAgain = NSToolbarItem.Identifier("CompareAgain")
    static let passwordGenerator = NSToolbarItem.Identifier("PasswordGenerator")
    static let settings = NSToolbarItem.Identifier("Settings")
    static let toggleComment = NSToolbarItem.Identifier("ToggleComment")
    static let wordWrap = NSToolbarItem.Identifier("WordWrap")

    static func make(_ identifier: NSToolbarItem.Identifier, window: NSWindow?) -> NSToolbarItem? {
        switch identifier {
        case convertCase:
            return ConvertCaseToolbarItem(window: window)
        case find:
            return button(identifier, String(localized: "Find"), symbol: "magnifyingglass",
                          #selector(EditorViewController.showFind(_:)), toolTip: String(localized: "Find (⌘F)"))
        case compare:
            return CompareToolbarItem(window: window)
        case previousDifference:
            return button(identifier, String(localized: "Previous"), symbol: "chevron.up",
                          #selector(CompareViewController.previousDifference(_:)), toolTip: String(localized: "Previous Difference (⇧F7)"))
        case nextDifference:
            return button(identifier, String(localized: "Next"), symbol: "chevron.down",
                          #selector(CompareViewController.nextDifference(_:)), toolTip: String(localized: "Next Difference (F7)"))
        case compareAgain:
            return button(identifier, String(localized: "Compare Again"), symbol: "arrow.clockwise",
                          #selector(CompareViewController.compareAgain(_:)), toolTip: String(localized: "Compare Again"))
        case passwordGenerator:
            return button(identifier, String(localized: "Password"), symbol: "key",
                          #selector(AppDelegate.showPasswordGenerator(_:)), toolTip: String(localized: "Password Generator"))
        case settings:
            return button(identifier, String(localized: "Settings"), symbol: "gearshape",
                          #selector(AppDelegate.showSettings(_:)), toolTip: String(localized: "Settings (⌘,)"))
        case toggleComment:
            return button(identifier, String(localized: "Comment"), symbol: "number",
                          #selector(EditorViewController.toggleLineComment(_:)), toolTip: String(localized: "Toggle Single Line Comment (⌘/)"))
        case wordWrap:
            return button(identifier, String(localized: "Word Wrap"), symbol: "text.word.spacing",
                          #selector(EditorViewController.toggleWordWrap(_:)), toolTip: String(localized: "Word Wrap"))
        default:
            return nil
        }
    }

    private static func button(_ identifier: NSToolbarItem.Identifier, _ label: String, symbol: String,
                               _ action: Selector, toolTip: String) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = toolTip
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.action = action
        item.isBordered = true
        return item
    }
}

/// "Aa" with a menu of the Convert Case options, enabled only while text is selected.
private final class ConvertCaseToolbarItem: NSMenuToolbarItem {
    private weak var documentWindow: NSWindow?

    init(window: NSWindow?) {
        documentWindow = window
        super.init(itemIdentifier: ToolbarItems.convertCase)
        label = String(localized: "Case")
        paletteLabel = String(localized: "Convert Case To")
        toolTip = String(localized: "Convert Case To")
        image = NSImage(systemSymbolName: "textformat", accessibilityDescription: label)
        showsIndicator = true
        menu = MainMenu.convertCaseMenu()
    }

    override func validate() {
        let editor = (documentWindow?.windowController as? DocumentWindowController)?.editorController?.editor
        isEnabled = editor.map { !$0.isReadOnly && $0.send(SCI_GETSELECTIONEMPTY) == 0 } ?? false
    }
}

/// Compare with another open document, from a menu of them.
private final class CompareToolbarItem: NSMenuToolbarItem {
    private weak var documentWindow: NSWindow?

    init(window: NSWindow?) {
        documentWindow = window
        super.init(itemIdentifier: ToolbarItems.compare)
        label = String(localized: "Compare")
        paletteLabel = String(localized: "Compare")
        toolTip = String(localized: "Compare with another open document")
        image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: label)
        showsIndicator = true
        menu = CompareMenu(source: window)
    }

    override func validate() {
        let document = documentWindow?.windowController?.document as? TextDocument
        isEnabled = document.map { !CompareMenu.candidates(for: $0).isEmpty } ?? false
    }
}
