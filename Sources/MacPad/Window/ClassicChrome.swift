import AppKit

/// Mac OS 9 Platinum window frame for the Classic theme: a pinstriped title bar
/// with close, zoom and collapse boxes drawn over the system title bar, whose
/// traffic lights and title are hidden while it is shown.
@MainActor
enum ClassicWindowFrame {
    private static let titleBarID = NSUserInterfaceItemIdentifier("ClassicTitleBar")

    static func apply(to window: NSWindow, toolbar: NSToolbar?) {
        let classic = Chrome.isClassic
        // Style mask and toolbar changes keep the content size; keep the frame instead.
        let frame = window.frame
        defer { window.setFrame(frame, display: false) }
        window.titlebarAppearsTransparent = classic
        window.titleVisibility = classic ? .hidden : .visible
        // Content starts below the title bar and tab strip, so no pane (such as
        // the sidebar) can extend underneath and cover the tabs.
        if classic {
            window.styleMask.remove(.fullSizeContentView)
        } else {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.backgroundColor = classic ? Chrome.Platinum.frame : .windowBackgroundColor
        window.toolbar = classic ? nil : toolbar
        // The app is dark under Classic (for dialogs and menus); the window's
        // own content stays light. Sheets follow the window, so it is not set there.
        window.contentView?.appearance = classic ? NSAppearance(named: .aqua) : nil
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = classic
        }

        guard let host = titlebarView(of: window) else { return }
        let existing = host.subviews.first { $0.identifier == titleBarID }
        if classic, existing == nil {
            let bar = ClassicTitleBar(window: window)
            bar.identifier = titleBarID
            bar.frame = host.bounds
            bar.autoresizingMask = [.width, .height]
            host.addSubview(bar, positioned: .below, relativeTo: nil)
        } else if !classic {
            existing?.removeFromSuperview()
            ClassicTabStrip.remove(from: host)
        }
    }

    /// The system view behind the traffic lights, which spans the title bar.
    private static func titlebarView(of window: NSWindow) -> NSView? {
        var view = window.standardWindowButton(.closeButton)?.superview
        while let current = view {
            if String(describing: type(of: current)) == "NSTitlebarView" { return current }
            view = current.superview
        }
        return window.standardWindowButton(.closeButton)?.superview
    }
}

/// Pinstripes, centred Chicago title and the three window boxes. Clicks outside
/// the boxes fall through to the system title bar, so dragging and
/// double-clicking keep working.
final class ClassicTitleBar: NSView {
    private weak var observedWindow: NSWindow?
    private let closeBox = ClassicWindowBox(kind: .close)
    private let zoomBox = ClassicWindowBox(kind: .zoom)
    private let collapseBox = ClassicWindowBox(kind: .collapse)
    private var titleObservation: NSKeyValueObservation?

    private static let boxSize: CGFloat = 13
    private static let inset: CGFloat = 8

    init(window: NSWindow) {
        observedWindow = window
        super.init(frame: .zero)
        closeBox.target = window
        closeBox.action = #selector(NSWindow.performClose(_:))
        zoomBox.target = window
        zoomBox.action = #selector(NSWindow.performZoom(_:))
        collapseBox.target = window
        collapseBox.action = #selector(NSWindow.performMiniaturize(_:))
        for box in [closeBox, zoomBox, collapseBox] {
            addSubview(box)
        }
        titleObservation = window.observe(\.title) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
            center.addObserver(self, selector: #selector(activeStateChanged), name: name, object: window)
        }
        activeStateChanged()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The system tab bar is created lazily, after the title bar.
        DispatchQueue.main.async { [weak self] in
            ClassicTabStrip.install(in: self?.superview, window: self?.observedWindow)
        }
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    private var isActive: Bool { observedWindow?.isMainWindow ?? false }

    @objc private func activeStateChanged() {
        for box in [closeBox, zoomBox, collapseBox] {
            box.isHidden = !isActive
        }
        needsDisplay = true
        // AppKit moves the system tab bar to whichever tab becomes main, e.g.
        // after another tab closes; cover it there too.
        DispatchQueue.main.async { [weak self] in
            ClassicTabStrip.install(in: self?.superview, window: self?.observedWindow)
        }
    }

    /// Height of the title bar proper; the view also spans the tab strip below.
    private static let titleHeight: CGFloat = {
        let content = NSRect(x: 0, y: 0, width: 100, height: 100)
        return NSWindow.frameRect(forContentRect: content, styleMask: [.titled]).height - content.height
    }()

    /// The band holding stripes and boxes, vertically centred in the title bar.
    private var band: NSRect {
        let height = Self.boxSize
        return NSRect(x: Self.inset, y: ((Self.titleHeight - height) / 2).rounded(.down),
                      width: bounds.width - Self.inset * 2, height: height)
    }

    override func layout() {
        super.layout()
        ClassicTabStrip.install(in: superview, window: observedWindow)
        let band = band
        let size = Self.boxSize
        closeBox.frame = NSRect(x: band.minX, y: band.minY, width: size, height: size)
        collapseBox.frame = NSRect(x: band.maxX - size, y: band.minY, width: size, height: size)
        zoomBox.frame = NSRect(x: collapseBox.frame.minX - size - 4, y: band.minY, width: size, height: size)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        needsLayout = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Chrome.Platinum.frame.setFill()
        bounds.fill()

        let title = observedWindow?.title ?? ""
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Chrome.font(ofSize: 12),
            .foregroundColor: isActive ? NSColor.black : Chrome.Platinum.inactiveText,
        ]
        let titleSize = (title as NSString).size(withAttributes: attributes)
        let band = band
        let reserved = (Self.boxSize + 6) * 2 + Self.boxSize
        let titleWidth = min(titleSize.width, max(0, band.width - reserved * 2))
        let titleRect = NSRect(x: (bounds.midX - titleWidth / 2).rounded(), y: (band.midY - titleSize.height / 2).rounded(),
                               width: titleWidth, height: titleSize.height)

        if isActive {
            // Stripes run between the boxes, leaving a gap around the title.
            let left = NSRect(x: closeBox.frame.maxX + 4, y: band.minY + 1,
                              width: titleRect.minX - 6 - (closeBox.frame.maxX + 4), height: band.height - 2)
            let right = NSRect(x: titleRect.maxX + 6, y: band.minY + 1,
                               width: zoomBox.frame.minX - 4 - (titleRect.maxX + 6), height: band.height - 2)
            for rect in [left, right] where rect.width > 0 {
                drawStripes(in: rect)
            }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        var truncated = attributes
        truncated[.paragraphStyle] = paragraph
        (title as NSString).draw(in: titleRect, withAttributes: truncated)
    }

    /// Alternating white and grey hairlines, the Platinum "racing stripes".
    private func drawStripes(in rect: NSRect) {
        var y = rect.minY
        var light = true
        while y < rect.maxY {
            (light ? NSColor.white : Chrome.Platinum.stripe).setFill()
            NSRect(x: rect.minX, y: y, width: rect.width, height: 1).fill()
            y += 1
            light.toggle()
        }
    }
}

/// Platinum tabs for the window's tab group, laid over the system tab bar:
/// click to select, close box on each tab, a "+" box for a new document.
///
/// The system bar stays underneath because AppKit refuses to hide it once a
/// window has more than one tab.
final class ClassicTabStrip: NSView {
    /// Hides the system tab bar in `titlebar` and keeps a strip on top of it.
    static func install(in titlebar: NSView?, window: NSWindow?) {
        guard Chrome.isClassic, let titlebar, let window,
              let tabBar = descendant(of: titlebar, named: "NSTabBar"),
              let container = tabBar.superview
        else { return }
        // Hidden so it takes no clicks; transparent in case AppKit unhides it.
        tabBar.alphaValue = 0
        tabBar.isHidden = true
        if let strip = container.subviews.first(where: { $0 is ClassicTabStrip }) {
            if container.subviews.last !== strip {
                container.addSubview(strip, positioned: .above, relativeTo: nil)
            }
            return
        }
        let strip = ClassicTabStrip(window: window)
        strip.frame = container.bounds
        strip.autoresizingMask = [.width, .height]
        container.addSubview(strip, positioned: .above, relativeTo: nil)
    }

    static func remove(from titlebar: NSView) {
        if let tabBar = descendant(of: titlebar, named: "NSTabBar") {
            tabBar.alphaValue = 1
            tabBar.isHidden = false
        }
        var stack = [titlebar]
        while let view = stack.popLast() {
            if view is ClassicTabStrip { view.removeFromSuperview() } else { stack += view.subviews }
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
    private var groupObservations: [NSKeyValueObservation] = []
    private var windowObservations: [NSKeyValueObservation] = []
    private var hoveredClose: Int?

    private static let tabHeight: CGFloat = 21
    private static let maxTabWidth: CGFloat = 200
    private static let addWidth: CGFloat = 22

    init(window: NSWindow) {
        observedWindow = window
        super.init(frame: .zero)
        // The group may not exist yet; observe once the window is on screen.
        DispatchQueue.main.async { [weak self] in self?.observeGroup() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(observeGroup), name: NSWindow.didBecomeMainNotification, object: window)
        // Tabs start where the sidebar ends, so follow it as it resizes.
        NotificationCenter.default.addObserver(
            self, selector: #selector(splitViewDidResize(_:)), name: NSSplitView.didResizeSubviewsNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(redraw), name: SidebarViewController.tabDidChange, object: nil)
    }

    @objc private func redraw() {
        needsDisplay = true
        updateToolTips()
    }

    @objc private func splitViewDidResize(_ notification: Notification) {
        guard (notification.object as? NSView)?.window === hostWindow else { return }
        redraw()
    }

    // MARK: Sidebar switcher

    /// The sidebar of the window hosting the strip, when it is showing.
    private var sidebar: SidebarViewController? {
        guard sidebarEdge > 0 else { return nil }
        return (hostWindow?.contentViewController as? DocumentSplitViewController)?.sidebar
    }

    private static let switcherTabs: [SidebarViewController.Tab] = [.files, .symbols]

    /// Platinum bevel buttons standing in for the sidebar's segmented control,
    /// centred above the sidebar and level with the tabs.
    private var switcherRects: [NSRect] {
        guard sidebar != nil else { return [] }
        let size = NSSize(width: 30, height: Self.tabHeight - 2)
        let originX = ((sidebarEdge - size.width * 2) / 2).rounded()
        let y = bounds.height - Self.tabHeight
        return (0..<2).map { NSRect(x: originX + CGFloat($0) * (size.width - 1), y: y, width: size.width, height: size.height) }
    }

    private func drawSwitcher() {
        guard let sidebar else { return }
        for (index, rect) in switcherRects.enumerated() {
            let tab = Self.switcherTabs[index]
            let selected = sidebar.tab == tab
            Chrome.Platinum.dark.setFill()
            rect.fill()
            let face = rect.insetBy(dx: 1, dy: 1)
            (selected ? Chrome.Platinum.boxShade : Chrome.Platinum.frame).setFill()
            face.fill()
            (selected ? Chrome.Platinum.dark : .white).setFill()
            NSRect(x: face.minX, y: face.minY, width: face.width, height: 1).fill()
            NSRect(x: face.minX, y: face.minY, width: 1, height: face.height).fill()
            (selected ? Chrome.Platinum.frame : Chrome.Platinum.shadow).setFill()
            NSRect(x: face.minX, y: face.maxY - 1, width: face.width, height: 1).fill()
            NSRect(x: face.maxX - 1, y: face.minY, width: 1, height: face.height).fill()

            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                .applying(.init(paletteColors: [.black]))
            guard let image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { continue }
            let imageRect = NSRect(x: (face.midX - image.size.width / 2).rounded(), y: (face.midY - image.size.height / 2).rounded(),
                                   width: image.size.width, height: image.size.height)
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    private func updateToolTips() {
        removeAllToolTips()
        for (rect, tab) in zip(switcherRects, Self.switcherTabs) {
            addToolTip(rect, owner: tab.toolTip as NSString, userData: nil)
        }
    }

    override func layout() {
        super.layout()
        updateToolTips()
    }

    /// Right edge of the sidebar in this view's coordinates, or 0 when hidden.
    /// The strip paints the sidebar's colour up to there, so the sidebar runs
    /// the full height below the title bar and the tabs sit over the editor.
    private var sidebarEdge: CGFloat {
        guard let split = hostWindow?.contentViewController as? NSSplitViewController,
              let item = split.splitViewItems.first, !item.isCollapsed,
              item.viewController.isViewLoaded
        else { return 0 }
        let sidebar = item.viewController.view
        let edge = convert(sidebar.convert(sidebar.bounds, to: nil), from: nil).maxX
        return max(0, min(edge, bounds.width - 120)).rounded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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

    /// Redraws when any tab's title or edited state changes.
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

    /// AppKit re-inserts its tab bar when tabs change; stay above it.
    override func viewWillDraw() {
        super.viewWillDraw()
        if let container = superview, container.subviews.last !== self {
            DispatchQueue.main.async { [weak self] in
                ClassicTabStrip.install(in: self?.window?.contentView?.superview, window: self?.observedWindow)
            }
        }
    }

    // MARK: Geometry

    private var tabRects: [NSRect] {
        let count = windows.count
        guard count > 0 else { return [] }
        let start = sidebarEdge + 8
        let available = bounds.width - start - 8 - Self.addWidth - 6
        let width = min(Self.maxTabWidth, (available / CGFloat(count)).rounded(.down))
        return (0..<count).map { index in
            NSRect(x: start + CGFloat(index) * (width - 1), y: bounds.height - Self.tabHeight - 1,
                   width: width, height: Self.tabHeight)
        }
    }

    private func closeRect(in tab: NSRect) -> NSRect {
        NSRect(x: tab.minX + 7, y: (tab.midY - 5).rounded(), width: 11, height: 11)
    }

    private var addRect: NSRect {
        let last = tabRects.last?.maxX ?? sidebarEdge + 8
        return NSRect(x: last + 6, y: bounds.height - Self.tabHeight + 2, width: Self.addWidth - 6, height: Self.tabHeight - 6)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        Chrome.Platinum.frame.setFill()
        bounds.fill()
        let edge = sidebarEdge
        if edge > 0 {
            // The top of the sidebar, with the divider continuing up to the title bar.
            Chrome.Platinum.panel.setFill()
            NSRect(x: 0, y: 0, width: edge, height: bounds.height).fill()
            Chrome.Platinum.shadow.setFill()
            NSRect(x: 0, y: 0, width: edge, height: 1).fill()
            NSRect(x: edge - 1, y: 0, width: 1, height: bounds.height).fill()
        }
        // Baseline the tabs sit on.
        Chrome.Platinum.dark.setFill()
        NSRect(x: edge, y: bounds.maxY - 1, width: bounds.width - edge, height: 1).fill()

        let windows = windows
        let rects = tabRects
        let selected = selected
        // Unselected tabs first, so the selected one overlaps its neighbours.
        let order = rects.indices.sorted { (windows[$0] === selected ? 1 : 0) < (windows[$1] === selected ? 1 : 0) }
        for index in order {
            drawTab(windows[index], in: rects[index], index: index, isSelected: windows[index] === selected)
        }
        drawAddBox()
        drawSwitcher()
    }

    private func drawTab(_ window: NSWindow, in rect: NSRect, index: Int, isSelected: Bool) {
        var tab = rect
        if isSelected {
            // Raised and merged into the baseline.
            tab.origin.y -= 2
            tab.size.height += 3
        }
        let radius: CGFloat = 4
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: tab.minX + 0.5, y: tab.maxY))
        outline.line(to: NSPoint(x: tab.minX + 0.5, y: tab.minY + radius))
        outline.appendArc(withCenter: NSPoint(x: tab.minX + radius, y: tab.minY + radius), radius: radius - 0.5,
                          startAngle: 180, endAngle: 270)
        outline.line(to: NSPoint(x: tab.maxX - radius, y: tab.minY + 0.5))
        outline.appendArc(withCenter: NSPoint(x: tab.maxX - radius, y: tab.minY + radius), radius: radius - 0.5,
                          startAngle: 270, endAngle: 360)
        outline.line(to: NSPoint(x: tab.maxX - 0.5, y: tab.maxY))
        (isSelected ? Chrome.Platinum.panel : Chrome.Platinum.frame).setFill()
        outline.fill()
        // Highlight along the top and left edges.
        NSColor.white.setFill()
        NSRect(x: tab.minX + radius, y: tab.minY + 1, width: tab.width - radius * 2, height: 1).fill()
        NSRect(x: tab.minX + 1, y: tab.minY + radius, width: 1, height: tab.height - radius - (isSelected ? 0 : 1)).fill()
        (isSelected ? Chrome.Platinum.dark : Chrome.Platinum.stripe).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        let close = closeRect(in: tab)
        drawCloseBox(in: close, pressed: hoveredClose == index)

        var title = window.title
        if window.isDocumentEdited { title = "• " + title }
        let document = window.windowController?.document as? TextDocument
        if document?.isPinned == true { title = "📌 " + title }
        if let color = document?.tabColor?.color {
            // The tab's color as a stripe along its bottom edge.
            color.setFill()
            NSRect(x: tab.minX + 4, y: tab.maxY - (isSelected ? 4 : 3), width: tab.width - 8, height: 2).fill()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Chrome.font(ofSize: 11),
            .foregroundColor: isSelected ? NSColor.black : Chrome.Platinum.dark,
            .paragraphStyle: paragraph,
        ]
        let textHeight = (title as NSString).size(withAttributes: attributes).height
        let textRect = NSRect(x: close.maxX + 4, y: (tab.midY - textHeight / 2).rounded(),
                              width: tab.maxX - close.maxX - 12, height: textHeight)
        (title as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func drawCloseBox(in rect: NSRect, pressed: Bool) {
        Chrome.Platinum.dark.setFill()
        rect.fill()
        let face = rect.insetBy(dx: 1, dy: 1)
        if pressed {
            Chrome.Platinum.pressed.setFill()
            face.fill()
        } else {
            NSGradient(starting: .white, ending: Chrome.Platinum.boxShade)?.draw(in: face, angle: -45)
        }
    }

    private func drawAddBox() {
        let rect = addRect
        Chrome.Platinum.dark.setFill()
        rect.fill()
        let face = rect.insetBy(dx: 1, dy: 1)
        NSGradient(starting: .white, ending: Chrome.Platinum.boxShade)?.draw(in: face, angle: -45)
        Chrome.Platinum.dark.setFill()
        NSRect(x: face.midX - 3, y: face.midY.rounded(.down), width: 7, height: 1).fill()
        NSRect(x: face.midX.rounded(.down), y: face.midY - 3, width: 1, height: 7).fill()
    }

    // MARK: Interaction

    /// These tabs are drawn here, so unlike native ones they can have
    /// Notepad++'s whole tab menu, for the tab clicked.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let windows = windows
        guard let index = tabRects.firstIndex(where: { $0.contains(point) }), index < windows.count,
              let controller = windows[index].windowController as? DocumentWindowController
        else { return nil }
        let menu = NSMenu(title: String(localized: "Tab"))
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
        if let index = switcherRects.firstIndex(where: { $0.contains(point) }) {
            sidebar?.select(Self.switcherTabs[index])
            redraw()
            return
        }
        if addRect.contains(point) {
            NSDocumentController.shared.newDocument(nil)
            return
        }
        let windows = windows
        guard let index = tabRects.firstIndex(where: { $0.contains(point) }), index < windows.count else {
            // A double click on the free space opens a new tab, like the + box.
            if event.clickCount == 2, point.x > (tabRects.last?.maxX ?? sidebarEdge) {
                NSDocumentController.shared.newDocument(nil)
                return
            }
            super.mouseDown(with: event)
            return
        }
        let target = windows[index]
        if closeRect(in: tabRects[index]).insetBy(dx: -2, dy: -2).contains(point) {
            // Track the close box like a button: act only if released inside.
            hoveredClose = index
            needsDisplay = true
            var inside = true
            while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
                inside = closeRect(in: tabRects[index]).insetBy(dx: -2, dy: -2).contains(convert(next.locationInWindow, from: nil))
                hoveredClose = inside ? index : nil
                needsDisplay = true
                if next.type == .leftMouseUp { break }
            }
            hoveredClose = nil
            needsDisplay = true
            if inside { target.performClose(nil) }
            return
        }
        if let group = target.tabGroup {
            group.selectedWindow = target
        }
        target.makeKeyAndOrderFront(nil)
    }
}

/// One of the square Platinum title-bar boxes.
final class ClassicWindowBox: NSButton {
    enum Kind { case close, zoom, collapse }

    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        switch kind {
        case .close: toolTip = String(localized: "Close")
        case .zoom: toolTip = String(localized: "Zoom")
        case .collapse: toolTip = String(localized: "Minimize")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        let pressed = isHighlighted

        // Frame-coloured ring, dark outline, then the bevelled face.
        let face = rect.insetBy(dx: 1, dy: 1)
        Chrome.Platinum.dark.setFill()
        face.fill()
        let inner = face.insetBy(dx: 1, dy: 1)
        if pressed {
            Chrome.Platinum.pressed.setFill()
            inner.fill()
        } else {
            NSGradient(starting: .white, ending: Chrome.Platinum.boxShade)?.draw(in: inner, angle: 45)
            Chrome.Platinum.shadow.setFill()
            NSRect(x: inner.minX, y: inner.maxY - 1, width: inner.width, height: 1).fill()
            NSRect(x: inner.maxX - 1, y: inner.minY, width: 1, height: inner.height).fill()
        }

        Chrome.Platinum.dark.setStroke()
        switch kind {
        case .close:
            break
        case .zoom:
            // A small window inside the box, with a thicker title edge.
            let window = inner.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(rect: window.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
            Chrome.Platinum.dark.setFill()
            NSRect(x: window.minX, y: window.minY, width: window.width, height: 2).fill()
        case .collapse:
            // Two horizontal lines: the window shade.
            Chrome.Platinum.dark.setFill()
            let width = inner.width - 2
            NSRect(x: inner.minX + 1, y: inner.minY + 2, width: width, height: 1).fill()
            NSRect(x: inner.minX + 1, y: inner.minY + 5, width: width, height: 1).fill()
        }
    }
}

/// Always-visible Platinum scroller: dotted track, lavender bevelled thumb with
/// grip ridges, and arrow buttons at the end of the track.
final class ClassicScroller: NSScroller {
    private static let width: CGFloat = 16

    override class var isCompatibleWithOverlayScrollers: Bool { false }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        width
    }

    private var isVertical: Bool { bounds.height >= bounds.width }

    /// Decrement and increment arrow buttons at either end of the track, the
    /// Mac OS 9 default.
    private var arrowRects: (decrement: NSRect, increment: NSRect) {
        let side = Self.width
        if isVertical {
            return (NSRect(x: 0, y: 0, width: bounds.width, height: side),
                    NSRect(x: 0, y: bounds.maxY - side, width: bounds.width, height: side))
        }
        return (NSRect(x: 0, y: 0, width: side, height: bounds.height),
                NSRect(x: bounds.maxX - side, y: 0, width: side, height: bounds.height))
    }

    override func rect(for partCode: NSScroller.Part) -> NSRect {
        let side = Self.width
        let slot = isVertical
            ? NSRect(x: 0, y: side, width: bounds.width, height: max(0, bounds.height - side * 2))
            : NSRect(x: side, y: 0, width: max(0, bounds.width - side * 2), height: bounds.height)
        switch partCode {
        case .knobSlot:
            return slot
        case .knob:
            guard isEnabled, knobProportion < 1 else { return .zero }
            if isVertical {
                let length = max(side, (slot.height * knobProportion).rounded())
                let offset = ((slot.height - length) * doubleValue).rounded()
                return NSRect(x: 0, y: slot.minY + offset, width: slot.width, height: length)
            }
            let length = max(side, (slot.width * knobProportion).rounded())
            let offset = ((slot.width - length) * doubleValue).rounded()
            return NSRect(x: slot.minX + offset, y: 0, width: length, height: slot.height)
        case .decrementLine:
            return arrowRects.decrement
        case .incrementLine:
            return arrowRects.increment
        default:
            return super.rect(for: partCode)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawKnobSlot(in: rect(for: .knobSlot), highlight: false)
        drawArrow(in: arrowRects.decrement, pointingForward: false, pressed: pressedArrow == .decrementLine)
        drawArrow(in: arrowRects.increment, pointingForward: true, pressed: pressedArrow == .incrementLine)
        drawKnob()
        // Outline separating the scroller from the text.
        Chrome.Platinum.shadow.setFill()
        if isVertical {
            NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        } else {
            NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        }
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        let pattern = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { _ in
            Chrome.Platinum.panel.setFill()
            NSRect(x: 0, y: 0, width: 2, height: 2).fill()
            Chrome.Platinum.bar.setFill()
            NSRect(x: 0, y: 0, width: 1, height: 1).fill()
            NSRect(x: 1, y: 1, width: 1, height: 1).fill()
            return true
        }
        NSColor(patternImage: pattern).setFill()
        slotRect.fill()
    }

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.width > 0, knob.height > 0 else { return }
        drawBevel(in: knob, fill: Chrome.Platinum.thumb, pressed: false)

        // Grip ridges in the middle of the thumb.
        let count = 4
        for index in 0..<count {
            let step = CGFloat(index) * 2 - CGFloat(count - 1)
            if isVertical {
                let y = (knob.midY + step).rounded(.down)
                guard knob.height > 20 else { break }
                NSColor.white.setFill()
                NSRect(x: knob.midX - 4, y: y, width: 7, height: 1).fill()
                Chrome.Platinum.thumbShadow.setFill()
                NSRect(x: knob.midX - 3, y: y + 1, width: 7, height: 1).fill()
            } else {
                let x = (knob.midX + step).rounded(.down)
                guard knob.width > 20 else { break }
                NSColor.white.setFill()
                NSRect(x: x, y: knob.midY - 4, width: 1, height: 7).fill()
                Chrome.Platinum.thumbShadow.setFill()
                NSRect(x: x + 1, y: knob.midY - 3, width: 1, height: 7).fill()
            }
        }
    }

    private func drawArrow(in rect: NSRect, pointingForward: Bool, pressed: Bool) {
        drawBevel(in: rect, fill: pressed ? Chrome.Platinum.pressed : Chrome.Platinum.frame, pressed: pressed)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let path = NSBezierPath()
        // Scroller coordinates are flipped: increment points down or right.
        if isVertical {
            let direction: CGFloat = pointingForward ? 1 : -1
            path.move(to: NSPoint(x: center.x - 4, y: center.y - 2 * direction))
            path.line(to: NSPoint(x: center.x + 4, y: center.y - 2 * direction))
            path.line(to: NSPoint(x: center.x, y: center.y + 2 * direction))
        } else {
            let direction: CGFloat = pointingForward ? 1 : -1
            path.move(to: NSPoint(x: center.x - 2 * direction, y: center.y - 4))
            path.line(to: NSPoint(x: center.x - 2 * direction, y: center.y + 4))
            path.line(to: NSPoint(x: center.x + 2 * direction, y: center.y))
        }
        path.close()
        (isEnabled && knobProportion < 1 ? Chrome.Platinum.dark : Chrome.Platinum.shadow).setFill()
        path.fill()
    }

    private func drawBevel(in rect: NSRect, fill: NSColor, pressed: Bool) {
        Chrome.Platinum.dark.setFill()
        rect.fill()
        let face = rect.insetBy(dx: 1, dy: 1)
        fill.setFill()
        face.fill()
        (pressed ? Chrome.Platinum.dark : NSColor.white).setFill()
        NSRect(x: face.minX, y: face.minY, width: face.width, height: 1).fill()
        NSRect(x: face.minX, y: face.minY, width: 1, height: face.height).fill()
        (pressed ? NSColor.white : Chrome.Platinum.shadow).setFill()
        NSRect(x: face.minX, y: face.maxY - 1, width: face.width, height: 1).fill()
        NSRect(x: face.maxX - 1, y: face.minY, width: 1, height: face.height).fill()
    }

    // MARK: Arrow tracking

    private var pressedArrow: NSScroller.Part?

    /// Modern NSScroller has no arrows, so arrow clicks scroll the clip view
    /// directly, repeating while the button is held. Everything else (knob
    /// dragging, page clicks in the track) is left to NSScroller.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let arrows = arrowRects
        let part: NSScroller.Part? = arrows.decrement.contains(point) ? .decrementLine
            : arrows.increment.contains(point) ? .incrementLine : nil
        guard let part, let scrollView = enclosingScrollView, isEnabled else {
            super.mouseDown(with: event)
            return
        }
        pressedArrow = part
        needsDisplay = true
        scrollLine(scrollView, part: part)
        // Repeat while held, after an initial delay, until mouse-up.
        var deadline = Date(timeIntervalSinceNow: 0.35)
        while true {
            if let next = window?.nextEvent(matching: [.leftMouseUp], until: deadline, inMode: .eventTracking, dequeue: true),
               next.type == .leftMouseUp {
                break
            }
            let location = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
            if rect(for: part).contains(location) {
                scrollLine(scrollView, part: part)
            }
            deadline = Date(timeIntervalSinceNow: 0.05)
        }
        pressedArrow = nil
        needsDisplay = true
    }

    private func scrollLine(_ scrollView: NSScrollView, part: NSScroller.Part) {
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        let sign: CGFloat = part == .incrementLine ? 1 : -1
        if isVertical {
            let line = max(scrollView.verticalLineScroll, 16)
            origin.y += line * sign * (clip.isFlipped ? 1 : -1)
        } else {
            origin.x += max(scrollView.horizontalLineScroll, 16) * sign
        }
        let document = scrollView.documentView?.frame ?? .zero
        origin.x = min(max(origin.x, document.minX), max(document.minX, document.maxX - clip.bounds.width))
        origin.y = min(max(origin.y, document.minY), max(document.minY, document.maxY - clip.bounds.height))
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }
}
