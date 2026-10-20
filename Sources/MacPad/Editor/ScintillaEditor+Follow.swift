import AppKit
import Scintilla

/// What following a file (tail -f) needs from the editor: appending to a
/// read-only buffer, staying at the end, dropping old lines, and coloring
/// lines by log level.
extension ScintillaEditor {
    /// Indicators for the level colors, after the find highlight's.
    private static let levelIndicators: [LogLevel: Int] = [
        .error: Int(INDICATOR_CONTAINER) + 1,
        .warning: Int(INDICATOR_CONTAINER) + 2,
        .debug: Int(INDICATOR_CONTAINER) + 3,
        .trace: Int(INDICATOR_CONTAINER) + 3,
    ]

    var length: Int { send(SCI_GETLENGTH) }
    var lineCount: Int { send(SCI_GETLINECOUNT) }

    /// Appends UTF-8 bytes, even to a read-only buffer, keeping them out of
    /// the undo history and the document clean.
    func appendWithoutUndo(utf8 data: Data) {
        let wasReadOnly = isReadOnly
        isReadOnly = false
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            if let base = bytes.baseAddress {
                send(SCI_APPENDTEXT, bytes.count, Int(bitPattern: base))
            }
        }
        isReadOnly = wasReadOnly
        send(SCI_SETSAVEPOINT)
    }

    /// Whether the last line is on screen, so new lines should keep it there.
    var isScrolledToEnd: Bool {
        let lastVisible = send(SCI_GETFIRSTVISIBLELINE) + send(SCI_LINESONSCREEN)
        return lastVisible + 1 >= send(SCI_VISIBLEFROMDOCLINE, lineCount - 1)
    }

    func scrollToEnd() {
        send(SCI_GOTOPOS, length)
        send(SCI_SCROLLCARET)
    }

    /// Removes the oldest lines once there are well over `maxLines`.
    func dropOldLines(keeping maxLines: Int) {
        let lines = lineCount
        guard lines > maxLines + maxLines / 10 else { return }
        let cut = send(SCI_POSITIONFROMLINE, lines - maxLines)
        let wasReadOnly = isReadOnly
        isReadOnly = false
        send(SCI_DELETERANGE, 0, cut)
        isReadOnly = wasReadOnly
        send(SCI_SETSAVEPOINT)
    }

    /// Stops keeping undo history, which following would only grow.
    var collectsUndo: Bool {
        get { send(SCI_GETUNDOCOLLECTION) != 0 }
        set {
            send(SCI_SETUNDOCOLLECTION, newValue ? 1 : 0)
            if !newValue { send(SCI_EMPTYUNDOBUFFER) }
        }
    }

    /// Colors whole lines by log level, from the line holding `start` to the
    /// end: appended text may finish a line that was already there.
    func colorLogLevels(from start: Int) {
        configureLevelIndicators()
        let firstLine = send(SCI_LINEFROMPOSITION, start)
        let from = send(SCI_POSITIONFROMLINE, firstLine)
        let end = length
        guard end > from, let pointer = UnsafeRawPointer(bitPattern: send(SCI_GETRANGEPOINTER, from, end - from)) else { return }
        for indicator in Set(Self.levelIndicators.values) {
            send(SCI_SETINDICATORCURRENT, indicator)
            send(SCI_INDICATORCLEARRANGE, from, end - from)
        }
        let text = Data(bytes: pointer, count: end - from)
        for span in LogLevel.spans(in: text, base: from) {
            guard let indicator = Self.levelIndicators[span.level] else { continue }
            send(SCI_SETINDICATORCURRENT, indicator)
            send(SCI_INDICATORFILLRANGE, span.range.lowerBound, span.range.count)
        }
    }

    func clearLogLevels() {
        for indicator in Set(Self.levelIndicators.values) {
            send(SCI_SETINDICATORCURRENT, indicator)
            send(SCI_INDICATORCLEARRANGE, 0, length)
        }
    }

    /// Text colors that read on the current theme's background.
    func configureLevelIndicators() {
        let colors: [(Int, NSColor)] = [
            (Self.levelIndicators[.error]!, .systemRed),
            (Self.levelIndicators[.warning]!, .systemOrange),
            (Self.levelIndicators[.debug]!, .secondaryLabelColor),
        ]
        for (indicator, color) in colors {
            send(SCI_INDICSETSTYLE, indicator, Int(INDIC_TEXTFORE))
            send(SCI_INDICSETFORE, indicator, rgba(color) & 0xFF_FFFF)
        }
    }
}
