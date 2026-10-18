import AppKit

/// The window sidebar: Folder Workspace and Function List. The switcher between
/// them lives in the window's top row, as close to the top as possible: a
/// toolbar item (see `SidebarSwitcher`), or the Classic theme's tab strip.
final class SidebarViewController: NSViewController {
    enum Tab: Int {
        case files, symbols

        var symbolName: String {
            switch self {
            case .files: "folder"
            case .symbols: "list.bullet.indent"
            }
        }

        var title: String {
            switch self {
            case .files: String(localized: "Folder Workspace")
            case .symbols: String(localized: "Function List")
            }
        }

        var toolTip: String {
            switch self {
            case .files: String(localized: "Folder Workspace (⌃⌘1)")
            case .symbols: String(localized: "Function List (⌃⌘2)")
            }
        }
    }

    static let tabKey = "sidebarTab"
    /// Wide enough for the traffic lights, the sidebar button and the switcher
    /// sharing the toolbar row above the sidebar.
    static let minimumWidth: CGFloat = 220
    static let tabDidChange = Notification.Name("MacPadSidebarTabDidChange")

    let files = FileTreeViewController()
    let symbols = FunctionListViewController()
    private let content = NSView()
    private let classicBackground = NSView()
    /// The lists' own source-list background, restored when leaving Classic.
    private var listBackground: NSColor?
    /// Distance from the top of the sidebar to its content; see `updateContentTop()`.
    private var contentTop: NSLayoutConstraint!

    private(set) var tab: Tab = .files {
        didSet { show(tab) }
    }

    override func loadView() {
        classicBackground.wantsLayer = true
        classicBackground.layer?.backgroundColor = Chrome.Platinum.panel.cgColor

        let container = NSView()
        for view in [classicBackground, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            classicBackground.topAnchor.constraint(equalTo: container.topAnchor),
            classicBackground.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            classicBackground.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            classicBackground.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumWidth),
        ])
        contentTop = content.topAnchor.constraint(equalTo: container.topAnchor)
        contentTop.isActive = true
        view = container

        addChild(files)
        addChild(symbols)
        tab = Tab(rawValue: UserDefaults.standard.integer(forKey: Self.tabKey)) ?? .files

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(tabDidChangeElsewhere), name: Self.tabDidChange, object: nil)
        center.addObserver(self, selector: #selector(applyChrome), name: Preferences.didChange, object: nil)
        applyChrome()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateContentTop()
    }

    /// The safe area also covers the tab bar's height, though the tab bar only
    /// spans the editor; start right below the toolbar instead.
    private func updateContentTop() {
        let safeTop = view.safeAreaInsets.top
        var top = safeTop
        if !Chrome.isClassic, let frameView = view.window?.contentView?.superview,
           let toolbarView = Self.descendant(of: frameView, named: "NSToolbarView"), !toolbarView.isHidden {
            let toolbarBottom = view.bounds.maxY - toolbarView.convert(toolbarView.bounds, to: view).minY
            top = min(safeTop, max(0, toolbarBottom))
        }
        if contentTop.constant != top {
            contentTop.constant = top
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

    @objc private func applyChrome() {
        view.needsLayout = true
        let classic = Chrome.isClassic
        classicBackground.isHidden = !classic
        // Source lists paint their own grey, which would hide the Platinum panel.
        for list in [files.view, symbols.view].flatMap(Self.outlineViews(in:)) {
            if listBackground == nil { listBackground = list.backgroundColor }
            list.backgroundColor = classic ? .clear : (listBackground ?? list.backgroundColor)
        }
    }

    private static func outlineViews(in view: NSView) -> [NSOutlineView] {
        (view as? NSOutlineView).map { [$0] } ?? view.subviews.flatMap(outlineViews(in:))
    }

    private func show(_ tab: Tab) {
        let child = tab == .files ? files.view : symbols.view
        guard child.superview !== content else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        child.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: content.topAnchor),
            child.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
    }

    /// Selects a tab here and in every other window, and remembers it.
    func select(_ tab: Tab) {
        self.tab = tab
        UserDefaults.standard.set(tab.rawValue, forKey: Self.tabKey)
        NotificationCenter.default.post(name: Self.tabDidChange, object: self)
    }

    @objc private func tabDidChangeElsewhere(_ notification: Notification) {
        guard notification.object as? SidebarViewController !== self else { return }
        tab = Tab(rawValue: UserDefaults.standard.integer(forKey: Self.tabKey)) ?? .files
    }
}

/// Toolbar control switching the sidebar between its tabs. It sits over the
/// sidebar, next to the sidebar button, and hides with the sidebar.
final class SidebarSwitcher: NSSegmentedControl {
    static let itemIdentifier = NSToolbarItem.Identifier("SidebarSwitcher")

    private let tabs: [SidebarViewController.Tab] = [.files, .symbols]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        segmentCount = tabs.count
        trackingMode = .selectOne
        segmentStyle = .automatic
        for (index, tab) in tabs.enumerated() {
            setImage(NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title), forSegment: index)
            setToolTip(tab.toolTip, forSegment: index)
        }
        target = self
        action = #selector(segmentChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(sync), name: SidebarViewController.tabDidChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var sidebar: SidebarViewController? {
        (window?.contentViewController as? DocumentSplitViewController)?.sidebar
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        sync()
    }

    @objc private func sync() {
        let tab = sidebar?.tab ?? SidebarViewController.Tab(rawValue: UserDefaults.standard.integer(forKey: SidebarViewController.tabKey)) ?? .files
        selectedSegment = tabs.firstIndex(of: tab) ?? 0
    }

    @objc private func segmentChanged() {
        guard tabs.indices.contains(selectedSegment) else { return }
        sidebar?.select(tabs[selectedSegment])
    }
}

/// Sidebar + editor. Sidebar visibility is shared by all windows, so switching
/// tabs (each a window) keeps the same layout, as Notepad++'s panels do.
final class DocumentSplitViewController: NSSplitViewController {
    static let collapsedKey = "sidebarCollapsed"
    static let collapsedDidChange = Notification.Name("MacPadSidebarCollapsedDidChange")

    let sidebar = SidebarViewController()
    let editorController: EditorViewController
    private var sidebarItem: NSSplitViewItem!

    init(editorController: EditorViewController) {
        self.editorController = editorController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sidebarItem = makeSidebarItem()
        let editorItem = NSSplitViewItem(viewController: editorController)
        editorItem.minimumThickness = 320
        addSplitViewItem(sidebarItem)
        addSplitViewItem(editorItem)
        splitView.autosaveName = "DocumentSplit"
        sidebar.symbols.editor = editorController.editor

        NotificationCenter.default.addObserver(self, selector: #selector(collapsedDidChangeElsewhere(_:)), name: Self.collapsedDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyChrome), name: Preferences.didChange, object: nil)
    }

    /// The system sidebar floats on glass; the Classic theme wants a plain
    /// Platinum pane, so it uses an ordinary split item instead.
    private func makeSidebarItem() -> NSSplitViewItem {
        let item = Chrome.isClassic ? NSSplitViewItem(viewController: sidebar) : NSSplitViewItem(sidebarWithViewController: sidebar)
        item.minimumThickness = SidebarViewController.minimumWidth
        item.maximumThickness = 420
        item.canCollapse = true
        item.holdingPriority = .defaultLow + 10
        item.isCollapsed = UserDefaults.standard.object(forKey: Self.collapsedKey) as? Bool ?? true
        return item
    }

    /// When the sidebar last started to show or hide.
    private var lastToggle = Date.distantPast

    @objc private func applyChrome() {
        let wantsSidebarBehavior = !Chrome.isClassic
        guard (sidebarItem.behavior == .sidebar) != wantsSidebarBehavior else { return }
        // Removing an item mid-animation makes AppKit throw when it finishes.
        let wait = 0.6 - Date().timeIntervalSince(lastToggle)
        if wait > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.applyChrome() }
            return
        }
        removeSplitViewItem(sidebarItem)
        sidebarItem = makeSidebarItem()
        insertSplitViewItem(sidebarItem, at: 0)
    }

    /// View ▸ Show/Hide Sidebar. Not `toggleSidebar(_:)`: AppKit only routes that
    /// to a split view controller with a system sidebar item, which the
    /// Classic theme replaces with a plain pane.
    @objc func toggleSidebarPane(_ sender: Any?) {
        toggleSidebar(sender)
    }

    override func toggleSidebar(_ sender: Any?) {
        // isCollapsed flips at the end of the animation; record the target state now.
        let collapsed = !sidebarItem.isCollapsed
        lastToggle = Date()
        if sidebarItem.behavior == .sidebar {
            super.toggleSidebar(sender)
        } else {
            sidebarItem.animator().isCollapsed = collapsed
        }
        UserDefaults.standard.set(collapsed, forKey: Self.collapsedKey)
        NotificationCenter.default.post(name: Self.collapsedDidChange, object: self)
    }

    /// Shows the sidebar on a given tab (View ▸ Folder Workspace / Function List).
    func reveal(_ tab: SidebarViewController.Tab) {
        if sidebarItem.isCollapsed {
            toggleSidebar(nil)
        }
        sidebar.select(tab)
    }

    @objc private func collapsedDidChangeElsewhere(_ notification: Notification) {
        guard notification.object as? DocumentSplitViewController !== self else { return }
        sidebarItem.isCollapsed = UserDefaults.standard.bool(forKey: Self.collapsedKey)
    }

    @objc func showFolderWorkspace(_ sender: Any?) {
        reveal(.files)
    }

    @objc func showFunctionList(_ sender: Any?) {
        reveal(.symbols)
    }

    @objc func openFolder(_ sender: Any?) {
        reveal(.files)
        Workspace.shared.chooseFolder(for: view.window)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(toggleSidebarPane(_:)) {
            (item as? NSMenuItem)?.title = sidebarItem.isCollapsed ? String(localized: "Show Sidebar") : String(localized: "Hide Sidebar")
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
