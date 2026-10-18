import AppKit
import Scintilla

/// Hosts one document's find bar, editor and status bar, and handles editor
/// menu commands that reach it through the responder chain.
final class EditorViewController: NSViewController, NSMenuItemValidation, FindBarDelegate {
    let editor = ScintillaEditor(frame: .zero)
    private let findBar = FindBarView(frame: .zero)
    private let statusBar = StatusBarView(frame: .zero)
    private weak var document: TextDocument?

    /// Matches for the current query, kept sorted for the "n of m" counter.
    private var matches: ScintillaEditor.MatchList?
    /// Where incremental search restarts from while the query is being typed.
    private var searchAnchor = 0
    private var refreshWorkItem: DispatchWorkItem?

    init(document: TextDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let stack = NSStackView(views: [findBar, editor, statusBar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        stack.distribution = .fill
        editor.setContentHuggingPriority(.init(1), for: .vertical)
        editor.setContentCompressionResistancePriority(.init(1), for: .vertical)
        // The window extends under the toolbar; keep the content below it.
        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        findBar.isHidden = true
        findBar.delegate = self
        view = container

        editor.onDirtyChange = { [weak self] dirty in
            self?.document?.updateChangeCount(dirty ? .changeDone : .changeCleared)
        }
        editor.onStatusChange = { [weak self] in
            self?.refreshStatus()
            self?.updateMatchCounter()
        }
        editor.onTextChange = { [weak self] in
            self?.scheduleMatchRefresh()
        }
        document?.attach(editor: editor)
        refreshStatus()
    }

    func refreshStatus() {
        guard let document else { return }
        statusBar.update(caret: editor.caretInfo, language: editor.language, format: document.format)
    }

    // MARK: Language

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let language = Language.with(id: id) else { return }
        editor.setLanguage(language)
    }

    // MARK: Line endings

    @objc func selectLineEnding(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lineEnding = LineEnding(rawValue: raw),
              let document, document.format.lineEnding != lineEnding
        else { return }
        editor.setLineEnding(lineEnding, convertExisting: true)
        document.format.lineEnding = lineEnding
        refreshStatus()
    }

    // MARK: View options

    @objc func toggleWordWrap(_ sender: Any?) {
        editor.wrapsLines.toggle()
    }

    @objc func toggleShowWhitespace(_ sender: Any?) {
        editor.showsWhitespace.toggle()
    }

    @objc func toggleShowLineEndings(_ sender: Any?) {
        editor.showsLineEndings.toggle()
    }

    @objc func zoomInText(_ sender: Any?) { editor.zoomIn() }
    @objc func zoomOutText(_ sender: Any?) { editor.zoomOut() }
    @objc func resetTextZoom(_ sender: Any?) { editor.resetZoom() }

    // MARK: Find commands

    @objc func showFind(_ sender: Any?) {
        presentFindBar(mode: .find)
    }

    @objc func showFindAndReplace(_ sender: Any?) {
        presentFindBar(mode: .replace)
    }

    @objc func findNextMatch(_ sender: Any?) {
        performFind(forward: true)
    }

    @objc func findPreviousMatch(_ sender: Any?) {
        performFind(forward: false)
    }

    /// ⌘E: search for the selection, shared with other apps via the find pasteboard.
    @objc func useSelectionForFind(_ sender: Any?) {
        let selection = editor.selectedText
        guard !selection.isEmpty else { NSSound.beep(); return }
        var options = findBar.options
        options.query = selection
        findBar.options = options
        FindPasteboard.string = selection
        searchAnchor = editor.selectionRange.lowerBound
        refreshMatches()
    }

    /// Search ▸ Replace: replaces the selected match and moves to the next one.
    @objc func replaceMatch(_ sender: Any?) {
        guard !findBar.isHidden, findBar.mode == .replace, !findBar.options.query.isEmpty else {
            presentFindBar(mode: .replace)
            return
        }
        findBarReplace(findBar)
    }

    @objc func replaceAllMatches(_ sender: Any?) {
        guard !findBar.isHidden, findBar.mode == .replace, !findBar.options.query.isEmpty else {
            presentFindBar(mode: .replace)
            return
        }
        findBarReplaceAll(findBar)
    }

    /// Search ▸ Go to Line…: accepts "line" or "line:column".
    @objc func goToLine(_ sender: Any?) {
        guard let window = view.window else { return }
        let caret = editor.caretInfo
        let alert = NSAlert()
        alert.messageText = String(localized: "Go to Line")
        alert.informativeText = String(localized: "Enter a line number between 1 and \(caret.lineCount.formatted()), optionally followed by :column.")
        alert.addButton(withTitle: String(localized: "Go"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(string: "\(caret.line)")
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let parts = field.stringValue.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard let line = parts.first else { NSSound.beep(); return }
            self.editor.goTo(line: line, column: parts.count > 1 ? parts[1] : 1)
            window.makeFirstResponder(self.editor.content())
        }
    }

    @objc func hideFindBar(_ sender: Any?) {
        guard !findBar.isHidden else { return }
        setFindBarVisible(false)
        editor.clearHighlights()
        matches = nil
        view.window?.makeFirstResponder(editor.content())
    }

    override func cancelOperation(_ sender: Any?) {
        hideFindBar(sender)
    }

    private func presentFindBar(mode: FindBarView.Mode) {
        let selection = editor.selectedText
        var options = findBar.options
        if !selection.isEmpty, !selection.contains(where: \.isNewline) {
            options.query = selection
        } else if findBar.isHidden, let shared = FindPasteboard.string {
            options.query = shared
        }
        findBar.options = options
        findBar.mode = mode
        searchAnchor = editor.selectionRange.lowerBound
        if findBar.isHidden {
            setFindBarVisible(true)
        }
        view.window?.makeFirstResponder(mode == .replace && !options.query.isEmpty ? findBar.replaceField : findBar.searchField)
        refreshMatches()
    }

    private func setFindBarVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            findBar.isHidden = !visible
            view.layoutSubtreeIfNeeded()
        }
    }

    private func performFind(forward: Bool) {
        if findBar.isHidden {
            if findBar.options.query.isEmpty, let shared = FindPasteboard.string {
                var options = findBar.options
                options.query = shared
                findBar.options = options
            }
            guard !findBar.options.query.isEmpty else {
                presentFindBar(mode: .find)
                return
            }
        }
        let options = findBar.options
        FindPasteboard.string = options.query
        do {
            if try editor.find(options, forward: forward) == nil {
                findBar.show(.notFound)
                NSSound.beep()
            }
            searchAnchor = editor.selectionRange.lowerBound
            updateMatchCounter()
        } catch {
            findBar.show(.invalidPattern)
        }
    }

    // MARK: FindBarDelegate

    func findBarQueryDidChange(_ findBar: FindBarView) {
        // Incremental search: restart from where the search began.
        editor.send(SCI_SETSEL, searchAnchor, searchAnchor)
        do {
            try editor.find(findBar.options)
        } catch {
            findBar.show(.invalidPattern)
        }
        refreshMatches()
    }

    func findBar(_ findBar: FindBarView, findForward forward: Bool) {
        performFind(forward: forward)
    }

    func findBarReplace(_ findBar: FindBarView) {
        do {
            try editor.replaceSelection(findBar.options, with: findBar.replacement)
            searchAnchor = editor.selectionRange.lowerBound
            refreshMatches()
        } catch {
            findBar.show(.invalidPattern)
        }
    }

    func findBarReplaceAll(_ findBar: FindBarView) {
        do {
            let count = try editor.replaceAll(findBar.options, with: findBar.replacement)
            refreshMatches()
            findBar.show(.replaced(count))
            if count == 0 { NSSound.beep() }
        } catch {
            findBar.show(.invalidPattern)
        }
    }

    func findBarDismiss(_ findBar: FindBarView) {
        hideFindBar(nil)
    }

    // MARK: Match highlighting

    private func scheduleMatchRefresh() {
        guard !findBar.isHidden else { return }
        refreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refreshMatches() }
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func refreshMatches() {
        let options = findBar.options
        guard !options.query.isEmpty else {
            matches = nil
            editor.clearHighlights()
            findBar.show(.none)
            return
        }
        do {
            let found = try editor.allMatches(options)
            matches = found
            editor.highlight(found.ranges)
            updateMatchCounter()
        } catch {
            matches = nil
            editor.clearHighlights()
            findBar.show(.invalidPattern)
        }
    }

    private func updateMatchCounter() {
        guard !findBar.isHidden, let matches else { return }
        guard !matches.ranges.isEmpty else {
            findBar.show(.notFound)
            return
        }
        let selection = editor.selectionRange
        // Binary search for the match that is currently selected.
        var low = 0, high = matches.ranges.count - 1
        var current: Int?
        while low <= high {
            let mid = (low + high) / 2
            let range = matches.ranges[mid]
            if range == selection {
                current = mid + 1
                break
            } else if range.lowerBound < selection.lowerBound
                        || (range.lowerBound == selection.lowerBound && range.upperBound < selection.upperBound) {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        findBar.show(.matches(current: current, total: matches.ranges.count, truncated: matches.truncated))
    }

    // MARK: Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectLanguage(_:)):
            menuItem.state = (menuItem.representedObject as? String) == editor.language.id ? .on : .off
        case #selector(selectLineEnding(_:)):
            menuItem.state = (menuItem.representedObject as? String) == document?.format.lineEnding.rawValue ? .on : .off
        case #selector(toggleWordWrap(_:)):
            menuItem.state = editor.wrapsLines ? .on : .off
        case #selector(toggleShowWhitespace(_:)):
            menuItem.state = editor.showsWhitespace ? .on : .off
        case #selector(toggleShowLineEndings(_:)):
            menuItem.state = editor.showsLineEndings ? .on : .off
        case #selector(useSelectionForFind(_:)):
            return !editor.selectedText.isEmpty
        case #selector(hideFindBar(_:)):
            return !findBar.isHidden
        default:
            break
        }
        return true
    }
}

/// The system-wide find pasteboard, shared with other apps (⌘E in Safari, Xcode…).
enum FindPasteboard {
    @MainActor static var string: String? {
        get { NSPasteboard(name: .find).string(forType: .string).flatMap { $0.isEmpty ? nil : $0 } }
        set {
            let pasteboard = NSPasteboard(name: .find)
            pasteboard.clearContents()
            if let newValue { pasteboard.setString(newValue, forType: .string) }
        }
    }
}
