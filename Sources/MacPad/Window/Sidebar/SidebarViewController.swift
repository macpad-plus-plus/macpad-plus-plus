import AppKit

/// The window sidebar: Folder Workspace and Function List, switched with a
/// segmented control as in Xcode's navigator.
final class SidebarViewController: NSViewController {
    enum Tab: Int {
        case files, symbols
    }

    static let tabKey = "sidebarTab"
    static let tabDidChange = Notification.Name("MacPadSidebarTabDidChange")

    let files = FileTreeViewController()
    let symbols = FunctionListViewController()
    private let switcher = NSSegmentedControl()
    private let content = NSView()
    private let classicBackground = NSView()

    var tab: Tab {
        get { Tab(rawValue: switcher.selectedSegment) ?? .files }
        set {
            switcher.selectedSegment = newValue.rawValue
            show(newValue)
        }
    }

    override func loadView() {
        switcher.segmentCount = 2
        switcher.trackingMode = .selectOne
        switcher.segmentStyle = .automatic
        switcher.setImage(NSImage(systemSymbolName: "folder", accessibilityDescription: String(localized: "Folder Workspace")), forSegment: 0)
        switcher.setImage(NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: String(localized: "Function List")), forSegment: 1)
        switcher.setToolTip(String(localized: "Folder Workspace (⌃⌘1)"), forSegment: 0)
        switcher.setToolTip(String(localized: "Function List (⌃⌘2)"), forSegment: 1)
        switcher.target = self
        switcher.action = #selector(switcherChanged(_:))

        let header = NSStackView(views: [switcher])
        header.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 6, right: 8)
        header.alignment = .centerX

        classicBackground.wantsLayer = true
        classicBackground.layer?.backgroundColor = Chrome.Platinum.panel.cgColor

        let container = NSView()
        for view in [classicBackground, header, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            classicBackground.topAnchor.constraint(equalTo: container.topAnchor),
            classicBackground.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            classicBackground.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            classicBackground.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: header.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
        view = container

        addChild(files)
        addChild(symbols)
        tab = Tab(rawValue: UserDefaults.standard.integer(forKey: Self.tabKey)) ?? .files

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(tabDidChangeElsewhere), name: Self.tabDidChange, object: nil)
        center.addObserver(self, selector: #selector(applyChrome), name: Preferences.didChange, object: nil)
        applyChrome()
    }

    @objc private func applyChrome() {
        classicBackground.isHidden = !Chrome.isClassic
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

    @objc private func switcherChanged(_ sender: NSSegmentedControl) {
        select(tab)
    }

    @objc private func tabDidChangeElsewhere(_ notification: Notification) {
        guard notification.object as? SidebarViewController !== self else { return }
        tab = Tab(rawValue: UserDefaults.standard.integer(forKey: Self.tabKey)) ?? .files
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
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true
        sidebarItem.isCollapsed = UserDefaults.standard.object(forKey: Self.collapsedKey) as? Bool ?? true
        let editorItem = NSSplitViewItem(viewController: editorController)
        editorItem.minimumThickness = 320
        addSplitViewItem(sidebarItem)
        addSplitViewItem(editorItem)
        splitView.autosaveName = "DocumentSplit"
        sidebar.symbols.editor = editorController.editor

        NotificationCenter.default.addObserver(self, selector: #selector(collapsedDidChangeElsewhere(_:)), name: Self.collapsedDidChange, object: nil)
    }

    override func toggleSidebar(_ sender: Any?) {
        super.toggleSidebar(sender)
        // isCollapsed flips at the end of the animation; record the target state now.
        let collapsed = !sidebarItem.isCollapsed
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
        if item.action == #selector(toggleSidebar(_:)), let menuItem = item as? NSMenuItem {
            menuItem.title = sidebarItem.isCollapsed ? String(localized: "Show Sidebar") : String(localized: "Hide Sidebar")
        }
        return super.validateUserInterfaceItem(item)
    }
}
