import AppKit

/// Sidebar tab listing the current document's functions, grouped by class
/// (Notepad++'s "Function List"), with a filter field.
final class FunctionListViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    /// A class (with children) or a function.
    final class Node: NSObject {
        let name: String
        let line: Int
        var children: [Node] = []
        let isContainer: Bool

        init(name: String, line: Int, isContainer: Bool) {
            self.name = name
            self.line = line
            self.isContainer = isContainer
        }
    }

    weak var editor: ScintillaEditor? {
        didSet { scheduleRefresh(delay: 0) }
    }

    private let outlineView = NSOutlineView()
    private let filterField = NSSearchField()
    private let emptyState = SidebarEmptyState(title: String(localized: "No Symbols"), message: "", buttonTitle: nil)
    private var symbols: [Symbol] = []
    private var roots: [Node] = []
    private var refreshTask: Task<Void, Never>?
    private var parseGeneration = 0

    override func loadView() {
        let column = NSTableColumn(identifier: .init("name"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(jumpToSelection(_:))

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        filterField.placeholderString = String(localized: "Filter")
        filterField.controlSize = .small
        filterField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        filterField.delegate = self
        filterField.sendsSearchStringImmediately = true

        let filterBar = NSStackView(views: [filterField])
        filterBar.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        let separator = NSBox()
        separator.boxType = .separator

        let container = NSView()
        for view in [scrollView, emptyState, separator, filterBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),
            emptyState.topAnchor.constraint(equalTo: scrollView.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            filterBar.topAnchor.constraint(equalTo: separator.bottomAnchor),
            filterBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            filterBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(editorDidChange(_:)), name: ScintillaEditor.contentDidChange, object: nil)
        center.addObserver(self, selector: #selector(preferencesDidChange), name: Preferences.didChange, object: nil)
    }

    // MARK: Parsing

    @objc private func editorDidChange(_ notification: Notification) {
        guard notification.object as? ScintillaEditor === editor else { return }
        scheduleRefresh(delay: 0.6)
    }

    private var theme = Preferences.theme

    @objc private func preferencesDidChange() {
        guard theme != Preferences.theme else { return }
        theme = Preferences.theme
        outlineView.reloadData()
    }

    /// Parses off the main thread, after a pause in typing.
    private func scheduleRefresh(delay: TimeInterval) {
        refreshTask?.cancel()
        guard let editor else { return }
        let language = editor.language
        let unavailable = String(localized: "The function list isn't available for \(language.name).")
        guard FunctionListParser.hasParser(for: language.id) else {
            symbols = []
            rebuild(message: unavailable)
            return
        }
        let text = String(decoding: editor.utf8Text(), as: UTF8.self)
        parseGeneration += 1
        let generation = parseGeneration
        refreshTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            let id = language.id
            let found = await Task.detached(priority: .utility) { FunctionListParser.parser(for: id)?.parse(text) }.value
            guard !Task.isCancelled, let self, generation == self.parseGeneration else { return }
            self.symbols = found ?? []
            self.rebuild(message: found == nil ? unavailable : String(localized: "No functions found in this document."))
        }
    }

    private func rebuild(message: String) {
        let filter = filterField.stringValue.trimmingCharacters(in: .whitespaces)
        var containers: [String: Node] = [:]
        var result: [Node] = []
        for symbol in symbols where filter.isEmpty || symbol.name.localizedCaseInsensitiveContains(filter)
            || (symbol.container?.localizedCaseInsensitiveContains(filter) ?? false) {
            let node = Node(name: symbol.name, line: symbol.line, isContainer: false)
            if let containerName = symbol.container {
                if let container = containers[containerName] {
                    container.children.append(node)
                } else {
                    let container = Node(name: containerName, line: symbol.line, isContainer: true)
                    container.children.append(node)
                    containers[containerName] = container
                    result.append(container)
                }
            } else {
                result.append(node)
            }
        }
        roots = result
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
        emptyState.isHidden = !roots.isEmpty
        emptyState.titleLabel.stringValue = filter.isEmpty ? String(localized: "No Symbols") : String(localized: "No Matches")
        emptyState.messageLabel.stringValue = filter.isEmpty ? message : String(localized: "Nothing matches “\(filter)”.")
    }

    func controlTextDidChange(_ notification: Notification) {
        rebuild(message: String(localized: "No functions found in this document."))
    }

    // MARK: Outline

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Node)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.isContainer ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let cell = SidebarCell.dequeue("SymbolCell", from: outlineView)
        cell.textField?.stringValue = node.name
        cell.textField?.lineBreakMode = .byTruncatingTail
        // Xcode-style badges: a class "C" in purple, a function "ƒ" in blue.
        let symbol = node.isContainer ? "c.square.fill" : "f.square.fill"
        cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: node.isContainer ? String(localized: "Class") : String(localized: "Function"))
        cell.imageView?.contentTintColor = node.isContainer ? .systemPurple : .systemBlue
        cell.toolTip = String(localized: "\(node.name) — line \(node.line)")
        return cell
    }

    @objc private func jumpToSelection(_ sender: Any?) {
        guard let node = outlineView.item(atRow: outlineView.clickedRow) as? Node, let editor else { return }
        editor.goTo(line: node.line)
        view.window?.makeFirstResponder(editor.content())
    }
}
