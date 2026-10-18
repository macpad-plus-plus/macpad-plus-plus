import AppKit
import Scintilla

/// Swift-facing wrapper around Scintilla's Cocoa view.
///
/// Owns editor configuration (margins, folding, theme, lexer) and exposes the
/// handful of events the rest of the app cares about as closures.
final class ScintillaEditor: ScintillaView {
    private enum Margin {
        static let lineNumbers = 0
        static let symbols = 1
        static let folding = 2
    }

    /// Called with `true` when the buffer diverges from the last save point.
    var onDirtyChange: ((Bool) -> Void)?
    /// Called when caret, selection or content changes.
    var onStatusChange: (() -> Void)?
    /// Called after text is inserted or deleted.
    var onTextChange: (() -> Void)?
    /// Posted (object: the editor) after text or language changes, for observers
    /// such as the function list.
    static let contentDidChange = Notification.Name("MacPadEditorContentDidChange")

    /// Incremented on every text change; used to skip redundant backups.
    private(set) var contentVersion = 0

    private(set) var language = Language.normalText
    private var lineNumberDigits = 0
    private var settings = Preferences.editor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
        NotificationCenter.default.addObserver(
            self, selector: #selector(systemColorsDidChange),
            name: NSColor.systemColorsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesDidChange),
            name: Preferences.didChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyScrollers),
            name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Messaging

    @discardableResult
    func send(_ message: Int32, _ wParam: Int = 0, _ lParam: Int = 0) -> Int {
        self.message(UInt32(message), wParam: UInt(bitPattern: wParam), lParam: lParam)
    }

    @discardableResult
    func send(_ message: Int32, _ wParam: Int = 0, string: String) -> Int {
        string.withCString { send(message, wParam, Int(bitPattern: $0)) }
    }

    // MARK: Configuration

    private func configure() {
        send(SCI_SETCODEPAGE, Int(SC_CP_UTF8))
        send(SCI_SETSCROLLWIDTH, 1)
        send(SCI_SETSCROLLWIDTHTRACKING, 1)
        send(SCI_SETCARETLINEVISIBLEALWAYS, 1)

        // Multiple carets and Option-drag column selection, as in Notepad++.
        send(SCI_SETMULTIPLESELECTION, 1)
        send(SCI_SETADDITIONALSELECTIONTYPING, 1)
        send(SCI_SETMULTIPASTE, Int(SC_MULTIPASTE_EACH))
        send(SCI_SETVIRTUALSPACEOPTIONS, Int(SCVS_RECTANGULARSELECTION))

        send(SCI_SETMARGINTYPEN, Margin.lineNumbers, Int(SC_MARGIN_NUMBER))
        send(SCI_SETMARGINWIDTHN, Margin.symbols, 0)
        send(SCI_SETMARGINTYPEN, Margin.folding, Int(SC_MARGIN_SYMBOL))
        send(SCI_SETMARGINMASKN, Margin.folding, Int(SC_MASK_FOLDERS))
        send(SCI_SETMARGINSENSITIVEN, Margin.folding, 1)
        send(SCI_SETMARGINWIDTHN, Margin.folding, 14)
        send(SCI_SETMARGINLEFT, 0, 4)
        updateScrollerMargin()

        // Disclosure-style fold markers read more naturally on macOS than
        // Notepad++'s box tree.
        let markers: [(Int32, Int32)] = [
            (SC_MARKNUM_FOLDEROPEN, SC_MARK_ARROWDOWN),
            (SC_MARKNUM_FOLDER, SC_MARK_ARROW),
            (SC_MARKNUM_FOLDERSUB, SC_MARK_EMPTY),
            (SC_MARKNUM_FOLDERTAIL, SC_MARK_EMPTY),
            (SC_MARKNUM_FOLDEREND, SC_MARK_ARROW),
            (SC_MARKNUM_FOLDEROPENMID, SC_MARK_ARROWDOWN),
            (SC_MARKNUM_FOLDERMIDTAIL, SC_MARK_EMPTY),
        ]
        for (marker, symbol) in markers {
            send(SCI_MARKERDEFINE, Int(marker), Int(symbol))
        }
        send(SCI_SETAUTOMATICFOLD, Int(SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE))
        send(SCI_SETFOLDFLAGS, Int(SC_FOLDFLAG_LINEAFTER_CONTRACTED))

        wrapsLines = settings.wrapLines
        applySettings()
    }

    private var scrollerMargin = -1

    /// Scintilla draws text across the whole clip view, including the strip under
    /// the vertical scroller (with both overlay and always-shown scrollers), so the
    /// end of long lines would hide behind it. Reserve the covered width as a
    /// right text margin, measured from the actual layout.
    @objc func updateScrollerMargin() {
        var covered: CGFloat = 0
        if let scroller = scrollView.verticalScroller, scrollView.hasVerticalScroller, !scroller.isHidden {
            let overlap = scrollView.contentView.frame.maxX - scroller.frame.minX
            // Overlay scrollers widen while in use; reserve their widest form.
            let width = scrollView.scrollerStyle == .overlay
                ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
                : scroller.frame.width
            covered = overlap > 0 ? max(overlap, width) : 0
        }
        let margin = Int(covered.rounded(.up)) + 2
        guard margin != scrollerMargin else { return }
        scrollerMargin = margin
        send(SCI_SETMARGINRIGHT, 0, margin)
    }

    override func layout() {
        super.layout()
        updateScrollerMargin()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        updateScrollerMargin()
    }

    /// Applies the non-colour editor preferences, then the theme.
    private func applySettings() {
        send(SCI_SETTABWIDTH, settings.tabWidth)
        send(SCI_SETUSETABS, settings.insertSpaces ? 0 : 1)
        send(SCI_SETINDENTATIONGUIDES, Int(settings.showIndentGuides ? SC_IV_LOOKBOTH : SC_IV_NONE))
        applyScrollers()
        applyTheme()
    }

    /// Platinum scrollers for the Classic theme; the system's otherwise.
    @objc private func applyScrollers() {
        let classic = Chrome.isClassic
        if (scrollView.verticalScroller is ClassicScroller) != classic {
            scrollView.verticalScroller = classic ? ClassicScroller() : NSScroller()
            scrollView.horizontalScroller = classic ? ClassicScroller() : NSScroller()
        }
        scrollView.scrollerStyle = classic ? .legacy : NSScroller.preferredScrollerStyle
        updateScrollerMargin()
    }

    @objc private func preferencesDidChange() {
        let updated = Preferences.editor
        guard updated != settings else { return }
        settings = updated
        applySettings()
    }

    func setLanguage(_ language: Language) {
        self.language = language
        let lexer = CreateLexer(language.lexer)
        send(SCI_SETILEXER, 0, Int(bitPattern: lexer))
        for (index, words) in language.keywords {
            send(SCI_SETKEYWORDS, index, string: words)
        }
        for (key, value) in language.properties {
            setLexerProperty(key, value: value)
        }
        applyTheme()
        send(SCI_COLOURISE, 0, -1)
        onStatusChange?()
        NotificationCenter.default.post(name: Self.contentDidChange, object: self)
    }

    // MARK: Theme

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    @objc private func systemColorsDidChange() {
        applyTheme()
    }

    private static let automaticFont: String = NSFont(name: "SF Mono", size: 13) != nil ? "SF Mono" : "Menlo"

    func applyTheme() {
        let theme = EditorTheme.current(for: effectiveAppearance)
        let defaultStyle = Int(STYLE_DEFAULT)
        let fontName = settings.fontName.isEmpty ? (theme.preferredFont ?? Self.automaticFont) : settings.fontName

        send(SCI_STYLESETFONT, defaultStyle, string: fontName)
        send(SCI_STYLESETSIZEFRACTIONAL, defaultStyle, Int(settings.fontSize * Double(SC_FONT_SIZE_MULTIPLIER)))
        send(SCI_STYLESETFORE, defaultStyle, bgr(theme.foreground))
        send(SCI_STYLESETBACK, defaultStyle, bgr(theme.background))
        send(SCI_STYLECLEARALL)

        for (kind, styleIDs) in language.styles {
            guard let token = theme.tokens[kind] else { continue }
            for style in styleIDs.map(Int.init) {
                send(SCI_STYLESETFORE, style, bgr(token.color))
                send(SCI_STYLESETBOLD, style, token.bold ? 1 : 0)
                send(SCI_STYLESETITALIC, style, token.italic ? 1 : 0)
            }
        }

        let lineNumberStyle = Int(STYLE_LINENUMBER)
        send(SCI_STYLESETFORE, lineNumberStyle, bgr(theme.gutterForeground))
        send(SCI_STYLESETBACK, lineNumberStyle, bgr(theme.gutterBackground))
        send(SCI_STYLESETSIZEFRACTIONAL, lineNumberStyle, Int((settings.fontSize - 2) * Double(SC_FONT_SIZE_MULTIPLIER)))
        send(SCI_SETFOLDMARGINCOLOUR, 1, bgr(theme.gutterBackground))
        send(SCI_SETFOLDMARGINHICOLOUR, 1, bgr(theme.gutterBackground))
        for marker in SC_MARKNUM_FOLDEREND...SC_MARKNUM_FOLDEROPEN {
            send(SCI_MARKERSETFORE, Int(marker), bgr(theme.gutterForeground))
            send(SCI_MARKERSETBACK, Int(marker), bgr(theme.gutterForeground))
        }

        send(SCI_STYLESETBACK, Int(STYLE_BRACELIGHT), bgr(theme.braceMatchBackground))
        send(SCI_STYLESETBOLD, Int(STYLE_BRACELIGHT), 1)
        send(SCI_STYLESETFORE, Int(STYLE_BRACEBAD), bgr(theme.tokens[.error]?.color ?? 0xFF0000))
        send(SCI_STYLESETFORE, Int(STYLE_INDENTGUIDE), bgr(theme.whitespace))

        // Caret and selection follow the user's accent and highlight colours,
        // unless the theme fixes them.
        let caret = theme.caret.map { bgr($0) | 0xFF00_0000 } ?? rgba(.controlAccentColor)
        let selection = theme.selection.map { bgr($0) | 0xFF00_0000 } ?? rgba(.selectedTextBackgroundColor)
        send(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_CARET), caret)
        if settings.highlightCurrentLine {
            send(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_CARET_LINE_BACK), bgr(theme.caretLine) | 0xFF00_0000)
        } else {
            send(SCI_RESETELEMENTCOLOUR, Int(SC_ELEMENT_CARET_LINE_BACK))
        }
        send(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_SELECTION_BACK), selection)
        send(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_SELECTION_ADDITIONAL_BACK), rgba(.unemphasizedSelectedTextBackgroundColor))
        send(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_SELECTION_SECONDARY_BACK), rgba(.unemphasizedSelectedTextBackgroundColor))
        send(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_SELECTION_INACTIVE_BACK), rgba(.unemphasizedSelectedTextBackgroundColor))
        send(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_WHITE_SPACE), bgr(theme.whitespace) | 0xFF00_0000)
        send(SCI_SETCARETWIDTH, theme.caretWidth)
        configureFindIndicator(color: .findHighlightColor)

        updateLineNumberWidth(force: true)
    }

    /// Scintilla expects colours as 0xBBGGRR.
    private func bgr(_ rgb: UInt32) -> Int {
        Int((rgb & 0xFF) << 16 | (rgb & 0xFF00) | (rgb >> 16) & 0xFF)
    }

    /// Resolves a dynamic system colour for this view's appearance as 0xAABBGGRR.
    func rgba(_ color: NSColor) -> Int {
        var value = 0
        effectiveAppearance.performAsCurrentDrawingAppearance {
            guard let c = color.usingColorSpace(.sRGB) else { return }
            let r = Int((c.redComponent * 255).rounded())
            let g = Int((c.greenComponent * 255).rounded())
            let b = Int((c.blueComponent * 255).rounded())
            let a = Int((c.alphaComponent * 255).rounded())
            value = r | g << 8 | b << 16 | a << 24
        }
        return value
    }

    private func updateLineNumberWidth(force: Bool = false) {
        let digits = max(3, String(send(SCI_GETLINECOUNT)).count)
        guard force || digits != lineNumberDigits else { return }
        lineNumberDigits = digits
        let width = send(SCI_TEXTWIDTH, Int(STYLE_LINENUMBER), string: String(repeating: "9", count: digits))
        send(SCI_SETMARGINWIDTHN, Margin.lineNumbers, settings.showLineNumbers ? width + 12 : 0)
    }

    // MARK: Content

    /// Replaces the buffer with UTF-8 bytes, resetting undo history and the save point.
    func load(utf8 data: Data, lineEnding: LineEnding) {
        send(SCI_CLEARALL)
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            if let base = bytes.baseAddress {
                send(SCI_APPENDTEXT, bytes.count, Int(bitPattern: base))
            }
        }
        send(SCI_SETEOLMODE, lineEnding.scintillaMode)
        send(SCI_EMPTYUNDOBUFFER)
        send(SCI_SETSAVEPOINT)
        send(SCI_GOTOPOS, 0)
        updateLineNumberWidth()
    }

    /// The buffer as UTF-8 bytes, including any embedded NULs.
    func utf8Text() -> Data {
        let length = send(SCI_GETLENGTH)
        guard length > 0, let pointer = UnsafeRawPointer(bitPattern: send(SCI_GETCHARACTERPOINTER)) else {
            return Data()
        }
        return Data(bytes: pointer, count: length)
    }

    /// The first line of the buffer (up to 256 bytes), for shebang detection.
    func firstLine() -> String {
        let end = min(send(SCI_GETLINEENDPOSITION, 0), 256)
        guard end > 0, let pointer = UnsafeRawPointer(bitPattern: send(SCI_GETRANGEPOINTER, 0, end)) else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: pointer, count: end), as: UTF8.self)
    }

    /// Replaces the whole buffer as one undoable edit, leaving the save point
    /// where it was (so restored backups show as unsaved changes).
    func replaceText(utf8 data: Data) {
        send(SCI_TARGETWHOLEDOCUMENT)
        _ = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            send(SCI_REPLACETARGET, bytes.count, Int(bitPattern: bytes.baseAddress))
        }
        send(SCI_GOTOPOS, 0)
    }

    struct ViewState: Codable, Equatable {
        var anchor = 0
        var caret = 0
        var firstVisibleLine = 0
    }

    var viewState: ViewState {
        get {
            ViewState(anchor: send(SCI_GETANCHOR), caret: send(SCI_GETCURRENTPOS), firstVisibleLine: send(SCI_GETFIRSTVISIBLELINE))
        }
        set {
            let length = send(SCI_GETLENGTH)
            send(SCI_SETSEL, min(newValue.anchor, length), min(newValue.caret, length))
            send(SCI_SETFIRSTVISIBLELINE, newValue.firstVisibleLine)
        }
    }

    func markSavePoint() {
        send(SCI_SETSAVEPOINT)
    }

    func setLineEnding(_ lineEnding: LineEnding, convertExisting: Bool) {
        send(SCI_SETEOLMODE, lineEnding.scintillaMode)
        if convertExisting {
            send(SCI_CONVERTEOLS, lineEnding.scintillaMode)
        }
    }

    // MARK: Caret

    struct CaretInfo {
        var line: Int
        var column: Int
        var selectedCharacters: Int
        var selectionCount: Int
        var length: Int
        var lineCount: Int
    }

    var caretInfo: CaretInfo {
        let position = send(SCI_GETCURRENTPOS)
        let line = send(SCI_LINEFROMPOSITION, position)
        var selected = 0
        let selections = send(SCI_GETSELECTIONS)
        for index in 0..<selections {
            let start = send(SCI_GETSELECTIONNSTART, index)
            let end = send(SCI_GETSELECTIONNEND, index)
            selected += send(SCI_COUNTCHARACTERS, start, end)
        }
        return CaretInfo(
            line: line + 1,
            column: send(SCI_GETCOLUMN, position) + 1,
            selectedCharacters: selected,
            selectionCount: selections,
            length: send(SCI_GETLENGTH),
            lineCount: send(SCI_GETLINECOUNT))
    }

    /// Moves the caret to a 1-based line and column, scrolling it to the middle.
    func goTo(line: Int, column: Int = 1) {
        let lineIndex = min(max(line, 1), send(SCI_GETLINECOUNT)) - 1
        let position = send(SCI_FINDCOLUMN, lineIndex, max(column, 1) - 1)
        send(SCI_ENSUREVISIBLEENFORCEPOLICY, lineIndex)
        send(SCI_GOTOPOS, position)
        send(SCI_SETFIRSTVISIBLELINE, max(0, send(SCI_VISIBLEFROMDOCLINE, lineIndex) - send(SCI_LINESONSCREEN) / 2))
    }

    // MARK: View options

    var wrapsLines: Bool {
        get { send(SCI_GETWRAPMODE) != Int(SC_WRAP_NONE) }
        set { send(SCI_SETWRAPMODE, Int(newValue ? SC_WRAP_WORD : SC_WRAP_NONE)) }
    }

    var showsWhitespace: Bool {
        get { send(SCI_GETVIEWWS) != Int(SCWS_INVISIBLE) }
        set { send(SCI_SETVIEWWS, Int(newValue ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE)) }
    }

    var showsLineEndings: Bool {
        get { send(SCI_GETVIEWEOL) != 0 }
        set { send(SCI_SETVIEWEOL, newValue ? 1 : 0) }
    }

    func zoomIn() { send(SCI_ZOOMIN) }
    func zoomOut() { send(SCI_ZOOMOUT) }
    func resetZoom() { send(SCI_SETZOOM, 0) }

    // MARK: Notifications

    override func notification(_ notification: UnsafeMutablePointer<SCNotification>!) {
        super.notification(notification)
        let scn = notification.pointee
        switch Int32(bitPattern: scn.nmhdr.code) {
        case SCN_SAVEPOINTLEFT:
            onDirtyChange?(true)
        case SCN_SAVEPOINTREACHED:
            onDirtyChange?(false)
        case SCN_UPDATEUI:
            // Scrollers appear and disappear as the content grows or shrinks.
            updateScrollerMargin()
            highlightMatchingBrace()
            onStatusChange?()
        case SCN_MODIFIED where scn.modificationType & Int32(SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT) != 0:
            contentVersion += 1
            if scn.linesAdded != 0 {
                updateLineNumberWidth()
            }
            onTextChange?()
            NotificationCenter.default.post(name: Self.contentDidChange, object: self)
        default:
            break
        }
    }

    private func highlightMatchingBrace() {
        var position = send(SCI_GETCURRENTPOS)
        var match = Int(INVALID_POSITION)
        for candidate in [position, position - 1] where candidate >= 0 {
            let character = UInt8(truncatingIfNeeded: send(SCI_GETCHARAT, candidate))
            if "()[]{}".utf8.contains(character) {
                position = candidate
                match = send(SCI_BRACEMATCH, candidate, 0)
                if match == Int(INVALID_POSITION) {
                    send(SCI_BRACEBADLIGHT, candidate)
                    return
                }
                send(SCI_BRACEHIGHLIGHT, position, match)
                return
            }
        }
        send(SCI_BRACEHIGHLIGHT, Int(INVALID_POSITION), Int(INVALID_POSITION))
    }
}
