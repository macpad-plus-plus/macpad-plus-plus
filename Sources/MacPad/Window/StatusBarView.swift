import AppKit

/// Bottom bar showing caret position, language, line ending and encoding —
/// the Notepad++ status bar, styled like Xcode's editor footer.
final class StatusBarView: NSView {
    private let positionLabel = StatusBarView.makeLabel()
    private let lengthLabel = StatusBarView.makeLabel()
    private let languageLabel = StatusBarView.makeLabel()
    private let lineEndingLabel = StatusBarView.makeLabel()
    private let encodingLabel = StatusBarView.makeLabel()
    private var labels: [NSTextField] { [positionLabel, lengthLabel, languageLabel, lineEndingLabel, encodingLabel] }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let separator = NSBox()
        separator.boxType = .separator

        let leading = NSStackView(views: [positionLabel, lengthLabel])
        leading.spacing = 16
        let trailing = NSStackView(views: [languageLabel, lineEndingLabel, encodingLabel])
        trailing.spacing = 16

        let row = NSStackView(views: [leading, NSView(), trailing])
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        row.setHuggingPriority(.defaultLow, for: .horizontal)

        for view in [separator, row] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: separator.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        wantsLayer = true
        applyChrome()
        NotificationCenter.default.addObserver(self, selector: #selector(applyChrome), name: Preferences.didChange, object: nil)
    }

    /// Platinum bar with Chicago labels for the Classic theme; plain otherwise.
    @objc private func applyChrome() {
        let classic = Chrome.isClassic
        layer?.backgroundColor = classic ? Chrome.Platinum.bar.cgColor : nil
        for label in labels {
            label.font = Chrome.font(ofSize: classic ? 10 : NSFont.smallSystemFontSize)
            label.textColor = classic ? .black : .secondaryLabelColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(caret: ScintillaEditor.CaretInfo, language: Language, format: TextFormat) {
        var position = String(localized: "Ln \(caret.line), Col \(caret.column)")
        if caret.selectionCount > 1 {
            position += "  ·  " + String(localized: "Selections: \(caret.selectionCount)")
        } else if caret.selectedCharacters > 0 {
            position += "  ·  " + String(localized: "Sel \(caret.selectedCharacters)")
        }
        positionLabel.stringValue = position
        // Phrased like Notepad++'s status bar, which reads well for any count.
        lengthLabel.stringValue = String(localized: "Length: \(caret.length.formatted())  ·  Lines: \(caret.lineCount.formatted())")
        languageLabel.stringValue = language.name
        lineEndingLabel.stringValue = format.lineEnding.shortName
        encodingLabel.stringValue = format.encoding.displayName
    }

    private static func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
