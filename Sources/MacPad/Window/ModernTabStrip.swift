import AppKit

/// Tabs for the Match System, Light and Dark themes, drawn over the system tab
/// bar: the selected tab is raised and joins the editor, every tab has its own
/// close button, and a tab's color tints its background.
///
/// The tabs stay native window tabs (session, ⌃Tab, Window menu); only the
/// drawing is ours. The system bar stays underneath, hidden, because AppKit
/// refuses to remove it once a window has more than one tab.
final class ModernTabStrip: NSView {
    /// Hides the system tab bar in `titlebar` and keeps a strip on top of it.
    static func install(in titlebar: NSView?, window: NSWindow?) {
        guard !Chrome.isClassic, let titlebar, let window,
              let tabBar = descendant(of: titlebar, named: "NSTabBar"),
              let container = tabBar.superview
        else { return }
        tabBar.alphaValue = 0
        tabBar.isHidden = true
        if let strip = container.subviews.first(where: { $0 is ModernTabStrip }) as? ModernTabStrip {
            strip.follow(tabBar)
            if container.subviews.last !== strip {
                container.addSubview(strip, positioned: .above, relativeTo: nil)
            }
            return
        }
        let strip = ModernTabStrip(window: window)
        strip.follow(tabBar)
        container.addSubview(strip, positioned: .above, relativeTo: nil)
    }

    static func remove(from titlebar: NSView) {
        if let tabBar = descendant(of: titlebar, named: "NSTabBar") {
            tabBar.alphaValue = 1
            tabBar.isHidden = false
        }
        var stack = [titlebar]
        while let view = stack.popLast() {
            if view is ModernTabStrip { view.removeFromSuperview() } else { stack += view.subviews }
        }
    }

    private static func descendant(of view: NSView, named className: String) -> NSView? {
        var stack = [view]
        while let current = stack.popLast() {
            if String(describing: type(of: current)) == className { return current }
            stack += current.subviews
        }
        return nil
    }

    private weak var observedWindow: NSWindow?
    private weak var tabBar: NSView?
    private var groupObservations: [NSKeyValueObservation] = []
    private var windowObservations: [NSKeyValueObservation] = []
    private var hoveredTab: Int?
    private var hoveredClose: Int?
    private var hoverArea: NSTrackingArea?

    private static let maxTabWidth: CGFloat = 200
    /// Narrower than this, tabs stop shrinking and the rest go to the overflow menu.
    private static let minTabWidth: CGFloat = 90
    /// Narrower than this, a tab shows its close button only on hover.
    private static let roomyTabWidth: CGFloat = 120
    private static let addWidth: CGFloat = 28
    private static let overflowWidth: CGFloat = 40
    /// First tab shown when they do not all fit (see TabStripLayout).
    private var firstVisibleTab = 0
    private var accessibilityElements: [TabStripElement]?
    private static let corner: CGFloat = 8
    private static let closeSize: CGFloat = 16

    init(window: NSWindow) {
        observedWindow = window
        super.init(frame: .zero)
        DispatchQueue.main.async { [weak self] in self?.observeGroup() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(observeGroup), name: NSWindow.didBecomeMainNotification, object: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Matches the system bar's frame, which AppKit changes with the sidebar and window size.
    private func follow(_ bar: NSView) {
        if tabBar !== bar {
            tabBar = bar
            bar.postsFrameChangedNotifications = true
            NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(barFrameChanged), name: NSView.frameDidChangeNotification, object: bar)
        }
        barFrameChanged()
    }

    @objc private func barFrameChanged() {
        guard let bar = tabBar, frame != bar.frame else { return }
        frame = bar.frame
        needsDisplay = true
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The window hosting the strip. The system tab bar, and the strip with it,
    /// can move to another tab's window, so this beats the original window.
    private var hostWindow: NSWindow? { window ?? observedWindow }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        observedWindow = window
        observeGroup()
    }

    private var windows: [NSWindow] {
        guard let window = hostWindow else { return [] }
        return window.tabGroup?.windows ?? [window]
    }

    private var selected: NSWindow? { hostWindow?.tabGroup?.selectedWindow ?? hostWindow }

    @objc private func observeGroup() {
        groupObservations = []
        if let group = hostWindow?.tabGroup {
            groupObservations = [
                group.observe(\.windows) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.observeWindows() }
                },
                group.observe(\.selectedWindow) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.needsDisplay = true }
                },
            ]
        }
        observeWindows()
    }

    /// Redraws when any tab's title, edited state, pin or color changes.
    private func observeWindows() {
        NotificationCenter.default.removeObserver(self, name: TextDocument.tabDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: TextDocument.tabDidChangeNotification, object: nil)
        windowObservations = windows.flatMap { window -> [NSKeyValueObservation] in
            [
                window.observe(\.title) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.needsDisplay = true }
                },
                window.observe(\.isDocumentEdited) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.needsDisplay = true }
                },
            ]
        }
        needsDisplay = true
    }

    @objc private func redraw() { needsDisplay = true }

    /// AppKit re-inserts its tab bar when tabs change; stay above it.
    override func viewWillDraw() {
        super.viewWillDraw()
        if let container = superview, container.subviews.last !== self {
            DispatchQueue.main.async { [weak self] in
                ModernTabStrip.install(in: self?.window?.contentView?.superview, window: self?.observedWindow)
            }
        }
    }

    // MARK: Colors

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    /// The editor's own background, so the selected tab and the editor read as one surface.
    private var editorColor: NSColor {
        let value = EditorTheme.current(for: effectiveAppearance).background
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// The bar behind the tabs: a step darker than the editor.
    private var barColor: NSColor {
        editorColor.blended(withFraction: isDark ? 0.28 : 0.06, of: .black) ?? editorColor
    }

    private var separatorColor: NSColor {
        NSColor.labelColor.withAlphaComponent(isDark ? 0.14 : 0.12)
    }

    // MARK: Geometry

    private var tabLayout: TabStripLayout {
        let windows = windows
        return TabStripLayout.make(
            count: windows.count, selected: selected.flatMap { windows.firstIndex(of: $0) },
            available: bounds.width - 8 - 8 - Self.addWidth - 4, minWidth: Self.minTabWidth, maxWidth: Self.maxTabWidth,
            overflowWidth: Self.overflowWidth + 2, first: &firstVisibleTab)
    }

    /// One rect per tab, in tab order; tabs that do not fit get an empty rect.
    private var tabRects: [NSRect] {
        let layout = tabLayout
        return (0..<layout.count).map { index in
            guard layout.visible.contains(index) else { return .zero }
            return NSRect(x: 8 + CGFloat(index - layout.visible.lowerBound) * layout.width, y: 3,
                          width: layout.width, height: bounds.height - 3)
        }
    }

    private var lastTabMaxX: CGFloat { max(8, tabRects.map(\.maxX).max() ?? 8) }

    /// The button listing every tab, shown when some do not fit.
    private var overflowRect: NSRect? {
        guard tabLayout.overflows else { return nil }
        return NSRect(x: lastTabMaxX + 2, y: (bounds.height / 2 - Self.addWidth / 2 + 1).rounded(),
                      width: Self.overflowWidth, height: Self.addWidth)
    }

    private var hiddenTabCount: Int {
        let layout = tabLayout
        return layout.count - layout.visible.count
    }

    private func closeRect(in tab: NSRect) -> NSRect {
        NSRect(x: tab.minX + 8, y: (tab.midY - Self.closeSize / 2 + 1).rounded(), width: Self.closeSize, height: Self.closeSize)
    }

    private var addRect: NSRect {
        let last = overflowRect?.maxX ?? lastTabMaxX
        return NSRect(x: last + 4, y: (bounds.height / 2 - Self.addWidth / 2 + 1).rounded(), width: Self.addWidth, height: Self.addWidth)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        barColor.setFill()
        bounds.fill()
        // Hairline under the bar; the selected tab covers it.
        separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

        let windows = windows
        let rects = tabRects
        let selected = selected
        for (index, window) in windows.enumerated() where window !== selected && !rects[index].isEmpty {
            drawTab(window, in: rects[index], index: index, isSelected: false)
        }
        for (index, window) in windows.enumerated() where window === selected && !rects[index].isEmpty {
            drawTab(window, in: rects[index], index: index, isSelected: true)
        }
        drawOverflowButton()
        drawAddButton()
        accessibilityElements = nil
        updateToolTips()
    }

    private func updateToolTips() {
        removeAllToolTips()
        addToolTip(addRect, owner: String(localized: "New Tab") as NSString, userData: nil)
        if let overflowRect {
            addToolTip(overflowRect, owner: String(localized: "All Tabs") as NSString, userData: nil)
        }
    }

    /// "»" and the number of tabs that do not fit.
    private func drawOverflowButton() {
        guard let rect = overflowRect else { return }
        if hoveredTab == -2 {
            NSColor.labelColor.withAlphaComponent(isDark ? 0.12 : 0.08).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
        }
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            .applying(.init(paletteColors: [.secondaryLabelColor]))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let count = "\(hiddenTabCount)" as NSString
        let countSize = count.size(withAttributes: attributes)
        guard let image = NSImage(systemSymbolName: "chevron.right.2", accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let totalWidth = image.size.width + 3 + countSize.width
        let x = (rect.midX - totalWidth / 2).rounded()
        image.draw(in: NSRect(x: x, y: (rect.midY - image.size.height / 2).rounded(), width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        count.draw(at: NSPoint(x: x + image.size.width + 3, y: (rect.midY - countSize.height / 2).rounded()), withAttributes: attributes)
    }

    private func drawTab(_ window: NSWindow, in rect: NSRect, index: Int, isSelected: Bool) {
        let document = window.windowController?.document as? TextDocument
        let tint = document?.tabColor?.color
        let isHovered = hoveredTab == index
        let tab = rect

        if isSelected {
            // Rounded at the top, open at the bottom: it continues into the editor.
            let path = NSBezierPath()
            let r = Self.corner
            path.move(to: NSPoint(x: tab.minX, y: tab.maxY))
            path.line(to: NSPoint(x: tab.minX, y: tab.minY + r))
            path.appendArc(withCenter: NSPoint(x: tab.minX + r, y: tab.minY + r), radius: r, startAngle: 180, endAngle: 270)
            path.line(to: NSPoint(x: tab.maxX - r, y: tab.minY))
            path.appendArc(withCenter: NSPoint(x: tab.maxX - r, y: tab.minY + r), radius: r, startAngle: 270, endAngle: 360)
            path.line(to: NSPoint(x: tab.maxX, y: tab.maxY))
            editorColor.setFill()
            path.fill()
            if let tint {
                tint.withAlphaComponent(isDark ? 0.20 : 0.16).setFill()
                path.fill()
            }
            // Outline on the sides and top only; the bottom stays open.
            separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        } else {
            // Flat: a rounded pill when hovered or tinted, otherwise just the bar.
            let pill = NSBezierPath(roundedRect: tab.insetBy(dx: 2, dy: 3).offsetBy(dx: 0, dy: -1), xRadius: 6, yRadius: 6)
            if let tint {
                tint.withAlphaComponent(isDark ? 0.16 : 0.13).setFill()
                pill.fill()
            }
            if isHovered {
                NSColor.labelColor.withAlphaComponent(isDark ? 0.08 : 0.06).setFill()
                pill.fill()
            }
            // Divider between two flat neighbours.
            if index > 0, !isHovered {
                separatorColor.setFill()
                NSRect(x: tab.minX, y: tab.midY - 6, width: 1, height: 12).fill()
            }
        }

        // One slot for close and edited, as in Safari: hovering shows ×, an
        // edited tab otherwise shows •, and the selected tab and roomy tabs keep × at rest.
        let close = closeRect(in: tab)
        if isHovered {
            drawCloseButton(in: close, hovered: hoveredClose == index, selected: true)
        } else if window.isDocumentEdited {
            drawEditedDot(in: close, selected: isSelected)
        } else if isSelected || tab.width >= Self.roomyTabWidth {
            drawCloseButton(in: close, hovered: false, selected: isSelected)
        }

        let title = window.title
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .medium : .regular),
            .foregroundColor: isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let textHeight = (title as NSString).size(withAttributes: attributes).height
        var left = close.maxX + 6
        if document?.isPinned == true,
           let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
               .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold).applying(.init(paletteColors: [.secondaryLabelColor]))) {
            let pinRect = NSRect(x: left, y: (tab.midY - pin.size.height / 2 + 1).rounded(), width: pin.size.width, height: pin.size.height)
            pin.draw(in: pinRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            left = pinRect.maxX + 4
        }
        let textRect = NSRect(x: left, y: (tab.midY - textHeight / 2 + 1).rounded(),
                              width: max(0, tab.maxX - left - 10), height: textHeight)
        (title as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func drawEditedDot(in rect: NSRect, selected: Bool) {
        (selected ? NSColor.labelColor : NSColor.secondaryLabelColor).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.midX - 3, y: rect.midY - 3, width: 6, height: 6)).fill()
    }

    private func drawCloseButton(in rect: NSRect, hovered: Bool, selected: Bool) {
        if hovered {
            NSColor.labelColor.withAlphaComponent(isDark ? 0.16 : 0.10).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        }
        (selected || hovered ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setStroke()
        let cross = NSBezierPath()
        let inset: CGFloat = 5
        cross.move(to: NSPoint(x: rect.minX + inset, y: rect.minY + inset))
        cross.line(to: NSPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        cross.move(to: NSPoint(x: rect.maxX - inset, y: rect.minY + inset))
        cross.line(to: NSPoint(x: rect.minX + inset, y: rect.maxY - inset))
        cross.lineWidth = 1.2
        cross.lineCapStyle = .round
        cross.stroke()
    }

    private func drawAddButton() {
        let rect = addRect
        if hoveredTab == -1 {
            NSColor.labelColor.withAlphaComponent(isDark ? 0.12 : 0.08).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
        }
        NSColor.secondaryLabelColor.setStroke()
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: rect.midX - 5, y: rect.midY))
        plus.line(to: NSPoint(x: rect.midX + 5, y: rect.midY))
        plus.move(to: NSPoint(x: rect.midX, y: rect.midY - 5))
        plus.line(to: NSPoint(x: rect.midX, y: rect.midY + 5))
        plus.lineWidth = 1.3
        plus.lineCapStyle = .round
        plus.stroke()
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .tabGroup }
    override func accessibilityLabel() -> String? { String(localized: "Tabs") }

    /// Every tab (those in the overflow menu sit on its button), then the
    /// overflow and new-tab buttons. Rebuilt after each redraw.
    override func accessibilityChildren() -> [Any]? {
        if let accessibilityElements { return accessibilityElements }
        let windows = windows
        let rects = tabRects
        let selected = selected
        var elements = windows.enumerated().map { index, window in
            TabStripElement(parent: self, frame: rects[index].isEmpty ? (overflowRect ?? .zero) : rects[index],
                            label: TabStripSupport.label(for: window), isTab: true, isSelected: window === selected,
                            press: { TabStripSupport.select(window) }, close: { window.performClose(nil) })
        }
        if let overflowRect {
            elements.append(TabStripElement(parent: self, frame: overflowRect, label: String(localized: "All Tabs"), isTab: false) { [weak self] in
                guard let self, let rect = self.overflowRect else { return }
                TabStripSupport.overflowMenu(windows: self.windows, selected: self.selected)
                    .popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY), in: self)
            })
        }
        elements.append(TabStripElement(parent: self, frame: addRect, label: String(localized: "New Tab"), isTab: false) {
            NSDocumentController.shared.newDocument(nil)
        })
        accessibilityElements = elements
        return elements
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let rects = tabRects
        let tab = rects.firstIndex { $0.contains(point) }
        let hover = addRect.contains(point) ? -1 : overflowRect?.contains(point) == true ? -2 : tab
        let close = tab.flatMap { closeRect(in: rects[$0]).insetBy(dx: -2, dy: -2).contains(point) ? $0 : nil }
        guard hover != hoveredTab || close != hoveredClose else { return }
        hoveredTab = hover
        hoveredClose = close
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredTab = nil
        hoveredClose = nil
        needsDisplay = true
    }

    // MARK: Interaction

    /// Tabs drawn here can carry Notepad++'s whole tab menu, for the tab clicked.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let windows = windows
        guard let index = tabRects.firstIndex(where: { $0.contains(point) }), index < windows.count else { return nil }
        let menu = NSMenu(title: String(localized: "Tab"))
        guard let controller = windows[index].windowController as? DocumentWindowController else {
            // A comparison tab: closing is all there is to do.
            let close = menu.addItem(withTitle: String(localized: "Close Tab"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "")
            close.target = windows[index]
            return menu
        }
        for item in TabMenu.items(target: controller, keyEquivalents: false) {
            // Close and Move to New Window are the window's own actions.
            if item.action == #selector(NSWindow.performClose(_:)) || item.action == #selector(NSWindow.moveTabToNewWindow(_:)) {
                item.target = windows[index]
            }
            menu.addItem(item)
        }
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let overflowRect, overflowRect.contains(point) {
            TabStripSupport.overflowMenu(windows: windows, selected: selected)
                .popUp(positioning: nil, at: NSPoint(x: overflowRect.minX, y: overflowRect.maxY), in: self)
            return
        }
        if addRect.contains(point) {
            NSDocumentController.shared.newDocument(nil)
            return
        }
        let windows = windows
        let rects = tabRects
        guard let index = rects.firstIndex(where: { $0.contains(point) }), index < windows.count else {
            // Free space moves the window; a double click opens a new tab.
            if event.clickCount == 2 {
                NSDocumentController.shared.newDocument(nil)
            } else {
                hostWindow?.performDrag(with: event)
            }
            return
        }
        let target = windows[index]
        if closeRect(in: rects[index]).insetBy(dx: -2, dy: -2).contains(point) {
            // Track the close button like a button: act only if released inside.
            var inside = true
            while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
                inside = closeRect(in: tabRects[index]).insetBy(dx: -2, dy: -2).contains(convert(next.locationInWindow, from: nil))
                hoveredClose = inside ? index : nil
                needsDisplay = true
                if next.type == .leftMouseUp { break }
            }
            if inside { target.performClose(nil) }
            return
        }
        if let group = target.tabGroup { group.selectedWindow = target }
        target.makeKeyAndOrderFront(nil)
        trackReorder(of: target, startingAt: point.x)
    }

    /// Dragging a tab sideways moves it among the others, within its kind
    /// (pinned tabs stay first).
    private func trackReorder(of target: NSWindow, startingAt startX: CGFloat) {
        var moved = false
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp { break }
            let x = convert(next.locationInWindow, from: nil).x
            guard moved || abs(x - startX) > 4 else { continue }
            moved = true
            let rects = tabRects
            let windows = windows
            guard let current = windows.firstIndex(of: target),
                  let over = rects.firstIndex(where: { $0.minX <= x && x < $0.maxX }) ?? (x < 0 ? 0 : rects.indices.last),
                  over != current
            else { continue }
            TabOrder.move(target, to: over)
            observeWindows()
        }
    }
}

/// Puts a `ModernTabStrip` over the system tab bar. The bar is created lazily
/// and AppKit moves it between windows, so this view sits in the title bar and
/// reinstalls the strip whenever the title bar lays out.
final class ModernTabStripInstaller: NSView {
    private weak var observedWindow: NSWindow?

    init(window: NSWindow) {
        observedWindow = window
        super.init(frame: .zero)
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            center.addObserver(self, selector: #selector(install), name: name, object: window)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        install()
    }

    override func layout() {
        super.layout()
        install()
    }

    @objc private func install() {
        DispatchQueue.main.async { [weak self] in
            ModernTabStrip.install(in: self?.superview, window: self?.observedWindow)
        }
    }
}
