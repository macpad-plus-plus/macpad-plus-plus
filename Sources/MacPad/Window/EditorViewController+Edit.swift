import AppKit
import Scintilla

/// Edit menu commands from Notepad++ (Indent, Convert Case, Line Operations,
/// Comment/Uncomment, Blank Operations), reaching the editor through the
/// responder chain. See `ScintillaEditor+Edit` for what each one does.
extension EditorViewController {
    // MARK: Indent

    @objc func increaseIndent(_ sender: Any?) { edit { $0.indentLines(increase: true) } }
    @objc func decreaseIndent(_ sender: Any?) { edit { $0.indentLines(increase: false) } }

    // MARK: Case

    /// The menu item's represented object is a `TextTransform.Case` raw value.
    @objc func convertCase(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let textCase = TextTransform.Case(rawValue: raw) else { return }
        edit { $0.convertCase(to: textCase) }
    }

    // MARK: Line operations

    @objc func duplicateLines(_ sender: Any?) { edit { $0.duplicateLines() } }
    @objc func removeDuplicateLines(_ sender: Any?) { edit { $0.removeDuplicateLines(consecutiveOnly: false) } }
    @objc func removeConsecutiveDuplicateLines(_ sender: Any?) { edit { $0.removeDuplicateLines(consecutiveOnly: true) } }
    @objc func splitLines(_ sender: Any?) { edit { $0.splitLines() } }
    @objc func joinLines(_ sender: Any?) { edit { $0.joinLines() } }
    @objc func moveLinesUp(_ sender: Any?) { edit { $0.moveLines(up: true) } }
    @objc func moveLinesDown(_ sender: Any?) { edit { $0.moveLines(up: false) } }
    @objc func removeEmptyLines(_ sender: Any?) { edit { $0.removeEmptyLines(includingBlank: false) } }
    @objc func removeBlankLines(_ sender: Any?) { edit { $0.removeEmptyLines(includingBlank: true) } }
    @objc func insertBlankLineAbove(_ sender: Any?) { edit { $0.insertBlankLine(above: true) } }
    @objc func insertBlankLineBelow(_ sender: Any?) { edit { $0.insertBlankLine(above: false) } }

    /// The menu item's represented object is a `TextTransform.Sort` raw value.
    @objc func sortLines(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let sort = TextTransform.Sort(rawValue: raw) else { return }
        edit { editor in
            do {
                try editor.sortLines(sort)
            } catch let error as TextTransform.SortError {
                let line = editor.send(SCI_LINEFROMPOSITION, editor.send(SCI_GETSELECTIONSTART))
                let first = editor.send(SCI_GETSELECTIONSTART) == editor.send(SCI_GETSELECTIONEND) ? 0 : line
                showSortError(line: first + error.lineIndex + 1)
            } catch {}
        }
    }

    private func showSortError(line: Int) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Can’t Sort as Numbers")
        alert.informativeText = String(localized: "Line \(line) doesn’t start with a number. Sort as text instead, or fix that line.")
        alert.beginSheetModal(for: window)
    }

    // MARK: Comments

    @objc func toggleLineComment(_ sender: Any?) { edit { $0.lineComment(.toggle) } }
    @objc func addLineComment(_ sender: Any?) { edit { $0.lineComment(.comment) } }
    @objc func removeLineComment(_ sender: Any?) { edit { $0.lineComment(.uncomment) } }
    @objc func addBlockComment(_ sender: Any?) { edit { $0.blockComment() } }
    @objc func removeBlockComment(_ sender: Any?) { edit { $0.blockUncomment() } }

    // MARK: Blank operations

    @objc func trimTrailingSpace(_ sender: Any?) { edit { $0.trimLines(.trailing) } }
    @objc func trimLeadingSpace(_ sender: Any?) { edit { $0.trimLines(.leading) } }
    @objc func trimLeadingAndTrailingSpace(_ sender: Any?) { edit { $0.trimLines(.both) } }
    @objc func lineEndingsToSpaces(_ sender: Any?) { edit { $0.lineEndingsToSpaces() } }
    @objc func trimAndJoinLines(_ sender: Any?) { edit { $0.trimAndJoinLines() } }
    @objc func tabsToSpaces(_ sender: Any?) { edit { $0.convertTabsToSpaces() } }
    @objc func spacesToTabs(_ sender: Any?) { edit { $0.convertSpacesToTabs(leadingOnly: false) } }
    @objc func leadingSpacesToTabs(_ sender: Any?) { edit { $0.convertSpacesToTabs(leadingOnly: true) } }

    // MARK: Helpers

    /// Runs an edit unless the document is read-only, which beeps instead.
    private func edit(_ body: (ScintillaEditor) -> Void) {
        guard !editor.isReadOnly else {
            NSSound.beep()
            return
        }
        body(editor)
    }

    /// Commands from this file that change the text, so read-only documents disable them.
    static let editingActions: Set<Selector> = [
        #selector(increaseIndent(_:)), #selector(decreaseIndent(_:)), #selector(convertCase(_:)),
        #selector(duplicateLines(_:)), #selector(removeDuplicateLines(_:)), #selector(removeConsecutiveDuplicateLines(_:)),
        #selector(splitLines(_:)), #selector(joinLines(_:)), #selector(moveLinesUp(_:)), #selector(moveLinesDown(_:)),
        #selector(removeEmptyLines(_:)), #selector(removeBlankLines(_:)),
        #selector(insertBlankLineAbove(_:)), #selector(insertBlankLineBelow(_:)), #selector(sortLines(_:)),
        #selector(toggleLineComment(_:)), #selector(addLineComment(_:)), #selector(removeLineComment(_:)),
        #selector(addBlockComment(_:)), #selector(removeBlockComment(_:)),
        #selector(trimTrailingSpace(_:)), #selector(trimLeadingSpace(_:)), #selector(trimLeadingAndTrailingSpace(_:)),
        #selector(lineEndingsToSpaces(_:)), #selector(trimAndJoinLines(_:)),
        #selector(tabsToSpaces(_:)), #selector(spacesToTabs(_:)), #selector(leadingSpacesToTabs(_:)),
    ]

    static let commentActions: Set<Selector> = [
        #selector(toggleLineComment(_:)), #selector(addLineComment(_:)), #selector(removeLineComment(_:)),
        #selector(addBlockComment(_:)), #selector(removeBlockComment(_:)),
    ]

    /// Read-only documents disable edits; languages without comments disable those.
    func validateEditAction(_ menuItem: NSMenuItem) -> Bool? {
        guard let action = menuItem.action, Self.editingActions.contains(action) else { return nil }
        if editor.isReadOnly { return false }
        // Case conversion only acts on selected text.
        if action == #selector(convertCase(_:)) { return editor.send(SCI_GETSELECTIONEMPTY) == 0 }
        if Self.commentActions.contains(action) {
            let symbols = editor.language.comment
            return !symbols.line.isEmpty || symbols.hasBlock
        }
        return true
    }
}
