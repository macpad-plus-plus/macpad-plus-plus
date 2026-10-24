import AppKit
import Scintilla

/// Notepad++'s Edit menu operations: Indent, Convert Case, Line Operations,
/// Comment/Uncomment and Blank Operations. Each one is a single undo step and,
/// like in Notepad++, acts on the selected lines or, with no selection, on the
/// whole document.
extension ScintillaEditor {
    // MARK: Text access

    /// UTF-8 text between two positions.
    func text(from start: Int, to end: Int) -> String {
        guard end > start, let pointer = UnsafeRawPointer(bitPattern: send(SCI_GETRANGEPOINTER, start, end - start)) else {
            return ""
        }
        return String(decoding: UnsafeRawBufferPointer(start: pointer, count: end - start), as: UTF8.self)
    }

    /// Replaces the text between two positions; returns the end of the new text.
    @discardableResult
    func replace(from start: Int, to end: Int, with text: String) -> Int {
        send(SCI_SETTARGETRANGE, start, end)
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            _ = send(SCI_REPLACETARGET, buffer.count, Int(bitPattern: buffer.baseAddress))
        }
        return send(SCI_GETTARGETEND)
    }

    /// The document's line ending, used when lines are rejoined.
    var lineEndingString: String {
        switch Int32(send(SCI_GETEOLMODE)) {
        case SC_EOL_CRLF: "\r\n"
        case SC_EOL_CR: "\r"
        default: "\n"
        }
    }

    /// Wraps several changes into one undo step.
    func undoGroup(_ body: () throws -> Void) rethrows {
        send(SCI_BEGINUNDOACTION)
        defer { send(SCI_ENDUNDOACTION) }
        try body()
    }

    private var hasSelection: Bool {
        send(SCI_GETSELECTIONS) > 1 || send(SCI_GETSELECTIONSTART) != send(SCI_GETSELECTIONEND)
    }

    private var isRectangularSelection: Bool {
        let mode = Int32(send(SCI_GETSELECTIONMODE))
        return mode == SC_SEL_RECTANGLE || mode == SC_SEL_THIN
    }

    /// First and last line of the main selection; a selection ending at the
    /// start of a line does not include that line.
    private var selectedLines: ClosedRange<Int> {
        let start = send(SCI_GETSELECTIONSTART)
        let end = send(SCI_GETSELECTIONEND)
        let first = send(SCI_LINEFROMPOSITION, start)
        var last = send(SCI_LINEFROMPOSITION, end)
        if last > first, send(SCI_POSITIONFROMLINE, last) == end { last -= 1 }
        return first...last
    }

    // MARK: Line transforms

    /// Replaces the selected lines (or every line) with `transform(lines)`.
    ///
    /// A final line ending stays where it is: sorting a file that ends with a
    /// newline does not move an empty line to the top.
    @discardableResult
    func transformLines(minimumLines: Int = 1, _ transform: ([String]) throws -> [String]) rethrows -> Bool {
        let wholeDocument = !hasSelection
        let lines: ClosedRange<Int> = wholeDocument ? 0...max(0, send(SCI_GETLINECOUNT) - 1) : selectedLines
        let start = send(SCI_POSITIONFROMLINE, lines.lowerBound)
        let end = send(SCI_GETLINEENDPOSITION, lines.upperBound)
        var items = text(from: start, to: end).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        var trailingEmpty = false
        if wholeDocument, items.count > 1, items.last == "" {
            items.removeLast()
            trailingEmpty = true
        }
        guard items.count >= minimumLines else { return false }
        let eol = lineEndingString
        var joined = try transform(items).joined(separator: eol)
        if trailingEmpty { joined += eol }
        guard joined != text(from: start, to: end) else { return false }
        let newEnd = replace(from: start, to: end, with: joined)
        if wholeDocument {
            send(SCI_GOTOPOS, min(send(SCI_GETCURRENTPOS), send(SCI_GETLENGTH)))
        } else {
            send(SCI_SETSEL, start, trailingEmpty ? newEnd - eol.utf8.count : newEnd)
        }
        return true
    }

    // MARK: Indent

    /// Several lines or carets indent like Tab; a single line by one tab width,
    /// keeping the caret where it was in the text.
    func indentLines(increase: Bool) {
        let start = send(SCI_GETSELECTIONSTART)
        let end = send(SCI_GETSELECTIONEND)
        let line = send(SCI_LINEFROMPOSITION, start)
        if send(SCI_GETSELECTIONS) > 1 || line != send(SCI_LINEFROMPOSITION, end) {
            send(increase ? SCI_TAB : SCI_BACKTAB)
            return
        }
        let indent = send(SCI_GETLINEINDENTATION, line)
        let width = send(SCI_GETINDENT) > 0 ? send(SCI_GETINDENT) : send(SCI_GETTABWIDTH)
        let target = max(0, increase ? indent + width : indent - width)
        guard target != indent else { return }
        let indentEnd = send(SCI_GETLINEINDENTPOSITION, line)
        let anchor = send(SCI_GETANCHOR), caret = send(SCI_GETCURRENTPOS)
        send(SCI_SETLINEINDENTATION, line, target)
        let delta = send(SCI_GETLINEINDENTPOSITION, line) - indentEnd
        let shift = { (position: Int) in position >= indentEnd ? position + delta : min(position, indentEnd + delta) }
        send(SCI_SETSEL, shift(anchor), shift(caret))
    }

    // MARK: Case

    /// Converts each selection; does nothing without one, as in Notepad++.
    func convertCase(to textCase: TextTransform.Case) {
        let count = send(SCI_GETSELECTIONS)
        var ranges = (0..<count).map { (start: send(SCI_GETSELECTIONNSTART, $0), end: send(SCI_GETSELECTIONNEND, $0)) }
            .filter { $0.end > $0.start }
        guard !ranges.isEmpty else { return }
        let main = send(SCI_GETMAINSELECTION)
        let mainStart = send(SCI_GETSELECTIONNSTART, main)
        ranges.sort { $0.start < $1.start }
        undoGroup {
            var delta = 0
            for index in ranges.indices {
                let start = ranges[index].start + delta
                let end = ranges[index].end + delta
                let converted = TextTransform.convert(text(from: start, to: end), to: textCase)
                let newEnd = replace(from: start, to: end, with: converted)
                delta += newEnd - end
                ranges[index] = (start, newEnd)
            }
        }
        // Reselect what was converted, keeping the main selection main.
        for (index, range) in ranges.enumerated() {
            if index == 0 {
                send(SCI_SETSELECTION, range.end, range.start)
            } else {
                send(SCI_ADDSELECTION, range.end, range.start)
            }
        }
        if let mainIndex = ranges.firstIndex(where: { $0.start >= mainStart }) {
            send(SCI_SETMAINSELECTION, mainIndex)
        }
    }

    // MARK: Line operations

    func duplicateLines() { send(SCI_LINEDUPLICATE) }

    func moveLines(up: Bool) {
        send(up ? SCI_MOVESELECTEDLINESUP : SCI_MOVESELECTEDLINESDOWN)
        send(SCI_SCROLLRANGE, send(SCI_GETSELECTIONEND), send(SCI_GETSELECTIONSTART))
    }

    /// Joins the selected lines, separated by a space.
    func joinLines() {
        let lines = selectedLines
        guard lines.count > 1 else { return }
        send(SCI_SETTARGETRANGE, send(SCI_POSITIONFROMLINE, lines.lowerBound), send(SCI_GETLINEENDPOSITION, lines.upperBound))
        send(SCI_LINESJOIN)
    }

    /// Wraps the selected lines at the window's width.
    func splitLines() {
        guard send(SCI_GETSELECTIONS) == 1 else { return }
        let lines = selectedLines
        send(SCI_SETTARGETRANGE, send(SCI_POSITIONFROMLINE, lines.lowerBound), send(SCI_GETLINEENDPOSITION, lines.upperBound))
        send(SCI_LINESSPLIT, 0)
    }

    func insertBlankLine(above: Bool) {
        let eol = lineEndingString
        let line = send(SCI_LINEFROMPOSITION, send(SCI_GETCURRENTPOS))
        if above {
            send(SCI_INSERTTEXT, send(SCI_POSITIONFROMLINE, line), string: eol)
            send(SCI_SETEMPTYSELECTION, send(SCI_POSITIONFROMLINE, line))
        } else {
            send(SCI_INSERTTEXT, send(SCI_GETLINEENDPOSITION, line), string: eol)
            send(SCI_SETEMPTYSELECTION, send(SCI_POSITIONFROMLINE, line + 1))
        }
    }

    func removeEmptyLines(includingBlank: Bool) {
        undoGroup {
            transformLines { TextTransform.removingEmptyLines($0, includingBlank: includingBlank) }
        }
    }

    func removeDuplicateLines(consecutiveOnly: Bool) {
        undoGroup {
            transformLines(minimumLines: 2) {
                consecutiveOnly ? TextTransform.removingConsecutiveDuplicates($0) : TextTransform.removingDuplicates($0)
            }
        }
    }

    /// Sorts the selected lines, or all of them. A selection inside one line is
    /// not sorted, and neither is a column selection.
    func sortLines(_ sort: TextTransform.Sort) throws {
        guard !isRectangularSelection || send(SCI_GETSELECTIONS) == 1 else { return }
        if hasSelection, selectedLines.count < 2 { return }
        try undoGroup {
            try transformLines(minimumLines: 2) { try TextTransform.sort($0, sort) }
        }
    }

    // MARK: Comments

    enum CommentMode { case toggle, comment, uncomment }

    /// Single-line comments on each selected line, Notepad++'s "Comment/Uncomment".
    /// Languages with only block delimiters (HTML, CSS…) get each line wrapped in them.
    @discardableResult
    func lineComment(_ mode: CommentMode) -> Bool {
        let symbols = language.comment
        let wrap = symbols.line.isEmpty
        if wrap {
            guard symbols.hasBlock else { return false }
            if mode == .uncomment { return blockUncomment() }
        }
        let prefix = (wrap ? symbols.start : symbols.line) + " "
        let suffix = wrap ? " " + symbols.end : ""
        let lines = selectedLines
        var anchor = PositionInLine(editor: self, position: send(SCI_GETANCHOR))
        var caret = PositionInLine(editor: self, position: send(SCI_GETCURRENTPOS))
        var uncommented = 0

        undoGroup {
            for line in lines {
                let indent = send(SCI_GETLINEINDENTPOSITION, line)
                let end = send(SCI_GETLINEENDPOSITION, line)
                // Empty lines are left alone.
                guard indent < end else { continue }
                let content = text(from: indent, to: end)
                if mode != .comment, let removed = commentRange(in: content, prefix: prefix, suffix: suffix) {
                    if removed.suffix > 0 { replace(from: end - removed.suffix, to: end, with: "") }
                    replace(from: indent, to: indent + removed.prefix, with: "")
                    uncommented += 1
                    continue
                }
                if mode != .uncomment {
                    if !suffix.isEmpty { send(SCI_INSERTTEXT, end, string: suffix) }
                    send(SCI_INSERTTEXT, indent, string: prefix)
                }
            }
        }
        anchor.restore()
        caret.restore()
        send(SCI_SETSEL, anchor.position, caret.position)
        if mode == .uncomment, uncommented == 0, symbols.hasBlock {
            return blockUncomment()
        }
        return true
    }

    /// The bytes to remove from the start and end of a commented line, or nil
    /// if it is not commented. The symbol matches in any case ("REM", "rem"),
    /// and the space after it is optional.
    private func commentRange(in content: String, prefix: String, suffix: String) -> (prefix: Int, suffix: Int)? {
        let opener = prefix.dropLast()
        guard content.lowercased().hasPrefix(opener.lowercased()) else { return nil }
        var start = opener.utf8.count
        if content.dropFirst(opener.count).first == " " { start += 1 }
        guard !suffix.isEmpty else { return (start, 0) }
        let closer = suffix.dropFirst()
        guard content.utf8.count >= start + closer.utf8.count, content.lowercased().hasSuffix(closer.lowercased()) else { return nil }
        var end = closer.utf8.count
        if content.dropLast(closer.count).last == " ", content.utf8.count - end - 1 >= start { end += 1 }
        return (start, end)
    }

    /// Wraps the selection (or the current line) in the block delimiters,
    /// Notepad++'s "Block Comment". Languages without them get line comments.
    func blockComment() {
        let symbols = language.comment
        guard symbols.hasBlock else {
            if !symbols.line.isEmpty { lineComment(.comment) }
            return
        }
        var start = send(SCI_GETSELECTIONSTART)
        var end = send(SCI_GETSELECTIONEND)
        let caretAtStart = send(SCI_GETCURRENTPOS) < end
        if start == end {
            let line = send(SCI_LINEFROMPOSITION, start)
            start = send(SCI_GETLINEINDENTPOSITION, line)
            end = send(SCI_GETLINEENDPOSITION, line)
        }
        let opener = symbols.start + " "
        undoGroup {
            send(SCI_INSERTTEXT, end, string: " " + symbols.end)
            send(SCI_INSERTTEXT, start, string: opener)
        }
        start += opener.utf8.count
        end += opener.utf8.count
        send(SCI_SETSEL, caretAtStart ? end : start, caretAtStart ? start : end)
    }

    /// Removes the block comment around the caret, then any inside the selection.
    @discardableResult
    func blockUncomment() -> Bool {
        let symbols = language.comment
        guard symbols.hasBlock else {
            return symbols.line.isEmpty ? false : lineComment(.uncomment)
        }
        var selectionStart = send(SCI_GETSELECTIONSTART)
        var selectionEnd = send(SCI_GETSELECTIONEND)
        var removedAny = false
        undoGroup {
            // The comment enclosing the selection start, then those starting inside it.
            var searchFrom = selectionStart
            var first = true
            while let comment = findBlockComment(around: searchFrom, first: first, limit: selectionEnd, symbols: symbols) {
                first = false
                var openEnd = comment.lowerBound + symbols.start.utf8.count
                if send(SCI_GETCHARAT, openEnd) == 0x20 { openEnd += 1 }
                var closeStart = comment.upperBound - symbols.end.utf8.count
                if closeStart > openEnd, send(SCI_GETCHARAT, closeStart - 1) == 0x20 { closeStart -= 1 }
                replace(from: closeStart, to: comment.upperBound, with: "")
                replace(from: comment.lowerBound, to: openEnd, with: "")
                let openLength = openEnd - comment.lowerBound
                let closeLength = comment.upperBound - closeStart
                func adjust(_ position: Int) -> Int {
                    if position >= comment.upperBound { return position - openLength - closeLength }
                    if position > closeStart { return closeStart - openLength }
                    if position >= openEnd { return position - openLength }
                    return min(position, comment.lowerBound)
                }
                selectionStart = adjust(selectionStart)
                selectionEnd = adjust(selectionEnd)
                searchFrom = comment.lowerBound
                removedAny = true
                if selectionEnd <= selectionStart { break }
            }
        }
        if removedAny { send(SCI_SETSEL, selectionStart, selectionEnd) }
        return removedAny
    }

    /// First pass: the comment that encloses `position`. Later passes: the next
    /// comment that starts before `limit`.
    private func findBlockComment(around position: Int, first: Bool, limit: Int, symbols: Language.CommentSymbols) -> Range<Int>? {
        let length = send(SCI_GETLENGTH)
        send(SCI_SETSEARCHFLAGS, 0)
        func find(_ needle: String, from start: Int, to end: Int) -> Int? {
            send(SCI_SETTARGETRANGE, start, end)
            let bytes = Array(needle.utf8)
            let found = bytes.withUnsafeBufferPointer { send(SCI_SEARCHINTARGET, $0.count, Int(bitPattern: $0.baseAddress)) }
            return found >= 0 ? found : nil
        }
        let open: Int?
        if !first, position >= limit { return nil }
        if first {
            // Backwards from just past the caret, so a caret inside "/*" counts.
            open = find(symbols.start, from: min(length, position + symbols.start.utf8.count), to: 0)
        } else {
            open = find(symbols.start, from: position, to: limit)
        }
        guard let open,
              let close = find(symbols.end, from: open + symbols.start.utf8.count, to: length)
        else { return nil }
        let comment = open..<(close + symbols.end.utf8.count)
        // The comment found backwards must reach the caret.
        if first, comment.upperBound < position { return nil }
        return comment
    }

    // MARK: Blank operations

    func trimLines(_ trim: TextTransform.Trim) {
        guard !isRectangularSelection else { return }
        undoGroup {
            transformLines { $0.map { TextTransform.trim($0, trim) } }
        }
    }

    /// Joins the selected lines (or the whole document) into one, with spaces.
    func lineEndingsToSpaces() {
        guard !isRectangularSelection else { return }
        let wholeDocument = !hasSelection
        undoGroup {
            if wholeDocument {
                send(SCI_TARGETWHOLEDOCUMENT)
            } else {
                send(SCI_TARGETFROMSELECTION)
            }
            send(SCI_LINESJOIN)
        }
    }

    func trimAndJoinLines() {
        guard !isRectangularSelection else { return }
        undoGroup {
            transformLines { $0.map { TextTransform.trim($0, .both) } }
            lineEndingsToSpaces()
        }
    }

    func convertTabsToSpaces() {
        guard !isRectangularSelection else { return }
        let width = send(SCI_GETTABWIDTH)
        undoGroup {
            transformLines { $0.map { TextTransform.tabsToSpaces($0, tabWidth: width) } }
        }
    }

    func convertSpacesToTabs(leadingOnly: Bool) {
        guard !isRectangularSelection else { return }
        let width = send(SCI_GETTABWIDTH)
        undoGroup {
            transformLines { $0.map { TextTransform.spacesToTabs($0, tabWidth: width, leadingOnly: leadingOnly) } }
        }
    }
}

/// A position kept as an offset from its line's end (or start, when it sits in
/// the indentation), so it survives text inserted at the indentation.
private struct PositionInLine {
    private let editor: ScintillaEditor
    private let line: Int
    private let fromEnd: Int?
    private let fromStart: Int
    private(set) var position: Int

    init(editor: ScintillaEditor, position: Int) {
        self.editor = editor
        self.position = position
        line = editor.send(SCI_LINEFROMPOSITION, position)
        let indent = editor.send(SCI_GETLINEINDENTPOSITION, line)
        fromStart = position - editor.send(SCI_POSITIONFROMLINE, line)
        fromEnd = position > indent ? editor.send(SCI_GETLINEENDPOSITION, line) - position : nil
    }

    mutating func restore() {
        let start = editor.send(SCI_POSITIONFROMLINE, line)
        let end = editor.send(SCI_GETLINEENDPOSITION, line)
        let indent = editor.send(SCI_GETLINEINDENTPOSITION, line)
        if let fromEnd {
            position = max(indent, end - fromEnd)
        } else {
            position = min(start + fromStart, indent)
        }
    }
}
