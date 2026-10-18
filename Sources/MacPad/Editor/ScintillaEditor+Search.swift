import AppKit
import Scintilla

struct SearchOptions: Equatable, Sendable {
    var query = ""
    var matchCase = false
    var wholeWord = false
    /// ECMAScript regular expressions (std::regex), searched per document.
    var regex = false

    var scintillaFlags: Int {
        var flags = 0
        if matchCase { flags |= Int(SCFIND_MATCHCASE) }
        if wholeWord { flags |= Int(SCFIND_WHOLEWORD) }
        if regex { flags |= Int(SCFIND_REGEXP) | Int(SCFIND_CXX11REGEX) }
        return flags
    }
}

enum SearchError: Error {
    case invalidPattern
}

/// Find and replace on top of Scintilla's target-based search API.
extension ScintillaEditor {
    struct MatchList {
        var ranges: [Range<Int>]
        /// True when counting stopped at the limit.
        var truncated: Bool
    }

    private static let findIndicator = Int(INDICATOR_CONTAINER)

    // MARK: Finding

    /// Selects the next (or previous) match, wrapping around the document.
    /// Returns nil when there is no match, and whether the search wrapped.
    @discardableResult
    func find(_ options: SearchOptions, forward: Bool = true) throws -> (range: Range<Int>, wrapped: Bool)? {
        guard !options.query.isEmpty else { return nil }
        let length = send(SCI_GETLENGTH)
        let match: Range<Int>?
        var wrapped = false
        if forward {
            let start = send(SCI_GETSELECTIONEND)
            if let found = try searchForward(options, from: start, to: length, skippingEmptyAt: start) {
                match = found
            } else {
                wrapped = true
                match = try searchForward(options, from: 0, to: length, skippingEmptyAt: nil)
            }
        } else {
            let start = send(SCI_GETSELECTIONSTART)
            if let found = try search(options, from: start, to: 0), found.lowerBound < start || !found.isEmpty {
                match = found
            } else {
                wrapped = true
                match = try search(options, from: length, to: 0)
            }
        }
        guard let match else { return nil }
        select(match)
        return (match, wrapped)
    }

    /// Every match in the document, up to `limit`.
    func allMatches(_ options: SearchOptions, limit: Int = 10_000) throws -> MatchList {
        guard !options.query.isEmpty else { return MatchList(ranges: [], truncated: false) }
        let length = send(SCI_GETLENGTH)
        var ranges: [Range<Int>] = []
        var position = 0
        while position <= length, let match = try search(options, from: position, to: length) {
            if ranges.count == limit {
                return MatchList(ranges: ranges, truncated: true)
            }
            ranges.append(match)
            position = match.isEmpty ? send(SCI_POSITIONAFTER, match.upperBound) : match.upperBound
            if match.isEmpty && position == match.upperBound { break }  // end of document
        }
        return MatchList(ranges: ranges, truncated: false)
    }

    // MARK: Replacing

    /// Replaces the selection if it is a match, then selects the next match.
    /// Returns true when a replacement happened.
    @discardableResult
    func replaceSelection(_ options: SearchOptions, with replacement: String) throws -> Bool {
        let selection = send(SCI_GETSELECTIONSTART)..<send(SCI_GETSELECTIONEND)
        guard let match = try search(options, from: selection.lowerBound, to: selection.upperBound),
              match == selection
        else {
            try find(options)
            return false
        }
        let end = replaceTarget(with: replacement, regex: options.regex)
        send(SCI_SETSEL, end, end)
        try find(options)
        return true
    }

    /// Replaces every match as a single undo step. Returns the replacement count.
    func replaceAll(_ options: SearchOptions, with replacement: String) throws -> Int {
        guard !options.query.isEmpty else { return 0 }
        var count = 0
        var position = 0
        send(SCI_BEGINUNDOACTION)
        defer { send(SCI_ENDUNDOACTION) }
        while let match = try search(options, from: position, to: send(SCI_GETLENGTH)) {
            let end = replaceTarget(with: replacement, regex: options.regex)
            count += 1
            // Step past empty matches (e.g. `^`) so the loop always advances.
            position = match.isEmpty ? send(SCI_POSITIONAFTER, end) : end
            if match.isEmpty && position == end { break }
        }
        return count
    }

    // MARK: Highlighting

    func configureFindIndicator(color: NSColor) {
        let indicator = Self.findIndicator
        send(SCI_INDICSETSTYLE, indicator, Int(INDIC_ROUNDBOX))
        send(SCI_INDICSETFORE, indicator, rgba(color) & 0xFF_FFFF)
        send(SCI_INDICSETALPHA, indicator, 90)
        send(SCI_INDICSETOUTLINEALPHA, indicator, 180)
        send(SCI_INDICSETUNDER, indicator, 1)
    }

    func highlight(_ ranges: [Range<Int>]) {
        clearHighlights()
        for range in ranges where !range.isEmpty {
            send(SCI_INDICATORFILLRANGE, range.lowerBound, range.count)
        }
    }

    func clearHighlights() {
        send(SCI_SETINDICATORCURRENT, Self.findIndicator)
        send(SCI_INDICATORCLEARRANGE, 0, send(SCI_GETLENGTH))
    }

    var selectedText: String {
        let start = send(SCI_GETSELECTIONSTART)
        let end = send(SCI_GETSELECTIONEND)
        guard end > start, let pointer = UnsafeRawPointer(bitPattern: send(SCI_GETRANGEPOINTER, start, end - start)) else {
            return ""
        }
        return String(decoding: UnsafeRawBufferPointer(start: pointer, count: end - start), as: UTF8.self)
    }

    var selectionRange: Range<Int> {
        send(SCI_GETSELECTIONSTART)..<send(SCI_GETSELECTIONEND)
    }

    // MARK: Primitives

    /// Searches between two positions; `end < start` searches backwards.
    private func search(_ options: SearchOptions, from start: Int, to end: Int) throws -> Range<Int>? {
        send(SCI_SETSEARCHFLAGS, options.scintillaFlags)
        send(SCI_SETTARGETRANGE, start, end)
        send(SCI_SETSTATUS, Int(SC_STATUS_OK))
        let query = Array(options.query.utf8)
        let position = query.withUnsafeBufferPointer { buffer in
            send(SCI_SEARCHINTARGET, buffer.count, Int(bitPattern: buffer.baseAddress))
        }
        guard position >= 0 else {
            // An invalid regex reports "not found" and flags the status.
            if send(SCI_GETSTATUS) == Int(SC_STATUS_WARN_REGEX) {
                send(SCI_SETSTATUS, Int(SC_STATUS_OK))
                throw SearchError.invalidPattern
            }
            return nil
        }
        return position..<send(SCI_GETTARGETEND)
    }

    /// Forward search that ignores an empty match sitting exactly at the caret,
    /// so patterns like `^` or `\b` keep moving.
    private func searchForward(_ options: SearchOptions, from start: Int, to end: Int, skippingEmptyAt caret: Int?) throws -> Range<Int>? {
        guard let match = try search(options, from: start, to: end) else { return nil }
        if match.isEmpty, match.lowerBound == caret {
            let next = send(SCI_POSITIONAFTER, start)
            return next > start ? try search(options, from: next, to: end) : nil
        }
        return match
    }

    /// Replaces the current target, expanding `\1`…`\9` (and `$1`…`$9`) in regex mode.
    /// Returns the end position of the inserted text.
    private func replaceTarget(with replacement: String, regex: Bool) -> Int {
        let text = regex ? replacement.replacingOccurrences(of: #"(?<!\\)\$(\d)"#, with: #"\\$1"#, options: .regularExpression) : replacement
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            let pointer = Int(bitPattern: buffer.baseAddress)
            send(regex ? SCI_REPLACETARGETRE : SCI_REPLACETARGET, buffer.count, pointer)
        }
        return send(SCI_GETTARGETEND)
    }

    private func select(_ range: Range<Int>) {
        let line = send(SCI_LINEFROMPOSITION, range.lowerBound)
        send(SCI_ENSUREVISIBLEENFORCEPOLICY, line)
        send(SCI_SETSEL, range.lowerBound, range.upperBound)
        send(SCI_SCROLLRANGE, range.upperBound, range.lowerBound)
    }
}
