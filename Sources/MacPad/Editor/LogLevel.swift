import Foundation

/// Severity of a log line, used to color it while following a file.
enum LogLevel: Equatable, Sendable {
    case error, warning, info, debug, trace

    /// How far into a line a level is looked for: levels sit near the start
    /// (after a timestamp), and a bound keeps very long lines cheap.
    private static let scanLimit = 160

    /// Classifies one line by the first level keyword it holds as a whole
    /// word: `ERROR`, `WARN`, `INFO`… in upper case, as most logging
    /// frameworks write them, or capitalized (`[Error]`, as PowerShell does),
    /// plus the short and syslog forms. Lower case only counts before a colon
    /// (`error: …` from compilers, `fail: …` from .NET), since in running
    /// text "error" is usually just a word.
    static func classify<Bytes: RandomAccessCollection>(_ line: Bytes) -> LogLevel? where Bytes.Element == UInt8, Bytes.Index == Int {
        let end = min(line.endIndex, line.startIndex + scanLimit)
        var start = line.startIndex
        while start < end {
            guard isLetter(line[start]) else {
                start += 1
                continue
            }
            var wordEnd = start
            while wordEnd < end, isLetter(line[wordEnd]) { wordEnd += 1 }
            let startsWord = start == line.startIndex || !isAlphanumeric(line[start - 1])
            let endsWord = wordEnd == end || !isAlphanumeric(line[wordEnd])
            if startsWord, endsWord,
               let level = level(of: line[start..<wordEnd], beforeColon: wordEnd < end && line[wordEnd] == UInt8(ascii: ":")) {
                return level
            }
            start = wordEnd
        }
        return nil
    }

    private static func level<Word: Collection>(of word: Word, beforeColon: Bool) -> LogLevel? where Word.Element == UInt8 {
        guard let first = word.first else { return nil }
        let rest = word.dropFirst()
        let upper = isUpper(first) && rest.allSatisfy(isUpper)
        let capitalized = isUpper(first) && rest.allSatisfy(isLower)
        let lower = word.allSatisfy(isLower)
        // A lone letter is a level only in upper case (Android's `E`, `W`…).
        guard upper || (!rest.isEmpty && (capitalized || (lower && beforeColon))) else { return nil }
        switch String(decoding: word, as: UTF8.self).uppercased() {
        case "ERROR", "ERR", "FATAL", "CRITICAL", "CRIT", "PANIC", "SEVERE", "EMERG", "ALERT", "FAIL", "E", "F": return .error
        case "WARN", "WARNING", "W": return .warning
        case "INFO", "NOTICE", "I": return .info
        case "DEBUG", "DBG", "DBUG", "D": return .debug
        case "TRACE", "TRCE", "VERBOSE", "T", "V": return .trace
        default: return nil
        }
    }

    /// Byte ranges (offset by `base`) and levels of the lines in `text` that
    /// carry one, without their line breaks.
    static func spans(in text: Data, base: Int = 0) -> [(range: Range<Int>, level: LogLevel)] {
        var spans: [(Range<Int>, LogLevel)] = []
        text.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            var lineStart = 0
            while lineStart < bytes.count {
                var lineEnd = lineStart
                while lineEnd < bytes.count, bytes[lineEnd] != UInt8(ascii: "\n") { lineEnd += 1 }
                var contentEnd = lineEnd
                if contentEnd > lineStart, bytes[contentEnd - 1] == UInt8(ascii: "\r") { contentEnd -= 1 }
                if let level = classify(UnsafeBufferPointer(rebasing: bytes[lineStart..<contentEnd])) {
                    spans.append((base + lineStart..<base + contentEnd, level))
                }
                lineStart = lineEnd + 1
            }
        }
        return spans
    }

    private static func isLetter(_ byte: UInt8) -> Bool { isUpper(byte) || isLower(byte) }
    private static func isUpper(_ byte: UInt8) -> Bool { (65...90).contains(byte) }
    private static func isLower(_ byte: UInt8) -> Bool { (97...122).contains(byte) }
    private static func isAlphanumeric(_ byte: UInt8) -> Bool { isLetter(byte) || (48...57).contains(byte) }
}
