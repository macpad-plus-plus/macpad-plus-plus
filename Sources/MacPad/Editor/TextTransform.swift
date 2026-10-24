import Foundation

/// Text transformations behind the Edit menu's Convert Case, Line Operations
/// and Blank Operations, ported from Notepad++ (`ScintillaEditView::changeCase`,
/// `Sorters.h`, `Notepad_plus::wsTabConvert`). They work on plain strings so
/// they can be tested without an editor.
enum TextTransform {
    // MARK: Case

    enum Case: String, CaseIterable {
        case upper, lower
        /// Capitalizes each word and lowercases the rest.
        case properForce
        /// Capitalizes each word, leaving the rest as it is.
        case properBlend
        /// Capitalizes each sentence and lowercases the rest.
        case sentenceForce
        /// Capitalizes each sentence, leaving the rest as it is.
        case sentenceBlend
        case invert, random
    }

    static func convert(_ text: String, to textCase: Case) -> String {
        switch textCase {
        case .upper: return text.uppercased()
        case .lower: return text.lowercased()
        case .properForce, .properBlend: return properCase(text, force: textCase == .properForce)
        case .sentenceForce, .sentenceBlend: return sentenceCase(text, force: textCase == .sentenceForce)
        case .invert:
            return text.map { $0.isLowercase ? $0.uppercased() : $0.lowercased() }.joined()
        case .random:
            return text.map { $0.isLetter ? (Bool.random() ? $0.uppercased() : $0.lowercased()) : String($0) }.joined()
        }
    }

    private static func isSingleQuote(_ character: Character) -> Bool {
        character == "'" || character == "\u{2019}"
    }

    private static func isAlphanumeric(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// "it's a dog" → "It's A Dog": the letter after an apostrophe inside a word stays small.
    private static func properCase(_ text: String, force: Bool) -> String {
        let characters = Array(text)
        var result = ""
        for (index, character) in characters.enumerated() {
            guard character.isLetter else {
                result.append(character)
                continue
            }
            if index >= 2, isSingleQuote(characters[index - 1]), isAlphanumeric(characters[index - 2]) {
                result += force ? character.lowercased() : String(character)
            } else if index == 0 || !isAlphanumeric(characters[index - 1]) {
                result += character.uppercased()
            } else {
                result += force ? character.lowercased() : String(character)
            }
        }
        return result
    }

    /// A sentence starts the text, follows ". ", "! " or "? ", or follows a blank line.
    /// A lone "i" becomes "I", as in English.
    private static func sentenceCase(_ text: String, force: Bool) -> String {
        let characters = Array(text)
        var result = ""
        var isNewSentence = true
        var lineBreaks = 0
        for (index, character) in characters.enumerated() {
            if character.isLetter {
                var converted = String(character)
                if isNewSentence {
                    converted = character.uppercased()
                    isNewSentence = false
                } else if force {
                    converted = character.lowercased()
                }
                lineBreaks = 0
                if converted == "i",
                   index > 0, characters[index - 1].isWhitespace || "(\"".contains(characters[index - 1]),
                   index + 1 < characters.count, characters[index + 1].isWhitespace || characters[index + 1] == "'" {
                    converted = "I"
                }
                result += converted
                continue
            }
            if ".!?".contains(character) {
                isNewSentence = !(index + 1 == characters.count || isAlphanumeric(characters[index + 1]))
            } else if character.isNewline {
                lineBreaks += 1
                if lineBreaks >= 2 { isNewSentence = true }
            }
            result.append(character)
        }
        return result
    }

    // MARK: Sorting

    enum Sort: String, CaseIterable {
        case lexicographicAscending, lexicographicDescending
        case caseInsensitiveAscending, caseInsensitiveDescending
        case localeAscending, localeDescending
        case integerAscending, integerDescending
        case decimalCommaAscending, decimalCommaDescending
        case decimalDotAscending, decimalDotDescending
        case lengthAscending, lengthDescending
        case reverse, random

        var isDescending: Bool { rawValue.hasSuffix("Descending") }
    }

    /// A numeric sort met a line that does not start with a number.
    struct SortError: Error, Equatable {
        /// 0-based index of the line among those sorted.
        var lineIndex: Int
    }

    static func sort(_ lines: [String], _ sort: Sort) throws -> [String] {
        let descending = sort.isDescending
        func ordered(_ compare: (String, String) -> Int) -> [String] {
            lines.sorted { descending ? compare($0, $1) > 0 : compare($0, $1) < 0 }
        }
        switch sort {
        case .lexicographicAscending, .lexicographicDescending:
            return ordered { compareUTF16(Array($0.utf16), Array($1.utf16)) }
        case .caseInsensitiveAscending, .caseInsensitiveDescending:
            return ordered { compareUTF16(Array($0.lowercased().utf16), Array($1.lowercased().utf16)) }
        case .localeAscending, .localeDescending:
            return ordered { $0.localizedCompare($1).rawValue }
        case .integerAscending, .integerDescending:
            return ordered { compareNatural(Array($0.utf16), Array($1.utf16)) }
        case .decimalCommaAscending, .decimalCommaDescending:
            return try numericSort(lines, descending: descending, decimalComma: true)
        case .decimalDotAscending, .decimalDotDescending:
            return try numericSort(lines, descending: descending, decimalComma: false)
        case .lengthAscending, .lengthDescending:
            return ordered { $0.utf16.count - $1.utf16.count }
        case .reverse:
            return lines.reversed()
        case .random:
            return lines.shuffled()
        }
    }

    private static func compareUTF16(_ a: [UInt16], _ b: [UInt16]) -> Int {
        for (x, y) in zip(a, b) where x != y {
            return Int(x) - Int(y)
        }
        return a.count - b.count
    }

    private static func isDigit(_ unit: UInt16) -> Bool { unit >= 0x30 && unit <= 0x39 }
    private static let minus: UInt16 = 0x2D

    /// Notepad++'s "Sort as Integers": text compared chunk by chunk, with runs of
    /// digits (optionally negative) compared as numbers of any size.
    static func compareNatural(_ a: [UInt16], _ b: [UInt16]) -> Int {
        var i = 0, j = 0
        while true {
            if i >= a.count || j >= b.count {
                return compareUTF16(Array(a[min(i, a.count)...]), Array(b[min(j, b.count)...]))
            }
            var aIsNumber = isDigit(a[i]), bIsNumber = isDigit(b[j])
            var aSign = 1, bSign = 1
            if !aIsNumber, i + 1 < a.count {
                aIsNumber = a[i] == minus && isDigit(a[i + 1])
                aSign = -1
            }
            if !bIsNumber, j + 1 < b.count {
                bIsNumber = b[j] == minus && isDigit(b[j + 1])
                bSign = -1
            }
            if aIsNumber != bIsNumber {
                let result = Int(a[i]) - Int(b[j])
                if result != 0 { return result }
                i += 1
                j += 1
            } else if aIsNumber {
                if aSign != bSign { return aSign == 1 ? 1 : -1 }
                if aSign == -1 {
                    i += 1
                    j += 1
                }
                var aEnd = i, bEnd = j
                while aEnd < a.count, isDigit(a[aEnd]) { aEnd += 1 }
                while bEnd < b.count, isDigit(b[bEnd]) { bEnd += 1 }
                var aZeros = 0, bZeros = 0
                while i < aEnd, a[i] == 0x30 { aZeros += 1; i += 1 }
                while j < bEnd, b[j] == 0x30 { bZeros += 1; j += 1 }
                let aLength = aEnd - i, bLength = bEnd - j
                if aLength != bLength { return (aLength > bLength ? 1 : -1) * aSign }
                while i < aEnd {
                    let result = (Int(a[i]) - Int(b[j])) * aSign
                    if result != 0 { return result }
                    i += 1
                    j += 1
                }
                if bZeros != aZeros { return bZeros - aZeros }
            } else {
                if a[i] == minus { i += 1 }
                if b[j] == minus { j += 1 }
                var aEnd = i, bEnd = j
                while aEnd < a.count, !isDigit(a[aEnd]), a[aEnd] != minus { aEnd += 1 }
                while bEnd < b.count, !isDigit(b[bEnd]), b[bEnd] != minus { bEnd += 1 }
                let result = compareUTF16(Array(a[i..<aEnd]), Array(b[j..<bEnd]))
                if result != 0 { return result }
                i = aEnd
                j = bEnd
            }
        }
    }

    /// Lines are read as decimal numbers; blank lines go first (last when descending).
    private static func numericSort(_ lines: [String], descending: Bool, decimalComma: Bool) throws -> [String] {
        let admissible = Set(decimalComma ? " \t0123456789,-" : " \t0123456789.-")
        var numbered: [(line: String, value: Double)] = []
        var blanks: [String] = []
        for (index, line) in lines.enumerated() {
            var prepared = String(line.prefix { admissible.contains($0) })
            if decimalComma { prepared = prepared.replacingOccurrences(of: ",", with: ".") }
            let trimmed = prepared.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty, line.allSatisfy(\.isWhitespace) {
                blanks.append(line)
                continue
            }
            guard let value = leadingNumber(trimmed) else { throw SortError(lineIndex: index) }
            numbered.append((line, value))
        }
        let sorted = numbered.enumerated().sorted { lhs, rhs in
            lhs.element.value == rhs.element.value
                ? lhs.offset < rhs.offset
                : (descending ? lhs.element.value > rhs.element.value : lhs.element.value < rhs.element.value)
        }.map(\.element.line)
        return descending ? sorted + blanks : blanks + sorted
    }

    /// The number at the start of `text`, like C's strtod: "12.5-3" is 12.5.
    private static func leadingNumber(_ text: String) -> Double? {
        guard let match = text.firstMatch(of: /^-?(\d+(\.\d*)?|\.\d+)/) else { return nil }
        return Double(match.output.0)
    }

    // MARK: Duplicates and blank lines

    static func removingDuplicates(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.filter { seen.insert($0).inserted }
    }

    static func removingConsecutiveDuplicates(_ lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines where line != result.last {
            result.append(line)
        }
        return result
    }

    static func removingEmptyLines(_ lines: [String], includingBlank: Bool) -> [String] {
        lines.filter { includingBlank ? !$0.allSatisfy(isBlank) : !$0.isEmpty }
    }

    // MARK: Whitespace

    /// Spaces and tabs, the only characters the Trim commands remove.
    static func isBlank(_ character: Character) -> Bool { character == " " || character == "\t" }

    enum Trim { case leading, trailing, both }

    static func trim(_ line: String, _ trim: Trim) -> String {
        var line = Substring(line)
        if trim != .trailing { line = line.drop(while: isBlank) }
        if trim != .leading {
            while let last = line.last, isBlank(last) { line = line.dropLast() }
        }
        return String(line)
    }

    /// Expands each tab to the spaces that reach the next tab stop.
    static func tabsToSpaces(_ line: String, tabWidth: Int) -> String {
        var result = ""
        var column = 0
        for character in line {
            if character == "\t" {
                let spaces = tabWidth - column % tabWidth
                result += String(repeating: " ", count: spaces)
                column += spaces
            } else {
                result.append(character)
                column += 1
            }
        }
        return result
    }

    /// Replaces runs of two or more spaces that end on a tab stop with a tab;
    /// with `leadingOnly`, only in the indentation.
    static func spacesToTabs(_ line: String, tabWidth: Int, leadingOnly: Bool) -> String {
        var result = ""
        var pendingSpaces = 0
        var column = 0
        var inIndentation = true
        for character in line {
            let converting = !leadingOnly || inIndentation
            if character == " ", converting {
                pendingSpaces += 1
                column += 1
                if column % tabWidth == 0 {
                    result += pendingSpaces > 1 ? "\t" : " "
                    pendingSpaces = 0
                }
            } else if character == "\t", converting {
                // Spaces just before a tab are absorbed by it.
                pendingSpaces = 0
                result += "\t"
                column += tabWidth - column % tabWidth
            } else {
                result += String(repeating: " ", count: pendingSpaces)
                pendingSpaces = 0
                result.append(character)
                column += 1
                inIndentation = false
            }
        }
        return result + String(repeating: " ", count: pendingSpaces)
    }
}
