import AppKit
import UniformTypeIdentifiers

/// A lazily loaded file or folder in the workspace tree.
final class FileNode: NSObject {
    let url: URL
    let isDirectory: Bool
    let isRoot: Bool
    private var cachedChildren: [FileNode]?

    init(url: URL, isDirectory: Bool, isRoot: Bool = false) {
        self.url = url
        self.isDirectory = isDirectory
        self.isRoot = isRoot
    }

    var children: [FileNode] {
        if let cachedChildren { return cachedChildren }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey]
        let options: FileManager.DirectoryEnumerationOptions = Preferences.showHiddenFiles ? [] : [.skipsHiddenFiles]
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)) ?? []
        let nodes = urls.map { url -> FileNode in
            let values = try? url.resourceValues(forKeys: Set(keys))
            // Packages (.app, .xcodeproj…) behave as files, as in Finder.
            let isFolder = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            return FileNode(url: url, isDirectory: isFolder)
        }
        // Folders first, then Finder-style natural order.
        let sorted = nodes.sorted {
            $0.isDirectory != $1.isDirectory
                ? $0.isDirectory
                : $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
        cachedChildren = sorted
        return sorted
    }
}

/// Sidebar tab listing the workspace folders (Notepad++'s "Folder as Workspace").
final class FileTreeViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private let outlineView = NSOutlineView()
    private let emptyState = SidebarEmptyState(
        title: String(localized: "No Folder Open"),
        message: String(localized: "Open a folder to browse its files here. You can also drop folders onto the sidebar."),
        buttonTitle: String(localized: "Open Folder…"))
    private var roots: [FileNode] = []

    override func loadView() {
        let column = NSTableColumn(identifier: .init("name"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .default
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(openSelection(_:))
        outlineView.autosaveName = "WorkspaceTree"
        outlineView.autosaveExpandedItems = true
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        outlineView.menu = NSMenu()
        outlineView.menu?.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        emptyState.button.target = self
        emptyState.button.action = #selector(addFolder(_:))

        let container = NSView()
        for view in [scrollView, emptyState] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
        view = container

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(reload), name: Workspace.didChange, object: nil)
        center.addObserver(self, selector: #selector(reload), name: Workspace.contentsDidChange, object: nil)
        center.addObserver(self, selector: #selector(preferencesDidChange), name: Preferences.didChange, object: nil)
        reload()
    }

    // MARK: Data

    private var showsHiddenFiles = Preferences.showHiddenFiles
    private var theme = Preferences.theme

    @objc private func preferencesDidChange() {
        if showsHiddenFiles != Preferences.showHiddenFiles {
            showsHiddenFiles = Preferences.showHiddenFiles
            reload()
        } else if theme != Preferences.theme {
            theme = Preferences.theme
            outlineView.reloadData()
        }
    }

    /// Rebuilds the tree from disk, keeping expanded folders and the selection.
    @objc func reload() {
        let expanded = Set((0..<outlineView.numberOfRows).compactMap { row -> URL? in
            guard let node = outlineView.item(atRow: row) as? FileNode, outlineView.isItemExpanded(node) else { return nil }
            return node.url
        })
        let selected = (outlineView.item(atRow: outlineView.selectedRow) as? FileNode)?.url

        roots = Workspace.shared.folders.map { FileNode(url: $0, isDirectory: true, isRoot: true) }
        outlineView.reloadData()
        emptyState.isHidden = !roots.isEmpty

        func restore(_ nodes: [FileNode]) {
            for node in nodes where node.isDirectory && (expanded.contains(node.url) || (expanded.isEmpty && node.isRoot)) {
                outlineView.expandItem(node)
                restore(node.children)
            }
        }
        restore(roots)
        if let selected, let row = (0..<outlineView.numberOfRows).first(where: { (outlineView.item(atRow: $0) as? FileNode)?.url == selected }) {
            outlineView.selectRowIndexes([row], byExtendingSelection: false)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? FileNode else { return roots.count }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FileNode else { return roots[index] }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? {
        (item as? FileNode)?.url.path
    }

    func outlineView(_ outlineView: NSOutlineView, itemForPersistentObject object: Any) -> Any? {
        guard let path = object as? String else { return nil }
        func find(_ nodes: [FileNode]) -> FileNode? {
            for node in nodes {
                if node.url.path == path { return node }
                if node.isDirectory, path.hasPrefix(node.url.path + "/"), let match = find(node.children) { return match }
            }
            return nil
        }
        return find(roots)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let cell = SidebarCell.dequeue("FileCell", from: outlineView)
        cell.textField?.stringValue = node.isRoot ? FileManager.default.displayName(atPath: node.url.path) : node.url.lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: node.url.path)
        icon.size = NSSize(width: 16, height: 16)
        cell.imageView?.image = icon
        cell.toolTip = node.url.path
        return cell
    }

    // MARK: Opening

    @objc private func openSelection(_ sender: Any?) {
        for row in outlineView.selectedRowIndexes {
            guard let node = outlineView.item(atRow: row) as? FileNode else { continue }
            if node.isDirectory {
                outlineView.isItemExpanded(node) ? outlineView.collapseItem(node) : outlineView.expandItem(node)
            } else {
                open(node.url)
            }
        }
    }

    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {  // Return, Enter
            openSelection(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func addFolder(_ sender: Any?) {
        Workspace.shared.chooseFolder(for: view.window)
    }

    // MARK: Context menu

    private var clickedNode: FileNode? {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        return outlineView.item(atRow: row) as? FileNode
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let node = clickedNode else {
            menu.addItem(withTitle: String(localized: "Add Folder to Workspace…"), action: #selector(addFolder(_:)), keyEquivalent: "").target = self
            return
        }
        if !node.isDirectory {
            menu.addItem(withTitle: String(localized: "Open"), action: #selector(openClicked(_:)), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: String(localized: "Show in Finder"), action: #selector(revealClicked(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Copy Path"), action: #selector(copyPath(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Refresh"), action: #selector(reload), keyEquivalent: "").target = self
        if node.isRoot {
            menu.addItem(.separator())
            menu.addItem(withTitle: String(localized: "Remove Folder from Workspace"), action: #selector(removeRoot(_:)), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Add Folder to Workspace…"), action: #selector(addFolder(_:)), keyEquivalent: "").target = self
    }

    @objc private func openClicked(_ sender: Any?) {
        guard let node = clickedNode else { return }
        open(node.url)
    }

    @objc private func revealClicked(_ sender: Any?) {
        guard let node = clickedNode else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    @objc private func copyPath(_ sender: Any?) {
        guard let node = clickedNode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.url.path, forType: .string)
    }

    @objc private func removeRoot(_ sender: Any?) {
        guard let node = clickedNode, node.isRoot else { return }
        Workspace.shared.remove(node.url)
    }

    // MARK: Drag and drop

    /// Files drag out of the sidebar into other apps (Finder, Terminal, Mail…).
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        (item as? FileNode)?.url as NSURL?
    }

    /// Folders dropped onto the sidebar join the workspace.
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard info.draggingSource as? NSOutlineView !== outlineView, !droppedFolders(info).isEmpty else { return [] }
        outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .link
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let folders = droppedFolders(info)
        folders.forEach(Workspace.shared.add)
        return !folders.isEmpty
    }

    private func droppedFolders(_ info: any NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}

/// Image + label cell shared by the sidebar lists.
@MainActor
enum SidebarCell {
    /// A reused or new cell, in the current theme's font.
    static func dequeue(_ identifier: String, from outlineView: NSOutlineView) -> NSTableCellView {
        let cell = outlineView.makeView(withIdentifier: .init(identifier), owner: nil) as? NSTableCellView ?? make(identifier: identifier)
        cell.textField?.font = Chrome.isClassic ? Chrome.font(ofSize: 11) : .systemFont(ofSize: NSFont.systemFontSize)
        return cell
    }

    private static func make(identifier: String) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = .init(identifier)
        let imageView = NSImageView()
        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingMiddle
        for view in [imageView, textField] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        cell.imageView = imageView
        cell.textField = textField
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// The axolotl mascot, title, explanation and optional button for empty sidebar tabs.
final class SidebarEmptyState: NSView {
    let titleLabel: NSTextField
    let messageLabel: NSTextField
    let button: NSButton

    init(title: String, message: String, buttonTitle: String?) {
        titleLabel = NSTextField(labelWithString: title)
        messageLabel = NSTextField(wrappingLabelWithString: message)
        button = NSButton(title: buttonTitle ?? "", target: nil, action: nil)
        super.init(frame: .zero)

        let image = NSImageView(image: NSImage(named: "Mascot") ?? NSImage())
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityLabel(String(localized: "MacPad++ axolotl"))
        image.widthAnchor.constraint(equalToConstant: 88).isActive = true
        image.heightAnchor.constraint(equalToConstant: 72).isActive = true
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        messageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        messageLabel.textColor = .tertiaryLabelColor
        messageLabel.alignment = .center
        button.controlSize = .small
        button.isHidden = buttonTitle == nil

        let stack = NSStackView(views: [image, titleLabel, messageLabel, button])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.setCustomSpacing(10, after: image)
        stack.setCustomSpacing(10, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
