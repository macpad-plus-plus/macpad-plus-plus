import AppKit
import Scintilla

/// Two read-only editors side by side, one row per `TextComparison` row, so
/// the columns line up and scroll together. Changed lines are tinted red on
/// the left and green on the right, with the words that changed marked more
/// strongly; a line on one side only faces an empty grey filler line.
final class CompareViewController: NSViewController, NSMenuItemValidation {
    struct Source {
        var title: String
        var text: String
        var language: Language
    }

    private let leftEditor = ScintillaEditor(frame: .zero)
    private let rightEditor = ScintillaEditor(frame: .zero)
    private let leftHeader = CompareHeaderView()
    private let rightHeader = CompareHeaderView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let summaryIcon = NSImageView()
    private var comparison = TextComparison(left: "", right: "")
    private var currentChange: Int?
    private var isSyncingScroll = false
    private var appearanceObservation: NSKeyValueObservation?

    /// Called by Compare Again for fresh snapshots of both sides; nil when one was closed.
    var reload: (() -> (Source, Source)?)?

    private enum Marker {
        static let changedBackground: Int32 = 10
        static let fillerBackground: Int32 = 11
        static let changedSymbol: Int32 = 12
    }

    private enum Margin {
        static let numbers = 1
        static let symbols = 3
    }

    private static let emphasisIndicator = 10

    override func loadView() {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        for (header, editor) in [(leftHeader, leftEditor), (rightHeader, rightEditor)] {
            let pane = NSStackView(views: [header, editor])
            pane.orientation = .vertical
            pane.spacing = 0
            pane.alignment = .width
            editor.setContentHuggingPriority(.init(1), for: .vertical)
            split.addArrangedSubview(pane)
            configure(editor)
        }

        let separator = NSBox()
        separator.boxType = .separator
        summaryLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryIcon.symbolConfiguration = .init(pointSize: NSFont.smallSystemFontSize, weight: .regular)
        let summary = NSStackView(views: [summaryIcon, summaryLabel])
        summary.spacing = 5
        summary.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)

        let container = NSView()
        for subview in [split, separator, summary] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.topAnchor.constraint(equalTo: split.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            summary.topAnchor.constraint(equalTo: separator.bottomAnchor),
            summary.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            summary.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            summary.heightAnchor.constraint(equalToConstant: 24),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 480),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
        view = container

        leftEditor.onStatusChange = { [weak self] in self?.syncScroll(from: self?.leftEditor) }
        rightEditor.onStatusChange = { [weak self] in self?.syncScroll(from: self?.rightEditor) }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.applyColors() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(applyColors), name: Preferences.didChange, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Equal columns to start with; the divider can then be dragged.
        if let split = view.subviews.first as? NSSplitView {
            split.setPosition(split.bounds.width / 2, ofDividerAt: 0)
        }
    }

    private func configure(_ editor: ScintillaEditor) {
        editor.usesLineNumberMargin = false
        editor.wrapsLines = false
        editor.send(SCI_SETMARGINS, 4)
        editor.send(SCI_SETMARGINWIDTHN, 0, 0)
        editor.send(SCI_SETMARGINWIDTHN, 2, 0)
        editor.send(SCI_SETMARGINTYPEN, Margin.numbers, Int(SC_MARGIN_RTEXT))
        editor.send(SCI_SETMARGINMASKN, Margin.numbers, 0)
        editor.send(SCI_SETMARGINTYPEN, Margin.symbols, Int(SC_MARGIN_SYMBOL))
        editor.send(SCI_SETMARGINMASKN, Margin.symbols, 1 << Int(Marker.changedSymbol))
        editor.send(SCI_SETMARGINWIDTHN, Margin.symbols, 14)
        editor.send(SCI_MARKERDEFINE, Int(Marker.changedBackground), Int(SC_MARK_BACKGROUND))
        editor.send(SCI_MARKERDEFINE, Int(Marker.fillerBackground), Int(SC_MARK_BACKGROUND))
        let symbol = editor === leftEditor ? "−" : "+"
        editor.send(SCI_MARKERDEFINE, Int(Marker.changedSymbol), Int(SC_MARK_CHARACTER) + Int(symbol.unicodeScalars.first!.value))
        editor.send(SCI_INDICSETSTYLE, Self.emphasisIndicator, Int(INDIC_FULLBOX))
        editor.send(SCI_INDICSETUNDER, Self.emphasisIndicator, 1)
        editor.send(SCI_INDICSETOUTLINEALPHA, Self.emphasisIndicator, 0)
    }

    // MARK: Content

    func show(left: Source, right: Source) {
        loadViewIfNeeded()
        comparison = TextComparison(left: left.text, right: right.text)
        currentChange = nil
        leftHeader.title = left.title
        rightHeader.title = right.title
        // One language colours both columns; prefer whichever side has one.
        let language = left.language == .normalText ? right.language : left.language
        fill(leftEditor, lines: TextComparison.lines(left.text), side: \.left, language: language)
        fill(rightEditor, lines: TextComparison.lines(right.text), side: \.right, language: language)
        applyColors()
        updateSummary()
    }

    private func fill(_ editor: ScintillaEditor, lines: [String], side: KeyPath<TextComparison.Row, TextComparison.Cell?>,
                      language: Language) {
        let isLeft = editor === leftEditor
        let rows = comparison.rows
        let text = rows.map { row in row[keyPath: side].map { lines[$0.line] } ?? "" }.joined(separator: "\n")
        editor.isReadOnly = false
        editor.load(utf8: Data(text.utf8), lineEnding: .lf)
        editor.setLanguage(language)
        editor.isReadOnly = true

        editor.send(SCI_SETINDICATORCURRENT, Self.emphasisIndicator)
        var widest = 1
        for (index, row) in rows.enumerated() {
            guard let cell = row[keyPath: side] else {
                editor.send(SCI_MARKERADD, index, Int(Marker.fillerBackground))
                continue
            }
            let number = String(cell.line + 1)
            widest = max(widest, number.count)
            editor.send(SCI_MARGINSETTEXT, index, string: number)
            editor.send(SCI_MARGINSETSTYLE, index, Int(STYLE_LINENUMBER))
            let differs = row.kind == .changed || row.kind == (isLeft ? .removed : .added)
            if differs {
                editor.send(SCI_MARKERADD, index, Int(Marker.changedBackground))
                editor.send(SCI_MARKERADD, index, Int(Marker.changedSymbol))
            }
            let start = editor.send(SCI_POSITIONFROMLINE, index)
            for range in cell.emphasis {
                editor.send(SCI_INDICATORFILLRANGE, start + range.lowerBound, range.count)
            }
        }
        let width = editor.send(SCI_TEXTWIDTH, Int(STYLE_LINENUMBER), string: String(repeating: "9", count: max(3, widest)))
        editor.send(SCI_SETMARGINWIDTHN, Margin.numbers, width + 10)
    }

    /// Tints computed from the editor background, so they suit every theme.
    @objc private func applyColors() {
        for editor in [leftEditor, rightEditor] {
            let isLeft = editor === leftEditor
            let appearance = editor.effectiveAppearance
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let background = Self.color(EditorTheme.current(for: appearance).background)
            var accent = NSColor.systemGreen, filler = NSColor.gray
            appearance.performAsCurrentDrawingAppearance {
                accent = (isLeft ? NSColor.systemRed : NSColor.systemGreen).usingColorSpace(.sRGB) ?? accent
                filler = NSColor.labelColor.usingColorSpace(.sRGB) ?? filler
            }
            let tint = background.blended(withFraction: dark ? 0.2 : 0.14, of: accent) ?? background
            let strong = background.blended(withFraction: dark ? 0.42 : 0.32, of: accent) ?? background
            let grey = background.blended(withFraction: dark ? 0.06 : 0.05, of: filler) ?? background
            editor.send(SCI_MARKERSETBACK, Int(Marker.changedBackground), Self.bgr(tint))
            editor.send(SCI_MARKERSETBACK, Int(Marker.fillerBackground), Self.bgr(grey))
            editor.send(SCI_MARKERSETFORE, Int(Marker.changedSymbol), Self.bgr(accent))
            editor.send(SCI_INDICSETFORE, Self.emphasisIndicator, Self.bgr(strong))
            editor.send(SCI_INDICSETALPHA, Self.emphasisIndicator, 255)
        }
    }

    private static func color(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// Scintilla wants 0xBBGGRR.
    private static func bgr(_ color: NSColor) -> Int {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return r | g << 8 | b << 16
    }

    // MARK: Scrolling

    /// Both columns have one line per row, so matching the first visible line
    /// (and the zoom) keeps them aligned.
    private func syncScroll(from source: ScintillaEditor?) {
        guard !isSyncingScroll, let source else { return }
        let other = source === leftEditor ? rightEditor : leftEditor
        isSyncingScroll = true
        defer { isSyncingScroll = false }
        let zoom = source.send(SCI_GETZOOM)
        if other.send(SCI_GETZOOM) != zoom { other.send(SCI_SETZOOM, zoom) }
        let first = source.send(SCI_GETFIRSTVISIBLELINE)
        if other.send(SCI_GETFIRSTVISIBLELINE) != first { other.send(SCI_SETFIRSTVISIBLELINE, first) }
    }

    // MARK: Navigation

    @objc func nextDifference(_ sender: Any?) {
        let count = comparison.changes.count
        guard count > 0 else { return NSSound.beep() }
        go(toChange: currentChange.map { ($0 + 1) % count } ?? 0)
    }

    @objc func previousDifference(_ sender: Any?) {
        let count = comparison.changes.count
        guard count > 0 else { return NSSound.beep() }
        go(toChange: currentChange.map { ($0 + count - 1) % count } ?? count - 1)
    }

    /// Compares fresh copies of the same two documents.
    @objc func compareAgain(_ sender: Any?) {
        guard let sources = reload?() else {
            let alert = NSAlert()
            alert.messageText = String(localized: "One of the compared files was closed.")
            if let window = view.window { alert.beginSheetModal(for: window) }
            return
        }
        let first = leftEditor.send(SCI_GETFIRSTVISIBLELINE)
        show(left: sources.0, right: sources.1)
        leftEditor.send(SCI_SETFIRSTVISIBLELINE, first)
    }

    private func go(toChange index: Int) {
        currentChange = index
        let row = comparison.changes[index]
        for editor in [leftEditor, rightEditor] {
            editor.send(SCI_GOTOLINE, row)
        }
        let first = max(0, row - leftEditor.send(SCI_LINESONSCREEN) / 2)
        leftEditor.send(SCI_SETFIRSTVISIBLELINE, first)
        rightEditor.send(SCI_SETFIRSTVISIBLELINE, first)
        updateSummary()
    }

    private func updateSummary() {
        guard !comparison.isIdentical else {
            summaryIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            summaryIcon.contentTintColor = .systemGreen
            summaryIcon.isHidden = false
            summaryLabel.stringValue = String(localized: "The files are identical.")
            return
        }
        summaryIcon.isHidden = true
        let total = comparison.changes.count
        let position = currentChange.map { String(localized: "Difference \($0 + 1) of \(total)") }
            ?? String(localized: "\(total) differences")
        let counts = String(localized: "\(comparison.changed) changed, \(comparison.removed) only on the left, \(comparison.added) only on the right")
        summaryLabel.stringValue = position + "  ·  " + counts
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(nextDifference(_:)), #selector(previousDifference(_:)):
            return !comparison.isIdentical
        default:
            return true
        }
    }
}

/// A file name above each column.
private final class CompareHeaderView: NSView {
    private let label = NSTextField(labelWithString: "")

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let icon = NSImageView(image: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [icon, label])
        row.spacing = 5
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        let separator = NSBox()
        separator.boxType = .separator
        for view in [row, separator] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
