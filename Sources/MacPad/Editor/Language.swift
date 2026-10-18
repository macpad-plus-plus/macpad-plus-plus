import Foundation
import Scintilla

/// Semantic token categories. Themes colour these; each language maps its
/// lexer-specific style numbers onto them.
enum TokenKind: CaseIterable, Sendable {
    case comment, docComment, number, keyword, type, string, character
    case preprocessor, `operator`, regex
    case tag, attribute, entity
    case heading, emphasis, code, link
    case added, deleted, changed
    case error
}

/// A language definition: which Lexilla lexer to use and how to configure it.
///
/// Definitions come from Notepad++'s `langs.model.xml` and `stylers.model.xml`
/// (see `LanguageCatalog`), plus a few built-in extras such as Markdown.
struct Language: Identifiable, Hashable, Sendable {
    /// Notepad++ language name (e.g. "cpp", "javascript.js").
    let id: String
    let name: String
    /// Lexilla lexer name, as accepted by `CreateLexer`.
    let lexer: String
    var extensions: [String] = []
    var fileNames: [String] = []
    /// Keyword lists keyed by `SCI_SETKEYWORDS` set index.
    var keywords: [Int: String] = [:]
    var styles: [TokenKind: [Int32]] = [:]
    var properties: [String: String] = [:]
    var commentLine: String?
    var commentStart: String?
    var commentEnd: String?

    static func == (lhs: Language, rhs: Language) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Language {
    static let normalText = Language(id: "normal", name: String(localized: "Normal Text"), lexer: "null", extensions: ["txt"])

    /// Every language, sorted by display name, with Normal Text first.
    static let all: [Language] = {
        let loaded = LanguageCatalog.loadBundled()
        var languages = loaded.filter { $0.id != normalText.id } + extras
        languages.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return [loaded.first { $0.id == normalText.id } ?? normalText] + languages
    }()

    private static let byID: [String: Language] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func with(id: String) -> Language? { byID[id] }

    /// Picks a language from the file name, then the extension, then a shebang line.
    static func detect(for url: URL?, firstLine: String? = nil) -> Language {
        if let url {
            let fileName = url.lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()
            if let match = all.first(where: { $0.fileNames.contains(fileName) })
                ?? all.first(where: { !ext.isEmpty && $0.extensions.contains(ext) }) {
                return match
            }
        }
        if let firstLine, firstLine.hasPrefix("#!") {
            let interpreters: [(String, String)] = [
                ("python", "python"), ("node", "javascript.js"), ("ruby", "ruby"), ("perl", "perl"),
                ("php", "php"), ("lua", "lua"), ("sh", "bash"), ("zsh", "bash"), ("bash", "bash"),
            ]
            for (needle, id) in interpreters where firstLine.contains(needle) {
                if let language = with(id: id) { return language }
            }
        }
        return with(id: normalText.id) ?? normalText
    }

    /// Languages Notepad++ handles through user-defined languages, built in here
    /// because Lexilla ships a lexer for them.
    private static let extras: [Language] = [
        Language(
            id: "markdown", name: "Markdown", lexer: "markdown",
            extensions: ["md", "markdown", "mdown", "mkd"],
            styles: [
                .heading: [SCE_MARKDOWN_HEADER1, SCE_MARKDOWN_HEADER2, SCE_MARKDOWN_HEADER3,
                           SCE_MARKDOWN_HEADER4, SCE_MARKDOWN_HEADER5, SCE_MARKDOWN_HEADER6],
                .emphasis: [SCE_MARKDOWN_STRONG1, SCE_MARKDOWN_STRONG2, SCE_MARKDOWN_EM1, SCE_MARKDOWN_EM2],
                .keyword: [SCE_MARKDOWN_ULIST_ITEM, SCE_MARKDOWN_OLIST_ITEM, SCE_MARKDOWN_HRULE],
                .comment: [SCE_MARKDOWN_BLOCKQUOTE, SCE_MARKDOWN_STRIKEOUT],
                .link: [SCE_MARKDOWN_LINK],
                .code: [SCE_MARKDOWN_CODE, SCE_MARKDOWN_CODE2, SCE_MARKDOWN_CODEBK],
            ]),
    ]
}
