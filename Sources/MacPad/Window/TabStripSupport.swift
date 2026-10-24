import AppKit

/// Which tabs a drawn tab strip (`ModernTabStrip`, `ClassicTabStrip`) shows.
///
/// Tabs shrink down to a minimum width; past that, only as many as fit are
/// shown, always including the selected one, and an overflow button lists them all.
struct TabStripLayout {
    /// Indexes of the tabs shown, in order.
    let visible: Range<Int>
    let width: CGFloat
    let count: Int

    var overflows: Bool { visible.count < count }

    /// `first` is the first visible tab of the previous layout, kept when
    /// possible so the strip does not jump around; it is updated in place.
    static func make(count: Int, selected: Int?, available: CGFloat, minWidth: CGFloat, maxWidth: CGFloat,
                     overflowWidth: CGFloat, first: inout Int) -> TabStripLayout {
        guard count > 0, available > 0 else { return TabStripLayout(visible: 0..<0, width: 0, count: count) }
        let even = (available / CGFloat(count)).rounded(.down)
        if even >= minWidth {
            first = 0
            return TabStripLayout(visible: 0..<count, width: min(maxWidth, even), count: count)
        }
        let room = available - overflowWidth
        let visibleCount = min(count, max(1, Int(room / minWidth)))
        if let selected {
            if selected < first { first = selected }
            if selected >= first + visibleCount { first = selected - visibleCount + 1 }
        }
        first = min(max(0, first), count - visibleCount)
        let width = min(maxWidth, (room / CGFloat(visibleCount)).rounded(.down))
        return TabStripLayout(visible: first..<(first + visibleCount), width: width, count: count)
    }
}

/// Shared pieces of the drawn tab strips: the overflow menu and the
/// accessibility elements standing in for the tabs and buttons they draw.
@MainActor
enum TabStripSupport {
    /// Every tab, for the overflow button: edited ones marked, colored ones
    /// with their swatch, the selected one checked.
    static func overflowMenu(windows: [NSWindow], selected: NSWindow?) -> NSMenu {
        let menu = NSMenu(title: String(localized: "All Tabs"))
        for window in windows {
            let document = window.windowController?.document as? TextDocument
            let title = (window.isDocumentEdited ? "• " : "") + window.title
            let item = menu.addItem(withTitle: title, action: #selector(TabSelector.select(_:)), keyEquivalent: "")
            item.target = TabSelector.shared
            item.representedObject = window
            item.state = window === selected ? .on : .off
            if let color = document?.tabColor?.color {
                item.image = TabMenu.swatch(color)
            } else if document?.isPinned == true {
                item.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: String(localized: "Pinned"))
            }
        }
        return menu
    }

    /// The accessibility description of a tab, read by VoiceOver.
    static func label(for window: NSWindow) -> String {
        let document = window.windowController?.document as? TextDocument
        var parts = [window.title]
        if window.isDocumentEdited { parts.append(String(localized: "edited")) }
        if document?.isPinned == true { parts.append(String(localized: "pinned")) }
        if let color = document?.tabColor { parts.append(color.displayName) }
        return parts.joined(separator: ", ")
    }

    static func select(_ window: NSWindow) {
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}

/// Target for the overflow menu's items.
@MainActor
final class TabSelector: NSObject {
    static let shared = TabSelector()

    @objc func select(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? NSWindow else { return }
        TabStripSupport.select(window)
    }
}

/// A tab or button drawn by a tab strip, exposed to VoiceOver: tabs as radio
/// buttons in a tab group (as AppKit's own tab bar does), with Close as a
/// custom action; buttons as buttons.
final class TabStripElement: NSAccessibilityElement {
    private let press: () -> Void

    init(parent: NSView, frame: NSRect, label: String, isTab: Bool, isSelected: Bool = false,
         press: @escaping () -> Void, close: (() -> Void)? = nil) {
        self.press = press
        super.init()
        setAccessibilityParent(parent)
        setAccessibilityFrameInParentSpace(frame)
        setAccessibilityLabel(label)
        if isTab {
            setAccessibilityRole(.radioButton)
            setAccessibilitySubrole(NSAccessibility.Subrole(rawValue: "AXTabButton"))
            setAccessibilityValue(isSelected ? 1 : 0)
            setAccessibilitySelected(isSelected)
        } else {
            setAccessibilityRole(.button)
        }
        if let close {
            setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: String(localized: "Close Tab")) {
                    close()
                    return true
                },
            ])
        }
    }

    override func accessibilityPerformPress() -> Bool {
        press()
        return true
    }
}
