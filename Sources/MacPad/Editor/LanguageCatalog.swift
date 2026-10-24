import Foundation

/// Builds `Language` definitions from Notepad++'s `langs.model.xml` (keywords,
/// extensions, comment tokens) and `stylers.model.xml` (style IDs per lexer).
///
/// Colours from the stylers file are ignored: style names are classified into
/// `TokenKind`s so every language follows the app's light/dark themes.
enum LanguageCatalog {
    static func loadBundled() -> [Language] {
        guard let langsURL = Bundle.main.url(forResource: "langs.model", withExtension: "xml"),
              let stylersURL = Bundle.main.url(forResource: "stylers.model", withExtension: "xml"),
              let langs = LangsParser.parse(langsURL),
              let stylers = StylersParser.parse(stylersURL)
        else {
            assertionFailure("Notepad++ language definitions are missing from the bundle")
            return []
        }
        return build(langs: langs, stylers: stylers)
    }

    static func build(langs: [LangsParser.Entry], stylers: [String: [StylersParser.Style]]) -> [Language] {
        let doxygen = langs.first { $0.name == "cpp" }?.keywords["type2"]

        return langs.compactMap { entry -> Language? in
            guard !hiddenLanguages.contains(entry.name) else { return nil }
            let info = lexerTable[entry.name]
            let lexer = lexerOverrides[entry.name] ?? info?.lexer ?? "null"

            var keywords: [Int: String] = [:]
            for (className, words) in entry.keywords where !words.isEmpty {
                if let index = keywordSetIndex(language: entry.name, keywordClass: className) {
                    keywords[index] = words
                }
            }
            if cFamily.contains(entry.name), entry.name != "rc", let doxygen {
                keywords[2] = doxygen
            }

            // Hypertext styles embedded JS/PHP/ASP too; JSON5 reuses JSON's styler.
            var styleSources = [entry.name]
            if lexer == "hypertext" {
                styleSources = ["html", "javascript", "php", "asp"]
            } else if entry.name == "json5" {
                styleSources = ["json"]
            }
            var styles: [TokenKind: [Int32]] = [:]
            for style in styleSources.flatMap({ stylers[$0] ?? [] }) {
                if let kind = classify(style) {
                    styles[kind, default: []].append(style.id)
                }
            }

            return Language(
                id: entry.name,
                name: entry.name == "normal" ? String(localized: "Normal Text") : displayNames[entry.name] ?? info?.name ?? entry.name,
                lexer: lexer,
                extensions: entry.extensions,
                fileNames: fileNames[entry.name] ?? [],
                keywords: keywords,
                styles: styles,
                properties: properties(language: entry.name, lexer: lexer),
                comment: entry.comment)
        }
    }

    // MARK: Keyword sets

    /// Languages whose `cpp`-lexer keyword sets Notepad++ assigns by hand
    /// (`ScintillaEditView::setCppLexer` and friends).
    private static let cFamily: Set<String> = [
        "c", "cpp", "cs", "objc", "java", "rc", "actionscript", "swift", "go", "javascript.js", "typescript",
    ]

    /// Maps a langs.xml keyword class to a Scintilla keyword set, mirroring
    /// Notepad++. Most lexers take the classes in order (instre1 = 0,
    /// instre2 = 1, type1 = 2, ... type7 = 8); a few are special-cased.
    private static func keywordSetIndex(language: String, keywordClass: String) -> Int? {
        if cFamily.contains(language) {
            switch keywordClass {
            case "instre1": return 0
            case "type1": return 1
            case "instre2": return 3
            case "type2" where language == "objc": return 4
            default: return nil
            }
        }
        switch language {
        case "html", "asp", "jsp", "php":
            switch keywordClass {
            case "instre1": return 0
            case "instre2": return 5
            default: return nil
            }
        case "xml":
            return keywordClass == "instre1" ? 5 : nil
        case "tcl":
            let order = ["instre1", "type1", "instre2", "type2", "type3", "type4", "type5", "type6", "type7"]
            return order.firstIndex(of: keywordClass)
        default:
            let order = ["instre1", "instre2", "type1", "type2", "type3", "type4", "type5", "type6", "type7"]
            return order.firstIndex(of: keywordClass)
        }
    }

    // MARK: Style classification

    /// Assigns a theme category to a Notepad++ style from its name and keyword class.
    static func classify(_ style: StylersParser.Style) -> TokenKind? {
        let name = style.name.uppercased()
        func has(_ needles: String...) -> Bool { needles.contains { name.contains($0) } }

        if let keywordClass = style.keywordClass, keywordClass.hasPrefix("substyle") {
            return nil
        }
        if has("ERROR", "UNKNOWN", "ILLEGAL", "GARBAGE", "WRONG", "NOT CLOSED", "STRING EOL", "STRINGEOL") {
            return .error
        }
        if has("COMMENT") {
            return has("DOC") ? .docComment : .comment
        }
        if has("POD") { return .docComment }
        if has("PREPROC", "DIRECTIVE", "PRAGMA", "MACRO", "DECORATOR", "IFDEF", "DEFINE", "QUESTION MARK", "CDATA", "XML START", "XML END", "SGML") {
            return .preprocessor
        }
        if has("REGEX") { return .regex }
        if has("ESCAPE", "CHARACTER", "CHAR ") || name == "CHAR" { return .character }
        if has("STRING", "VERBATIM", "TRIPLE", "HEREDOC", "HERE ", "QUOTE", "BACKTICK", "LITERAL") {
            return .string
        }
        if has("NUMBER", "NUMERIC", "HEX DIGIT") { return .number }
        if has("ENTITY") { return .entity }
        if has("TAG") { return .tag }
        if has("ATTRIBUTE", "PROPERTY") || name == "KEY" || name == "PARAMETER" { return .attribute }
        if name.range(of: "^H[1-6]$", options: .regularExpression) != nil || has("HEADER", "SECTION", "TITLE") {
            return .heading
        }
        if has("LINK", "URL", "URI") { return .link }
        if has("ADDED") { return .added }
        if has("DELETED", "REMOVED") { return .deleted }
        if has("CHANGED") { return .changed }
        if has("STRONG", "EM1", "EM2") { return .emphasis }
        if let keywordClass = style.keywordClass {
            return keywordClass.hasPrefix("type") ? .type : .keyword
        }
        if has("TYPE", "CLASS", "FUNCTION", "FUNC", "GLOBAL", "BUILT", "PREDEFINED", "STD ") { return .type }
        if has("INSTRUCTION", "KEYWORD", "STATEMENT", "RESERVED", "COMMAND", "WORD") && !has("IDENTIFIER") {
            // Hypertext's embedded-JS "WORD" style is plain identifiers.
            return name == "WORD" ? nil : .keyword
        }
        if has("OPERATOR", "DELIMITER") { return .operator }
        return nil
    }

    // MARK: Lexer table

    /// Notepad++ language name -> (display name, Lexilla lexer), from
    /// `ScintillaEditView::_langNameInfoArray`.
    private static let lexerTable: [String: (name: String, lexer: String)] = [
        "normal": ("Normal Text", "null"),
        "php": ("PHP", "phpscript"),
        "c": ("C", "cpp"),
        "cpp": ("C++", "cpp"),
        "cs": ("C#", "cpp"),
        "objc": ("Objective-C", "objc"),
        "java": ("Java", "cpp"),
        "rc": ("RC", "cpp"),
        "html": ("HTML", "hypertext"),
        "xml": ("XML", "xml"),
        "makefile": ("Makefile", "makefile"),
        "pascal": ("Pascal", "pascal"),
        "batch": ("Batch", "batch"),
        "ini": ("ini", "props"),
        "nfo": ("NFO", "null"),
        "asp": ("ASP", "hypertext"),
        "sql": ("SQL", "sql"),
        "vb": ("Visual Basic", "vb"),
        "css": ("CSS", "css"),
        "perl": ("Perl", "perl"),
        "python": ("Python", "python"),
        "lua": ("Lua", "lua"),
        "tex": ("TeX", "tex"),
        "fortran": ("Fortran free form", "fortran"),
        "bash": ("Shell", "bash"),
        "actionscript": ("ActionScript", "cpp"),
        "nsis": ("NSIS", "nsis"),
        "tcl": ("TCL", "tcl"),
        "lisp": ("Lisp", "lisp"),
        "scheme": ("Scheme", "lisp"),
        "asm": ("Assembly", "asm"),
        "diff": ("Diff", "diff"),
        "props": ("Properties file", "props"),
        "postscript": ("PostScript", "ps"),
        "ruby": ("Ruby", "ruby"),
        "smalltalk": ("Smalltalk", "smalltalk"),
        "vhdl": ("VHDL", "vhdl"),
        "kix": ("KiXtart", "kix"),
        "autoit": ("AutoIt", "au3"),
        "caml": ("CAML", "caml"),
        "ada": ("Ada", "ada"),
        "verilog": ("Verilog", "verilog"),
        "matlab": ("MATLAB", "matlab"),
        "haskell": ("Haskell", "haskell"),
        "inno": ("Inno Setup", "inno"),
        "cmake": ("CMake", "cmake"),
        "yaml": ("YAML", "yaml"),
        "cobol": ("COBOL", "COBOL"),
        "gui4cli": ("Gui4Cli", "gui4cli"),
        "d": ("D", "d"),
        "powershell": ("PowerShell", "powershell"),
        "r": ("R", "r"),
        "jsp": ("JSP", "hypertext"),
        "coffeescript": ("CoffeeScript", "coffeescript"),
        "json": ("json", "json"),
        "javascript.js": ("JavaScript", "cpp"),
        "fortran77": ("Fortran fixed form", "f77"),
        "baanc": ("BaanC", "baan"),
        "srec": ("S-Record", "srec"),
        "ihex": ("Intel HEX", "ihex"),
        "tehex": ("Tektronix extended HEX", "tehex"),
        "swift": ("Swift", "cpp"),
        "asn1": ("ASN.1", "asn1"),
        "avs": ("AviSynth", "avs"),
        "blitzbasic": ("BlitzBasic", "blitzbasic"),
        "purebasic": ("PureBasic", "purebasic"),
        "freebasic": ("FreeBasic", "freebasic"),
        "csound": ("Csound", "csound"),
        "erlang": ("Erlang", "erlang"),
        "escript": ("ESCRIPT", "escript"),
        "forth": ("Forth", "forth"),
        "latex": ("LaTeX", "latex"),
        "mmixal": ("MMIXAL", "mmixal"),
        "nim": ("Nim", "nimrod"),
        "nncrontab": ("Nncrontab", "nncrontab"),
        "oscript": ("OScript", "oscript"),
        "rebol": ("REBOL", "rebol"),
        "registry": ("registry", "registry"),
        "rust": ("Rust", "rust"),
        "spice": ("Spice", "spice"),
        "txt2tags": ("txt2tags", "txt2tags"),
        "visualprolog": ("Visual Prolog", "visualprolog"),
        "typescript": ("TypeScript", "cpp"),
        "json5": ("json5", "json"),
        "mssql": ("mssql", "mssql"),
        "gdscript": ("GDScript", "gdscript"),
        "hollywood": ("Hollywood", "hollywood"),
        "go": ("Go", "cpp"),
        "raku": ("Raku", "raku"),
        "toml": ("TOML", "toml"),
        "sas": ("SAS", "sas"),
        "errorlist": ("ErrorList", "errorlist"),
        "escseq": ("EscapeSequence (ANSI)", "escseq"),
        "fcST": ("Structured Text", "fcST"),
    ]

    /// Notepad++ internals with no meaning outside it.
    private static let hiddenLanguages: Set<String> = ["javascript", "searchResult", "udf", "ext"]

    /// Lexers that only exist in Notepad++'s Lexilla fork, or that Notepad++
    /// swaps out at runtime (whole PHP files are lexed as hypertext).
    private static let lexerOverrides: [String: String] = [
        "objc": "cpp",
        "php": "hypertext",
    ]

    private static let displayNames: [String: String] = [
        "ini": "INI",
        "json": "JSON",
        "json5": "JSON5",
        "mssql": "Transact-SQL",
        "registry": "Registry",
        "nfo": "NFO (ASCII Art)",
    ]

    private static let fileNames: [String: [String]] = [
        "makefile": ["makefile", "gnumakefile"],
        "cmake": ["cmakelists.txt"],
        "bash": [".bashrc", ".zshrc", ".profile", ".bash_profile", ".zprofile", ".zshenv"],
        "props": [".editorconfig", ".gitconfig", ".gitattributes"],
        "ruby": ["gemfile", "rakefile", "podfile"],
    ]

    private static func properties(language: String, lexer: String) -> [String: String] {
        var properties = [
            "fold": "1", "fold.compact": "0", "fold.comment": "1", "fold.preprocessor": "1",
        ]
        switch lexer {
        case "cpp":
            properties["fold.cpp.comment.explicit"] = "0"
            properties["lexer.cpp.track.preprocessor"] = "0"
            if language == "go" || language == "typescript" {
                properties["lexer.cpp.backquoted.strings"] = "1"
            }
        case "hypertext", "xml":
            properties["fold.html"] = "1"
            properties["fold.hypertext.comment"] = "1"
            if lexer == "xml" {
                properties["lexer.xml.allow.scripts"] = "0"
            }
        case "python":
            properties["fold.quotes.python"] = "1"
            properties["lexer.python.decorator.attributes"] = "1"
        case "json":
            properties["lexer.json.escape.sequence"] = "1"
            properties["lexer.json.allow.comments"] = "1"
        case "asm":
            properties["fold.asm.syntax.based"] = "1"
            properties["fold.asm.comment.multiline"] = "1"
        default:
            break
        }
        return properties
    }
}

// MARK: - XML parsing

/// Reads `<Language>` entries from langs.model.xml.
final class LangsParser: NSObject, XMLParserDelegate {
    struct Entry {
        var name: String
        var extensions: [String]
        var keywords: [String: String] = [:]
        var comment = Language.CommentSymbols()
    }

    private var entries: [Entry] = []
    private var current: Entry?
    private var keywordClass: String?
    private var text = ""

    static func parse(_ url: URL) -> [Entry]? {
        guard let parser = XMLParser(contentsOf: url) else { return nil }
        let delegate = LangsParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.entries : nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "Language":
            current = Entry(
                name: attributes["name"] ?? "",
                extensions: (attributes["ext"] ?? "").lowercased().split(separator: " ").map(String.init),
                comment: Language.CommentSymbols(
                    line: attributes["commentLine"] ?? "",
                    start: attributes["commentStart"] ?? "",
                    end: attributes["commentEnd"] ?? ""))
        case "Keywords":
            keywordClass = attributes["name"]
            text = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if keywordClass != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Keywords":
            if let keywordClass {
                current?.keywords[keywordClass] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            keywordClass = nil
        case "Language":
            if let current { entries.append(current) }
            current = nil
        default:
            break
        }
    }
}

/// Reads `<LexerType>/<WordsStyle>` entries from stylers.model.xml.
final class StylersParser: NSObject, XMLParserDelegate {
    struct Style {
        var name: String
        var id: Int32
        var keywordClass: String?
    }

    private var lexers: [String: [Style]] = [:]
    private var currentLexer: String?

    static func parse(_ url: URL) -> [String: [Style]]? {
        guard let parser = XMLParser(contentsOf: url) else { return nil }
        let delegate = StylersParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.lexers : nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "LexerType":
            currentLexer = attributes["name"]
        case "WordsStyle":
            guard let currentLexer, let name = attributes["name"],
                  let id = attributes["styleID"].flatMap(Int32.init)
            else { return }
            lexers[currentLexer, default: []].append(Style(name: name, id: id, keywordClass: attributes["keywordClass"]))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "LexerType" { currentLexer = nil }
    }
}
