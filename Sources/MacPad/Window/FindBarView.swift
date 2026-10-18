import AppKit

@MainActor
protocol FindBarDelegate: AnyObject {
    func findBarQueryDidChange(_ findBar: FindBarView)
    func findBar(_ findBar: FindBarView, findForward forward: Bool)
    func findBarReplace(_ findBar: FindBarView)
    func findBarReplaceAll(_ findBar: FindBarView)
    func findBarDismiss(_ findBar: FindBarView)
}

/// Inline find/replace bar shown above the editor, in the style of Xcode and Safari.
///
/// Row 1: mode pop-up, search field, option toggles, match count, previous/next, Done.
/// Row 2 (replace mode): replacement field, Replace, Replace All.
final class FindBarView: NSVisualEffectView, NSSearchFieldDelegate, NSTextFieldDelegate {
    enum Mode: Int {
        case find, replace
    }

    weak var delegate: FindBarDelegate?

    private let modePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    let searchField = NSSearchField()
    let replaceField = NSTextField()
    private let matchCaseButton = FindBarView.makeToggle(title: "Aa", toolTip: String(localized: "Match Case"))
    private let wholeWordButton = FindBarView.makeToggle(title: "W", toolTip: String(localized: "Whole Word"))
    private let regexButton = FindBarView.makeToggle(title: ".*", toolTip: String(localized: "Regular Expression (\\1 or $1 in replacement)"))
    private let statusLabel = NSTextField(labelWithString: "")
    private let navigation = NSSegmentedControl()
    private let replaceRow: NSStackView
    /// Platinum backdrop shown instead of the vibrant material in the Classic theme.
    private let classicBackground = NSView()
    private var chromeControls: [NSControl] = []

    var mode: Mode = .find {
        didSet {
            modePopUp.selectItem(at: mode.rawValue)
            replaceRow.isHidden = mode == .find
        }
    }

    var options: SearchOptions {
        SearchOptions(
            query: searchField.stringValue,
            matchCase: matchCaseButton.state == .on,
            wholeWord: wholeWordButton.state == .on,
            regex: regexButton.state == .on)
    }

    var query: String {
        get { searchField.stringValue }
        set { searchField.stringValue = newValue }
    }

    var replacement: String { replaceField.stringValue }

    override init(frame frameRect: NSRect) {
        let replaceButton = NSButton(title: String(localized: "Replace"), target: nil, action: nil)
        let replaceAllButton = NSButton(title: String(localized: "All"), target: nil, action: nil)
        let replaceSpacer = NSView()
        let trailingSpacer = NSView()
        trailingSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        replaceRow = NSStackView(views: [replaceSpacer, replaceField, replaceButton, replaceAllButton, trailingSpacer])
        super.init(frame: frameRect)

        material = .titlebar
        blendingMode = .withinWindow

        modePopUp.addItems(withTitles: [String(localized: "Find"), String(localized: "Replace")])
        modePopUp.target = self
        modePopUp.action = #selector(modeChanged(_:))

        searchField.placeholderString = String(localized: "Find")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        searchField.setContentHuggingPriority(.init(100), for: .horizontal)
        searchField.target = self
        searchField.action = #selector(queryChanged(_:))

        for toggle in [matchCaseButton, wholeWordButton, regexButton] {
            toggle.target = self
            toggle.action = #selector(queryChanged(_:))
        }

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        statusLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        navigation.segmentCount = 2
        navigation.trackingMode = .momentary
        navigation.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: String(localized: "Previous")), forSegment: 0)
        navigation.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: String(localized: "Next")), forSegment: 1)
        navigation.setToolTip(String(localized: "Find Previous (⇧⌘G)"), forSegment: 0)
        navigation.setToolTip(String(localized: "Find Next (⌘G)"), forSegment: 1)
        navigation.target = self
        navigation.action = #selector(navigate(_:))

        let doneButton = NSButton(title: String(localized: "Done"), target: self, action: #selector(dismiss(_:)))

        replaceField.placeholderString = String(localized: "Replace")
        replaceField.delegate = self
        replaceButton.target = self
        replaceButton.action = #selector(replace(_:))
        replaceButton.toolTip = String(localized: "Replace and find next")
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAll(_:))
        replaceAllButton.toolTip = String(localized: "Replace all matches")

        let findRow = NSStackView(views: [
            modePopUp, searchField, matchCaseButton, wholeWordButton, regexButton, statusLabel, navigation, doneButton,
        ])
        for row in [findRow, replaceRow] {
            row.spacing = 6
            row.setHuggingPriority(.defaultLow, for: .horizontal)
        }
        findRow.setCustomSpacing(2, after: matchCaseButton)
        findRow.setCustomSpacing(2, after: wholeWordButton)
        findRow.setCustomSpacing(10, after: regexButton)

        chromeControls = [modePopUp, searchField, replaceField, replaceButton, replaceAllButton, doneButton, navigation, statusLabel]
        for control in chromeControls {
            control.controlSize = .small
        }

        let rows = NSStackView(views: [findRow, replaceRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        rows.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

        let separator = NSBox()
        separator.boxType = .separator

        classicBackground.wantsLayer = true
        classicBackground.layer?.backgroundColor = Chrome.Platinum.bar.cgColor
        for view in [classicBackground, rows, separator] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            classicBackground.topAnchor.constraint(equalTo: topAnchor),
            classicBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            classicBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            classicBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: rows.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            findRow.widthAnchor.constraint(equalTo: rows.widthAnchor, constant: -16),
            replaceRow.widthAnchor.constraint(equalTo: findRow.widthAnchor),
            // Line the replace field up under the search field.
            replaceSpacer.widthAnchor.constraint(equalTo: modePopUp.widthAnchor),
            replaceField.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            replaceField.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
        ])
        replaceRow.isHidden = true
        applyChrome()
        NotificationCenter.default.addObserver(self, selector: #selector(applyChrome), name: Preferences.didChange, object: nil)
    }

    @objc private func applyChrome() {
        let classic = Chrome.isClassic
        classicBackground.isHidden = !classic
        for control in chromeControls where control !== searchField && control !== replaceField {
            control.font = Chrome.font(ofSize: classic ? 10 : NSFont.smallSystemFontSize)
        }
        searchField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        replaceField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Status

    enum Status {
        case none
        case matches(current: Int?, total: Int, truncated: Bool)
        case notFound
        case invalidPattern
        case replaced(Int)
    }

    func show(_ status: Status) {
        statusLabel.textColor = .secondaryLabelColor
        switch status {
        case .none:
            statusLabel.stringValue = ""
        case let .matches(current, total, truncated):
            let totalText = truncated ? "\(total.formatted())+" : total.formatted()
            if let current {
                statusLabel.stringValue = String(localized: "\(current.formatted()) of \(totalText)")
            } else {
                statusLabel.stringValue = String(localized: "Matches: \(totalText)")
            }
        case .notFound:
            statusLabel.stringValue = String(localized: "Not found")
            statusLabel.textColor = .systemRed
        case .invalidPattern:
            statusLabel.stringValue = String(localized: "Invalid pattern")
            statusLabel.textColor = .systemRed
        case let .replaced(count):
            statusLabel.stringValue = String(localized: "Replaced: \(count.formatted())")
        }
    }

    // MARK: Actions

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            mode = Mode(rawValue: sender.indexOfSelectedItem) ?? .find
            superview?.layoutSubtreeIfNeeded()
        }
    }

    @objc private func queryChanged(_ sender: Any?) {
        delegate?.findBarQueryDidChange(self)
    }

    @objc private func navigate(_ sender: NSSegmentedControl) {
        delegate?.findBar(self, findForward: sender.selectedSegment == 1)
    }

    @objc private func replace(_ sender: Any?) {
        delegate?.findBarReplace(self)
    }

    @objc private func replaceAll(_ sender: Any?) {
        delegate?.findBarReplaceAll(self)
    }

    @objc private func dismiss(_ sender: Any?) {
        delegate?.findBarDismiss(self)
    }

    // MARK: Field editor commands

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if control === replaceField {
                delegate?.findBarReplace(self)
            } else {
                let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                delegate?.findBar(self, findForward: !backwards)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            delegate?.findBarDismiss(self)
            return true
        case #selector(NSResponder.insertTab(_:)) where control === searchField && mode == .replace:
            window?.makeFirstResponder(replaceField)
            return true
        default:
            return false
        }
    }

    private static func makeToggle(title: String, toolTip: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        return button
    }
}
