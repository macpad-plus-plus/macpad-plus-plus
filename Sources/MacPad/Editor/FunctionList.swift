import Foundation

/// A function, method or heading found in a document.
struct Symbol: Equatable, Sendable {
    var name: String
    /// Enclosing class/struct/namespace, when the parser reports one.
    var container: String?
    /// UTF-16 offset of the name in the document.
    var offset: Int
    /// 1-based line of the name.
    var line: Int
}

/// Notepad++ function-list parsers (`installer/functionList/*.xml`), run with
/// ICU regular expressions instead of Boost.
///
/// The matching algorithm mirrors Notepad++'s `functionParser.cpp`: comment
/// zones are excluded, class ranges are found with `classRange/mainExpr` and
/// closed by brace counting, and names are narrowed by chained `nameExpr`s.
struct FunctionListParser: Sendable {
    struct FunctionRule: Sendable {
        var main: BoostRegex
        var nameExprs: [BoostRegex]
        var classNameExprs: [BoostRegex]
    }

    struct ClassRule: Sendable {
        var main: BoostRegex
        var openSymbol: BoostRegex?
        var closeSymbol: BoostRegex?
        var nameExprs: [BoostRegex]
        var function: FunctionRule?
    }

    var comment: BoostRegex?
    var classRule: ClassRule?
    var function: FunctionRule?

    // MARK: Loading

    private static let cache = ParserCache()

    /// The parser for a Notepad++ language name, loaded on first use (thread-safe).
    /// Nil when there is none or its patterns cannot run on ICU.
    static func parser(for language: String) -> FunctionListParser? {
        cache.parser(for: language)
    }

    static func hasParser(for language: String) -> Bool {
        Bundle.main.url(forResource: language, withExtension: "xml", subdirectory: "FunctionList") != nil
    }

    private final class ParserCache: @unchecked Sendable {
        private let lock = NSLock()
        private var parsers: [String: FunctionListParser?] = [:]

        func parser(for language: String) -> FunctionListParser? {
            lock.lock()
            defer { lock.unlock() }
            if let cached = parsers[language] { return cached }
            let url = Bundle.main.url(forResource: language, withExtension: "xml", subdirectory: "FunctionList")
            let parser = url.flatMap { try? FunctionListParser.load(from: $0) }
            parsers[language] = parser
            return parser
        }
    }

    /// Parsers keyed by Notepad++ language name (the XML file name).
    static func loadBundled() -> [String: FunctionListParser] {
        guard let directory = Bundle.main.url(forResource: "FunctionList", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [:] }
        var parsers: [String: FunctionListParser] = [:]
        for file in files where file.pathExtension == "xml" {
            if let parser = try? load(from: file) {
                parsers[file.deletingPathExtension().lastPathComponent] = parser
            }
        }
        return parsers
    }

    static func load(from url: URL) throws -> FunctionListParser {
        let document = try XMLDocument(xmlString: preservingAttributeNewlines(try String(contentsOf: url, encoding: .utf8)))
        guard let parser = try document.nodes(forXPath: "//functionList/parser").first as? XMLElement else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try FunctionListParser(element: parser)
    }

    /// XML parsers normalise newlines in attribute values to spaces, which breaks
    /// `(?x)` patterns: their `#` comments would swallow the rest of the pattern.
    /// Notepad++'s TinyXML keeps them, so escape them as character references.
    static func preservingAttributeNewlines(_ xml: String) -> String {
        var result = ""
        var inValue = false
        var inTag = false
        for character in xml {
            switch character {
            case "<" where !inValue: inTag = true
            case ">" where !inValue: inTag = false
            case "\"" where inTag: inValue.toggle()
            default: break
            }
            if inValue, character == "\n" || character == "\r\n" {
                result += "&#10;"
            } else if inValue, character == "\t" {
                result += "&#9;"
            } else {
                result.append(character)
            }
        }
        return result
    }

    init(element parser: XMLElement) throws {
        func regex(_ element: XMLElement?, _ attribute: String) throws -> BoostRegex? {
            guard let pattern = element?.attribute(forName: attribute)?.stringValue, !pattern.isEmpty else { return nil }
            return try BoostRegex(pattern)
        }
        func chain(_ element: XMLElement?, _ container: String, _ child: String) throws -> [BoostRegex] {
            let nodes = (element?.elements(forName: container).first?.elements(forName: child)) ?? []
            return try nodes.compactMap { try regex($0, "expr") }
        }
        func functionRule(_ element: XMLElement?) throws -> FunctionRule? {
            guard let element, let main = try regex(element, "mainExpr") else { return nil }
            return FunctionRule(
                main: main,
                nameExprs: try chain(element, "functionName", "nameExpr") + chain(element, "functionName", "funcNameExpr"),
                classNameExprs: try chain(element, "className", "nameExpr"))
        }

        comment = try regex(parser, "commentExpr")
        function = try functionRule(parser.elements(forName: "function").first)
        if let range = parser.elements(forName: "classRange").first, let main = try regex(range, "mainExpr") {
            classRule = ClassRule(
                main: main,
                openSymbol: try regex(range, "openSymbole"),
                closeSymbol: try regex(range, "closeSymbole"),
                nameExprs: try chain(range, "className", "nameExpr"),
                function: try functionRule(range.elements(forName: "function").first))
        }
    }

    // MARK: Parsing

    func parse(_ string: String) -> [Symbol] {
        let text = string as NSString
        var context = Context(text: text)
        let whole = NSRange(location: 0, length: text.length)
        context.comments = comment.map { zones(of: $0, in: whole, text: text) } ?? []

        switch (classRule, function) {
        case let (classRule?, function):
            // Class zones first, then free functions everywhere else.
            var classZones: [NSRange] = []
            for zone in invert(context.comments, in: whole) {
                classZones += parseClasses(classRule, in: zone, context: &context)
            }
            if let function {
                for zone in invert(classZones, in: whole) {
                    parseFunctions(function, in: zone, container: nil, context: &context)
                }
            }
        case let (nil, function?):
            for zone in invert(context.comments, in: whole) {
                parseFunctions(function, in: zone, container: nil, context: &context)
            }
        case (nil, nil):
            break
        }
        return context.symbols.sorted { $0.offset < $1.offset }
    }

    private struct Context {
        let text: NSString
        var comments: [NSRange] = []
        var symbols: [Symbol] = []
        var seen = Set<Int>()
        private var lineStarts: [Int]?

        init(text: NSString) {
            self.text = text
        }

        func isInComment(_ location: Int) -> Bool {
            comments.contains { NSLocationInRange(location, $0) }
        }

        mutating func line(at offset: Int) -> Int {
            if lineStarts == nil {
                var starts = [0]
                let length = text.length
                var index = 0
                while index < length {
                    let char = text.character(at: index)
                    if char == 0x0A || (char == 0x0D && (index + 1 >= length || text.character(at: index + 1) != 0x0A)) {
                        starts.append(index + 1)
                    }
                    index += 1
                }
                lineStarts = starts
            }
            // Binary search for the last line start <= offset.
            var low = 0, high = lineStarts!.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if lineStarts![mid] <= offset { low = mid } else { high = mid - 1 }
            }
            return low + 1
        }

        mutating func add(name: String, container: String?, offset: Int) {
            let clean = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !clean.isEmpty, seen.insert(offset).inserted else { return }
            let containerName = container?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            symbols.append(Symbol(name: clean, container: containerName?.isEmpty == false ? containerName : nil,
                                  offset: offset, line: line(at: offset)))
        }
    }

    /// `FunctionParser::funcParse`.
    private func parseFunctions(_ rule: FunctionRule, in zone: NSRange, container: String?, context: inout Context) {
        var location = zone.location
        let end = NSMaxRange(zone)
        while location < end, let match = rule.main.firstMatch(in: context.text, range: NSRange(location: location, length: end - location)) {
            var name: (String, Int)?
            var className: (String, Int)?
            if rule.nameExprs.isEmpty && rule.classNameExprs.isEmpty {
                name = (context.text.substring(with: match), match.location)
            } else {
                name = narrow(match, with: rule.nameExprs, text: context.text)
                if let container {
                    className = (container, -1)
                } else {
                    className = narrow(match, with: rule.classNameExprs, text: context.text)
                }
            }
            if let name, !context.isInComment(name.1) {
                context.add(name: name.0, container: className?.0, offset: name.1)
            }
            location = max(NSMaxRange(match), match.location + 1)
        }
    }

    /// `FunctionZoneParser::classParse`. Returns the class zones it scanned.
    private func parseClasses(_ rule: ClassRule, in zone: NSRange, context: inout Context) -> [NSRange] {
        var zones: [NSRange] = []
        var location = zone.location
        let end = NSMaxRange(zone)
        while location < end, let match = rule.main.firstMatch(in: context.text, range: NSRange(location: location, length: end - location)) {
            let className = narrow(match, with: rule.nameExprs, text: context.text)?.0
            var zoneEnd = NSMaxRange(match)
            if let open = rule.openSymbol, let close = rule.closeSymbol {
                zoneEnd = bodyEnd(from: zoneEnd, open: open, close: close, context: context)
            }
            let classZone = NSRange(location: match.location, length: zoneEnd - match.location)
            zones.append(classZone)
            if let function = rule.function, !context.isInComment(match.location) {
                parseFunctions(function, in: classZone, container: className, context: &context)
            }
            location = max(zoneEnd, match.location + 1)
        }
        return zones
    }

    /// `FunctionZoneParser::getBodyClosePos`: counts open/close symbols outside comments.
    private func bodyEnd(from start: Int, open: BoostRegex, close: BoostRegex, context: Context) -> Int {
        let length = context.text.length
        var depth = 1
        var location = start
        while depth > 0, location < length {
            let range = NSRange(location: location, length: length - location)
            let nextOpen = open.firstMatch(in: context.text, range: range)
            let nextClose = close.firstMatch(in: context.text, range: range)
            guard let symbol = [nextOpen, nextClose].compactMap({ $0 }).min(by: { $0.location < $1.location }) else {
                return start
            }
            if !context.isInComment(symbol.location) {
                depth += symbol == nextOpen ? 1 : -1
            }
            location = max(NSMaxRange(symbol), symbol.location + 1)
        }
        return min(location, length)
    }

    /// `FunctionParser::parseSubLevel`: each expression searches inside the previous match.
    private func narrow(_ range: NSRange, with exprs: [BoostRegex], text: NSString) -> (String, Int)? {
        guard !exprs.isEmpty else { return nil }
        var current = range
        for expr in exprs {
            guard let match = expr.firstMatch(in: text, range: current) else { return nil }
            current = match
        }
        return (text.substring(with: current), current.location)
    }

    private func zones(of regex: BoostRegex, in range: NSRange, text: NSString) -> [NSRange] {
        var zones: [NSRange] = []
        var location = range.location
        while location < NSMaxRange(range), let match = regex.firstMatch(in: text, range: NSRange(location: location, length: NSMaxRange(range) - location)) {
            if match.length > 0 { zones.append(match) }
            location = max(NSMaxRange(match), match.location + 1)
        }
        return zones
    }

    /// The parts of `range` not covered by `zones` (which are sorted).
    private func invert(_ zones: [NSRange], in range: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        var location = range.location
        for zone in zones.sorted(by: { $0.location < $1.location }) {
            if zone.location > location {
                result.append(NSRange(location: location, length: zone.location - location))
            }
            location = max(location, NSMaxRange(zone))
        }
        if location < NSMaxRange(range) {
            result.append(NSRange(location: location, length: NSMaxRange(range) - location))
        }
        return result
    }
}

/// A Notepad++ (Boost/Perl) pattern translated for NSRegularExpression (ICU).
///
/// Boost options used by Notepad++'s function list: `.` matches newlines and
/// `^`/`$` match at line boundaries. Unsupported constructs are rewritten:
/// `\K` becomes a capture group whose range is reported as the match,
/// `(?'name')` becomes `(?<name>)`, and `\<`/`\>` become `\b`.
struct BoostRegex: @unchecked Sendable {
    /// NSRegularExpression is immutable and documented as thread-safe.
    let regex: NSRegularExpression
    private let keepGroup = "mpkeep"
    private let hasKeep: Bool

    init(_ pattern: String) throws {
        let (translated, hasKeep) = try Self.translate(pattern)
        self.hasKeep = hasKeep
        let expanded = Self.expandSubroutines(translated, extended: Self.isExtended(pattern))
        regex = try NSRegularExpression(pattern: expanded, options: [.dotMatchesLineSeparators, .anchorsMatchLines])
    }

    static func isExtended(_ pattern: String) -> Bool {
        pattern.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("(?x")
    }

    /// The first match in `range`, narrowed to the part after `\K` if present.
    func firstMatch(in text: NSString, range: NSRange) -> NSRange? {
        guard let result = regex.firstMatch(in: text as String, options: [.withoutAnchoringBounds], range: range) else {
            return nil
        }
        if hasKeep {
            let kept = result.range(withName: keepGroup)
            if kept.location != NSNotFound { return kept }
        }
        return result.range
    }

    /// ICU group names allow only ASCII letters and digits (no underscores).
    private static func groupName(_ characters: ArraySlice<Character>) -> String {
        let name = String(characters.filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
        return name.first?.isLetter == true ? name : "g" + name
    }

    enum TranslationError: Error {
        case unsupported(String)
    }

    static func translate(_ pattern: String) throws -> (String, Bool) {
        let chars = Array(pattern)
        var output = ""
        var depth = 0
        var keepOffset: Int?
        var index = 0
        let extended = isExtended(pattern)

        while index < chars.count {
            let c = chars[index]
            switch c {
            case "#" where extended:
                // Free-spacing comment: copy through end of line untouched.
                while index < chars.count, chars[index] != "\n" {
                    output.append(chars[index]); index += 1
                }
                continue
            case "\\":
                guard index + 1 < chars.count else { output.append(c); index += 1; continue }
                let next = chars[index + 1]
                switch next {
                case "K":
                    if depth == 0, keepOffset == nil {
                        keepOffset = output.count
                    }
                    index += 2
                    continue
                case "<", ">":
                    output += "\\b"
                case "k" where index + 2 < chars.count && "'<{".contains(chars[index + 2]):
                    // \k'name', \k<name>, \k{name} -> \k<name>
                    let closer: Character = chars[index + 2] == "'" ? "'" : chars[index + 2] == "<" ? ">" : "}"
                    var end = index + 3
                    while end < chars.count, chars[end] != closer { end += 1 }
                    output += "\\k<" + groupName(chars[(index + 3)..<min(end, chars.count)]) + ">"
                    index = end + 1
                    continue
                default:
                    output.append(c); output.append(next)
                }
                index += 2
                continue
            case "[":
                // Copy a character class verbatim (it may contain parentheses).
                output.append(c); index += 1
                if index < chars.count, chars[index] == "^" { output.append("^"); index += 1 }
                if index < chars.count, chars[index] == "]" { output.append("]"); index += 1 }
                while index < chars.count, chars[index] != "]" {
                    if chars[index] == "\\", index + 1 < chars.count {
                        output.append(chars[index]); output.append(chars[index + 1]); index += 2
                    } else if chars[index] == "[", index + 1 < chars.count, chars[index + 1] == ":" {
                        // POSIX class like [:alpha:]
                        while index < chars.count, !(chars[index] == "]" && chars[index - 1] == ":") {
                            output.append(chars[index]); index += 1
                        }
                        if index < chars.count { output.append("]"); index += 1 }
                    } else {
                        // Literal in Boost, but set syntax (or ignored) in ICU.
                        switch chars[index] {
                        case "[", "&", "#", "$", "{", "}": output += "\\" + String(chars[index])
                        case " " where extended: output += "\\x20"
                        case "\t" where extended: output += "\\t"
                        case "\n" where extended, "\r" where extended: break
                        default: output.append(chars[index])
                        }
                        index += 1
                    }
                }
                if index < chars.count { output.append("]"); index += 1 }
                continue
            case "{":
                // Boost reads a "{" that does not start a {n,m} quantifier literally; ICU rejects it.
                let tail = String(chars[index..<min(index + 24, chars.count)])
                if let quantifier = tail.range(of: #"^\{\d+(,\d*)?\}"#, options: .regularExpression) {
                    output += tail[quantifier]
                    index += tail[quantifier].count
                } else {
                    output += "\\{"
                    index += 1
                }
                continue
            case "}":
                output += "\\}"
                index += 1
                continue
            case "(":
                let rest = String(chars[index..<min(index + 4, chars.count)])
                // Named groups and subroutine calls: (?'name' (?P<name> (?<name> (?&name) (?P>name)
                let nameStart: Int?
                let closer: Character
                let prefix: String
                if rest.hasPrefix("(?'") {
                    (nameStart, closer, prefix) = (index + 3, "'", "(?<")
                } else if rest.hasPrefix("(?P<") {
                    (nameStart, closer, prefix) = (index + 4, ">", "(?<")
                } else if rest.hasPrefix("(?<"), rest.count > 3, rest.last != "=", rest.last != "!" {
                    (nameStart, closer, prefix) = (index + 3, ">", "(?<")
                } else if rest.hasPrefix("(?&") {
                    (nameStart, closer, prefix) = (index + 3, ")", "(?&")
                } else if rest.hasPrefix("(?P>") {
                    (nameStart, closer, prefix) = (index + 4, ")", "(?&")
                } else {
                    (nameStart, closer, prefix) = (nil, ")", "")
                }
                if let nameStart {
                    var end = nameStart
                    while end < chars.count, chars[end] != closer { end += 1 }
                    let name = groupName(chars[nameStart..<min(end, chars.count)])
                    if prefix == "(?&" {
                        output += "(?&" + name + ")"
                    } else {
                        output += prefix + name + ">"
                        depth += 1
                    }
                    index = end + 1
                    continue
                }
                if rest.hasPrefix("(?+") || rest.hasPrefix("(?|") {
                    throw TranslationError.unsupported(rest)
                }
                depth += 1
                output.append(c)
            case ")":
                depth -= 1
                output.append(c)
            default:
                output.append(c)
            }
            index += 1
        }

        guard let keepOffset else { return (output, false) }
        let keepIndex = output.index(output.startIndex, offsetBy: keepOffset)
        let prefix = output[..<keepIndex]
        let suffix = output[keepIndex...]
        // A newline keeps the closing parenthesis out of a trailing (?x) comment.
        return (prefix + "(?<mpkeep>" + suffix + (extended ? "\n)" : ")"), true)
    }

    // MARK: Subroutines and recursion

    /// How many levels of `(?&name)`, `(?N)` and `(?R)` to unroll; deeper nesting fails to match.
    private static let recursionDepth = 4

    /// Inlines Boost subroutine calls, which ICU lacks: `(?&NAME)` and `(?N)` become a
    /// copy of the referenced group, `(?R)` a copy of the whole pattern, unrolled a few
    /// levels deep. `(?(DEFINE)...)` blocks, used only to declare such groups, are removed.
    static func expandSubroutines(_ pattern: String, extended: Bool) -> String {
        guard pattern.contains("(?&") || pattern.contains("(?R)") || pattern.range(of: #"\(\?\d+\)"#, options: .regularExpression) != nil else {
            return pattern
        }
        let chars = Array(pattern)
        var named: [String: String] = [:]
        var numbered: [String] = []
        var defineBlocks: [Range<Int>] = []

        for group in groups(in: chars, extended: extended) {
            let text = String(chars[group.open..<group.close + 1])
            if text.hasPrefix("(?(DEFINE)") {
                defineBlocks.append(group.open..<group.close + 1)
                continue
            }
            if text.hasPrefix("(?<"), !text.hasPrefix("(?<="), !text.hasPrefix("(?<!"),
               let end = text.firstIndex(of: ">") {
                let name = String(text[text.index(text.startIndex, offsetBy: 3)..<end])
                named[name] = String(text[text.index(after: end)..<text.index(before: text.endIndex)])
                numbered.append(named[name]!)
            } else if !text.hasPrefix("(?") {
                numbered.append(String(text.dropFirst().dropLast()))
            }
        }

        var body = chars
        for block in defineBlocks.reversed() {
            body.removeSubrange(block)
        }
        let whole = String(body)

        func inline(_ text: String, level: Int) -> String {
            var result = ""
            let chars = Array(text)
            var index = 0
            while index < chars.count {
                if chars[index] == "\\", index + 1 < chars.count {
                    result.append(chars[index]); result.append(chars[index + 1]); index += 2
                    continue
                }
                if chars[index] == "(", index + 2 < chars.count, chars[index + 1] == "?" {
                    var end = index + 2
                    while end < chars.count, chars[end] != ")" { end += 1 }
                    let call = String(chars[(index + 2)..<min(end, chars.count)])
                    var target: String?
                    if call.hasPrefix("&") {
                        target = named[String(call.dropFirst())]
                    } else if call == "R" {
                        target = whole
                    } else if let number = Int(call), number >= 1, number <= numbered.count {
                        target = numbered[number - 1]
                    }
                    if let target, end < chars.count {
                        result += level >= recursionDepth ? "(?!)" : "(?:" + inline(stripGroupNames(target), level: level + 1) + (extended ? "\n)" : ")")
                        index = end + 1
                        continue
                    }
                }
                result.append(chars[index])
                index += 1
            }
            return result
        }
        return inline(whole, level: 0)
    }

    /// Copies of a group must not redefine its name (ICU rejects duplicates).
    private static func stripGroupNames(_ text: String) -> String {
        text.replacingOccurrences(of: #"\(\?<(?![=!])\w+>"#, with: "(?:", options: .regularExpression)
    }

    /// Every parenthesised group, skipping escapes, character classes and (?x) comments.
    private static func groups(in chars: [Character], extended: Bool) -> [(open: Int, close: Int)] {
        var stack: [Int] = []
        var result: [(open: Int, close: Int)] = []
        var index = 0
        var inClass = false
        while index < chars.count {
            let c = chars[index]
            if c == "\\" { index += 2; continue }
            if inClass {
                if c == "]" { inClass = false }
            } else if c == "[" {
                inClass = true
                if index + 1 < chars.count, chars[index + 1] == "]" { index += 1 }
            } else if c == "#", extended {
                while index < chars.count, chars[index] != "\n" { index += 1 }
                continue
            } else if c == "(" {
                stack.append(index)
            } else if c == ")", let open = stack.popLast() {
                result.append((open, index))
            }
            index += 1
        }
        return result.sorted { $0.open < $1.open }
    }
}
