import Foundation

/// Side-by-side comparison of two texts, ported from OxyPad's `compare.rs`.
///
/// The lines of both texts are paired into rows a viewer can draw as two
/// columns: equal lines share a row, a changed line sits next to the line it
/// replaced, and a line present on one side only faces an empty filler cell.
struct TextComparison: Equatable {
    enum Kind: Equatable {
        case equal
        /// Both sides have a line, and they differ.
        case changed
        /// Only the left side has a line.
        case removed
        /// Only the right side has a line.
        case added
    }

    /// One side of a row.
    struct Cell: Equatable {
        /// 0-based line index in that side's text.
        var line: Int
        /// UTF-8 byte ranges within the line that differ from the other side.
        var emphasis: [Range<Int>] = []
    }

    struct Row: Equatable {
        var kind: Kind
        var left: Cell?
        var right: Cell?
    }

    private(set) var rows: [Row] = []
    /// Index of the first row of each block of differences, in order.
    private(set) var changes: [Int] = []
    private(set) var changed = 0
    private(set) var removed = 0
    private(set) var added = 0

    var isIdentical: Bool { changes.isEmpty }

    /// Paired lines more different than this get no word emphasis: when nearly
    /// every word changed, marking them all is noise.
    private static let minimumSimilarityForEmphasis = 0.3
    /// Lines longer than this (in bytes) are not compared word by word.
    private static let maximumEmphasisLineLength = 2_000

    /// The lines of `text`: split on line endings, without them, and without a
    /// phantom empty line after a final one.
    static func lines(_ text: String) -> [String] {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    init(left: String, right: String) {
        self.init(leftLines: Self.lines(left), rightLines: Self.lines(right))
    }

    init(leftLines: [String], rightLines: [String]) {
        // Shared lines at both ends never need diffing.
        let prefix = zip(leftLines, rightLines).prefix { $0 == $1 }.count
        let suffix = zip(leftLines.dropFirst(prefix).reversed(), rightLines.dropFirst(prefix).reversed()).prefix { $0 == $1 }.count
        let leftMiddle = Array(leftLines[prefix..<(leftLines.count - suffix)])
        let rightMiddle = Array(rightLines[prefix..<(rightLines.count - suffix)])

        var removedLines = Set<Int>(), insertedLines = Set<Int>()
        for change in rightMiddle.difference(from: leftMiddle) {
            switch change {
            case .remove(let offset, _, _): removedLines.insert(prefix + offset)
            case .insert(let offset, _, _): insertedLines.insert(prefix + offset)
            }
        }

        var i = 0, j = 0
        while i < leftLines.count || j < rightLines.count {
            let leftKept = i < leftLines.count && !removedLines.contains(i)
            let rightKept = j < rightLines.count && !insertedLines.contains(j)
            if leftKept, rightKept {
                rows.append(Row(kind: .equal, left: Cell(line: i), right: Cell(line: j)))
                i += 1
                j += 1
                continue
            }
            // A block of differences: lines removed on the left, inserted on the right.
            let leftStart = i, rightStart = j
            while i < leftLines.count, removedLines.contains(i) { i += 1 }
            while j < rightLines.count, insertedLines.contains(j) { j += 1 }
            if i == leftStart, j == rightStart {
                // Only possible if one side ran out; take what is left as a difference.
                if i < leftLines.count { i += 1 } else { j += 1 }
            }
            changes.append(rows.count)
            let paired = min(i - leftStart, j - rightStart)
            changed += paired
            for offset in 0..<paired {
                let (l, r) = (leftStart + offset, rightStart + offset)
                let emphasis = Self.wordEmphasis(leftLines[l], rightLines[r])
                rows.append(Row(kind: .changed, left: Cell(line: l, emphasis: emphasis.left),
                                right: Cell(line: r, emphasis: emphasis.right)))
            }
            for line in (leftStart + paired)..<i {
                rows.append(Row(kind: .removed, left: Cell(line: line), right: nil))
                removed += 1
            }
            for line in (rightStart + paired)..<j {
                rows.append(Row(kind: .added, left: nil, right: Cell(line: line)))
                added += 1
            }
        }
    }

    // MARK: Word emphasis

    /// UTF-8 byte ranges of the words that differ between two paired lines.
    static func wordEmphasis(_ left: String, _ right: String) -> (left: [Range<Int>], right: [Range<Int>]) {
        guard left.utf8.count <= maximumEmphasisLineLength, right.utf8.count <= maximumEmphasisLineLength else {
            return ([], [])
        }
        let leftTokens = tokens(left), rightTokens = tokens(right)
        var deleted = Set<Int>(), inserted = Set<Int>()
        for change in rightTokens.difference(from: leftTokens) {
            switch change {
            case .remove(let offset, _, _): deleted.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var leftRanges: [Range<Int>] = [], rightRanges: [Range<Int>] = []
        var same = 0
        var at = 0
        for (index, token) in leftTokens.enumerated() {
            let length = token.utf8.count
            if deleted.contains(index) {
                pushMerged(&leftRanges, at..<(at + length))
            } else if !token.allSatisfy(\.isWhitespace) {
                // Similarity counts only non-whitespace text, so shared spacing
                // does not make unrelated lines look alike.
                same += length
            }
            at += length
        }
        at = 0
        for (index, token) in rightTokens.enumerated() {
            let length = token.utf8.count
            if inserted.contains(index) { pushMerged(&rightRanges, at..<(at + length)) }
            at += length
        }
        let total = nonWhitespaceLength(left) + nonWhitespaceLength(right)
        let similarity = total == 0 ? 1 : Double(2 * same) / Double(total)
        guard similarity >= minimumSimilarityForEmphasis else { return ([], []) }
        return (bridgeWhitespace(left, leftRanges), bridgeWhitespace(right, rightRanges))
    }

    /// Splits a line into words (letters, digits, `_`), runs of whitespace and
    /// single punctuation characters, so `compute(60)` and `compute_fast(60)`
    /// differ only in the word.
    static func tokens(_ line: String) -> [Substring] {
        enum Class { case word, space, other }
        func classify(_ character: Character) -> Class {
            if character.isLetter || character.isNumber || character == "_" { return .word }
            if character.isWhitespace { return .space }
            return .other
        }
        var tokens: [Substring] = []
        var start = line.startIndex
        var index = line.startIndex
        while index < line.endIndex {
            let current = classify(line[index])
            let next = line.index(after: index)
            let joinsNext = current != .other && next < line.endIndex && classify(line[next]) == current
            if !joinsNext {
                tokens.append(line[start..<next])
                start = next
            }
            index = next
        }
        return tokens
    }

    /// Joins ranges separated only by whitespace, so a changed phrase reads as
    /// one highlight instead of one per word.
    private static func bridgeWhitespace(_ line: String, _ ranges: [Range<Int>]) -> [Range<Int>] {
        let bytes = Array(line.utf8)
        var joined: [Range<Int>] = []
        for range in ranges {
            if let last = joined.last, bytes[last.upperBound..<range.lowerBound].allSatisfy({ $0 == 0x20 || $0 == 0x09 }) {
                joined[joined.count - 1] = last.lowerBound..<range.upperBound
            } else {
                joined.append(range)
            }
        }
        return joined
    }

    private static func nonWhitespaceLength(_ text: String) -> Int {
        text.filter { !$0.isWhitespace }.utf8.count
    }

    private static func pushMerged(_ ranges: inout [Range<Int>], _ range: Range<Int>) {
        if let last = ranges.last, last.upperBound == range.lowerBound {
            ranges[ranges.count - 1] = last.lowerBound..<range.upperBound
        } else {
            ranges.append(range)
        }
    }
}
