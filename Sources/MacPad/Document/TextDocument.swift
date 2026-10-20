import AppKit

/// A text file. Scintilla owns the buffer and its undo history; the document
/// owns the on-disk format (encoding, line endings) and the file lifecycle.
final class TextDocument: NSDocument {
    var format = Preferences.newDocumentFormat

    private(set) weak var editor: ScintillaEditor?
    /// File contents read before the editor exists (the normal open path).
    private var pendingText: TextCodec.Decoded?
    /// Set while the "changed by another app" sheet is up, so it is asked once.
    var isPresentingExternalChangeAlert = false

    // MARK: Tab

    /// N in "Untitled N", given the first time an untitled document is named:
    /// the lowest number no other open document uses, as in Notepad++.
    var untitledNumber: Int?
    /// A name chosen with Rename, for an untitled document.
    var customName: String? {
        didSet { tabDidChange() }
    }
    /// Kept at the start of the tab bar.
    var isPinned = false {
        didSet { tabDidChange() }
    }
    var tabColor: TabColor? {
        didSet { tabDidChange() }
    }
    /// Editing is locked; the text can still be saved, searched and copied.
    var isReadOnly = false {
        didSet {
            editor?.isReadOnly = isReadOnly || isFollowing
            tabDidChange()
        }
    }
    /// The file is being followed like `tail -f` (see EditorViewController+Follow).
    var isFollowing = false {
        didSet {
            editor?.isReadOnly = isReadOnly || isFollowing
            tabDidChange()
        }
    }

    /// Posted (object: the document) when its name, pin, color or modes change.
    static let tabDidChangeNotification = Notification.Name("MacPadDocumentTabDidChange")

    private func tabDidChange() {
        NotificationCenter.default.post(name: Self.tabDidChangeNotification, object: self)
    }

    override var displayName: String! {
        get {
            if fileURL != nil { return super.displayName }
            if let customName { return customName }
            let number = untitledNumber ?? assignUntitledNumber()
            return number == 1 ? String(localized: "Untitled") : String(localized: "Untitled \(number)")
        }
        set { super.displayName = newValue }
    }

    private func assignUntitledNumber() -> Int {
        let used = NSDocumentController.shared.documents.compactMap { document -> Int? in
            guard let other = document as? TextDocument, other !== self, other.fileURL == nil, other.customName == nil else { return nil }
            return other.untitledNumber
        }
        let number = Self.lowestFreeNumber(excluding: Set(used))
        untitledNumber = number
        return number
    }

    /// The lowest number from 1 that is not in `used`.
    static func lowestFreeNumber(excluding used: Set<Int>) -> Int {
        var number = 1
        while used.contains(number) { number += 1 }
        return number
    }

    override init() {
        super.init()
        // Scintilla keeps its own undo stack; dirty state is bridged via save points.
        hasUndoManager = false
    }

    // Windows-style explicit Save / Save As, as Notepad++ users expect.
    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    func attach(editor: ScintillaEditor) {
        self.editor = editor
        if let pendingText {
            self.pendingText = nil
            editor.load(utf8: pendingText.utf8, lineEnding: pendingText.format.lineEnding)
        } else {
            editor.setLineEnding(format.lineEnding, convertExisting: false)
        }
        editor.setLanguage(Language.detect(for: fileURL, firstLine: editor.firstLine()))
        editor.isReadOnly = isReadOnly || isFollowing
    }

    // MARK: Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = TextCodec.decode(data)
        MainActor.assumeIsolated {
            format = decoded.format
            if let editor {
                // Revert: the window is already open.
                editor.load(utf8: decoded.utf8, lineEnding: decoded.format.lineEnding)
                editor.setLanguage(Language.detect(for: fileURL, firstLine: editor.firstLine()))
            } else {
                pendingText = decoded
            }
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        try MainActor.assumeIsolated {
            try TextCodec.encode(editor?.utf8Text() ?? Data(), format: format)
        }
    }

    override func save(
        to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            MainActor.assumeIsolated {
                if error == nil, saveOperation != .saveToOperation, let self {
                    self.editor?.markSavePoint()
                    // Save As may change the extension, and with it the language.
                    let language = Language.detect(for: url)
                    if self.editor?.language != language, language != .normalText {
                        self.editor?.setLanguage(language)
                    }
                }
            }
            completionHandler(error)
        }
    }

    // MARK: File coordination

    /// Deleting in Finder moves the file to the Trash, and NSDocument would follow
    /// it there. Keep the original path instead, so the document reports the file
    /// as deleted and Save recreates it where it was.
    override func presentedItemDidMove(to newURL: URL) {
        let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.standardizedFileURL.path
        let path = newURL.standardizedFileURL.path
        if path.contains("/.Trash/") || (trash.map { path.hasPrefix($0 + "/") } ?? false) {
            return
        }
        super.presentedItemDidMove(to: newURL)
    }

    // MARK: Printing

    /// The text with its syntax colors (from the light theme: paper is
    /// white), in the editor's font at a print size, wrapped to the page.
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let editor else { throw CocoaError(.featureUnsupported) }
        let info = printInfo.copy() as? NSPrintInfo ?? printInfo
        info.dictionary().addEntries(from: printSettings)
        info.horizontalPagination = .fit
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin

        let settings = Preferences.editor
        let font = NSFont(name: settings.fontName, size: 9) ?? NSFont(name: "SF Mono", size: 9) ?? .monospacedSystemFont(ofSize: 9, weight: .regular)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(
            editor.attributedTextForPrinting(theme: .light, font: font, tabWidth: settings.tabWidth))
        textView.sizeToFit()

        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.jobTitle = displayName
        return operation
    }

    // MARK: Save panel

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        // Text files keep whatever extension the user types.
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return true
    }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        if let ext = fileURL?.pathExtension, !ext.isEmpty {
            return ext
        }
        return "txt"
    }
}
