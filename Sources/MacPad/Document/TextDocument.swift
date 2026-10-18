import AppKit

/// A text file. Scintilla owns the buffer and its undo history; the document
/// owns the on-disk format (encoding, line endings) and the file lifecycle.
final class TextDocument: NSDocument {
    var format = Preferences.newDocumentFormat

    private(set) weak var editor: ScintillaEditor?
    /// File contents read before the editor exists (the normal open path).
    private var pendingText: TextCodec.Decoded?

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
