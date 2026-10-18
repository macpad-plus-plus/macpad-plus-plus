import AppKit

/// Colours for the editor, expressed as 0xRRGGBB. Chrome colours that should
/// follow the system (selection, accent) are resolved at apply time instead.
struct EditorTheme: Sendable {
    struct TokenStyle: Sendable {
        var color: UInt32
        var bold = false
        var italic = false
    }

    var background: UInt32
    var foreground: UInt32
    var gutterBackground: UInt32
    var gutterForeground: UInt32
    var caretLine: UInt32
    var whitespace: UInt32
    var braceMatchBackground: UInt32
    var tokens: [TokenKind: TokenStyle]
    /// Fixed selection colour; nil uses the system highlight colour.
    var selection: UInt32?
    /// Fixed caret colour; nil uses the accent colour.
    var caret: UInt32?
    var caretWidth = 2
    /// Font used when the font preference is "Automatic".
    var preferredFont: String?

    /// Modelled on Xcode's "Default (Light)".
    static let light = EditorTheme(
        background: 0xFFFFFF,
        foreground: 0x1F1F24,
        gutterBackground: 0xFFFFFF,
        gutterForeground: 0xA6A6AB,
        caretLine: 0xECF5FF,
        whitespace: 0xC7C7CC,
        braceMatchBackground: 0xFCE79A,
        tokens: [
            .comment: .init(color: 0x5D6C79),
            .docComment: .init(color: 0x5D6C79, italic: true),
            .number: .init(color: 0x1C00CF),
            .keyword: .init(color: 0x9B2393, bold: true),
            .type: .init(color: 0x0B4F79),
            .string: .init(color: 0xC41A16),
            .character: .init(color: 0x1C00CF),
            .preprocessor: .init(color: 0x643820),
            .operator: .init(color: 0x1F1F24),
            .regex: .init(color: 0xC41A16),
            .tag: .init(color: 0x9B2393),
            .attribute: .init(color: 0x815F03),
            .entity: .init(color: 0x1C00CF),
            .heading: .init(color: 0x0B4F79, bold: true),
            .emphasis: .init(color: 0x1F1F24, italic: true),
            .code: .init(color: 0xC41A16),
            .link: .init(color: 0x0E0EFF),
            .added: .init(color: 0x1F7A1F),
            .deleted: .init(color: 0xC41A16),
            .changed: .init(color: 0x815F03),
            .error: .init(color: 0xD12F1B),
        ])

    /// Modelled on Xcode's "Default (Dark)".
    static let dark = EditorTheme(
        background: 0x1F1F24,
        foreground: 0xDFDFE0,
        gutterBackground: 0x1F1F24,
        gutterForeground: 0x6C6C71,
        caretLine: 0x23252B,
        whitespace: 0x424248,
        braceMatchBackground: 0x5C4F1E,
        tokens: [
            .comment: .init(color: 0x6C7986),
            .docComment: .init(color: 0x6C7986, italic: true),
            .number: .init(color: 0xD0BF69),
            .keyword: .init(color: 0xFC5FA3, bold: true),
            .type: .init(color: 0x5DD8FF),
            .string: .init(color: 0xFC6A5D),
            .character: .init(color: 0xD0BF69),
            .preprocessor: .init(color: 0xFD8F3F),
            .operator: .init(color: 0xDFDFE0),
            .regex: .init(color: 0xFC6A5D),
            .tag: .init(color: 0xFC5FA3),
            .attribute: .init(color: 0xBF8555),
            .entity: .init(color: 0xD0BF69),
            .heading: .init(color: 0x5DD8FF, bold: true),
            .emphasis: .init(color: 0xDFDFE0, italic: true),
            .code: .init(color: 0xFC6A5D),
            .link: .init(color: 0x6699FF),
            .added: .init(color: 0x67B7A4),
            .deleted: .init(color: 0xFC6A5D),
            .changed: .init(color: 0xD0BF69),
            .error: .init(color: 0xFF4040),
        ])

    /// Mac OS 9 Platinum: Monaco on white, lavender highlight, BBEdit-style colours.
    static let classic = EditorTheme(
        background: 0xFFFFFF,
        foreground: 0x000000,
        gutterBackground: 0xDDDDDD,
        gutterForeground: 0x555555,
        caretLine: 0xEEEEFF,
        whitespace: 0xAAAAAA,
        braceMatchBackground: 0xFFFFCC,
        tokens: [
            .comment: .init(color: 0x990000),
            .docComment: .init(color: 0x990000, italic: true),
            .number: .init(color: 0x990099),
            .keyword: .init(color: 0x0000CC, bold: true),
            .type: .init(color: 0x000099),
            .string: .init(color: 0x006600),
            .character: .init(color: 0x006600),
            .preprocessor: .init(color: 0x996600),
            .operator: .init(color: 0x000000),
            .regex: .init(color: 0x006600),
            .tag: .init(color: 0x0000CC),
            .attribute: .init(color: 0x663399),
            .entity: .init(color: 0x990099),
            .heading: .init(color: 0x333399, bold: true),
            .emphasis: .init(color: 0x000000, italic: true),
            .code: .init(color: 0x006600),
            .link: .init(color: 0x000099),
            .added: .init(color: 0x006600),
            .deleted: .init(color: 0xCC0000),
            .changed: .init(color: 0x996600),
            .error: .init(color: 0xCC0000),
        ],
        selection: 0xCCCCFF,
        caret: 0x000000,
        caretWidth: 1,
        preferredFont: "Monaco")

    static func palette(for theme: Preferences.Theme, dark: Bool) -> EditorTheme {
        switch theme {
        case .classic: .classic
        case .light: .light
        case .dark: .dark
        case .system: dark ? .dark : .light
        }
    }

    static func current(for appearance: NSAppearance) -> EditorTheme {
        palette(for: Preferences.theme, dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }
}
