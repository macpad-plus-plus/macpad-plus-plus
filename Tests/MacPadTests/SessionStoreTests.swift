import Scintilla
import XCTest
@testable import MacPad

@MainActor
final class SessionStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "MacPadSessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        closeAllDocuments()
    }

    override func tearDown() async throws {
        closeAllDocuments()
        try? FileManager.default.removeItem(at: directory)
    }

    private func closeAllDocuments() {
        for document in NSDocumentController.shared.documents {
            document.updateChangeCount(.changeCleared)
            document.close()
        }
    }

    private func text(of document: TextDocument?) -> String {
        String(decoding: document?.editor?.utf8Text() ?? Data(), as: UTF8.self)
    }

    func testRestoresFilesUnsavedChangesAndUntitledTabs() throws {
        let controller = NSDocumentController.shared
        let store = SessionStore(directory: directory.appending(path: "Support"))

        // A saved file with unsaved edits.
        let fileURL = directory.appending(path: "notes.py")
        try Data("print('on disk')\n".utf8).write(to: fileURL)
        let fileDocument = try XCTUnwrap(controller.makeDocument(withContentsOf: fileURL, ofType: "public.plain-text") as? TextDocument)
        controller.addDocument(fileDocument)
        fileDocument.makeWindowControllers()
        fileDocument.showWindows()
        fileDocument.editor?.replaceText(utf8: Data("print('edited')\n".utf8))
        XCTAssertTrue(fileDocument.isDocumentEdited)

        // An untitled tab with content.
        let untitled = try XCTUnwrap(controller.openUntitledDocumentAndDisplay(true) as? TextDocument)
        untitled.editor?.replaceText(utf8: Data("scratch".utf8))

        // An empty untitled tab, which should not be restored.
        _ = try controller.openUntitledDocumentAndDisplay(true)

        store.save()
        closeAllDocuments()
        XCTAssertTrue(controller.documents.isEmpty)

        XCTAssertTrue(store.restore())
        let restored = controller.documents.compactMap { $0 as? TextDocument }
        XCTAssertEqual(restored.count, 2)

        let restoredFile = restored.first { $0.fileURL?.lastPathComponent == "notes.py" }
        XCTAssertEqual(text(of: restoredFile), "print('edited')\n")
        XCTAssertEqual(restoredFile?.isDocumentEdited, true)
        XCTAssertEqual(restoredFile?.editor?.language.id, "python")
        // Undo goes back to what is on disk.
        restoredFile?.editor?.send(SCI_UNDO)
        XCTAssertEqual(text(of: restoredFile), "print('on disk')\n")

        let restoredUntitled = restored.first { $0.fileURL == nil }
        XCTAssertEqual(text(of: restoredUntitled), "scratch")
        XCTAssertEqual(restoredUntitled?.isDocumentEdited, true)

        // Both tabs come back in a single window.
        let windows = Set(restored.compactMap { $0.windowControllers.first?.window?.tabGroup }.map(ObjectIdentifier.init))
        XCTAssertEqual(windows.count, 1)
    }

    func testRemovesBackupsOfSavedDocuments() throws {
        let support = directory.appending(path: "Support")
        let store = SessionStore(directory: support)
        let untitled = try XCTUnwrap(NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? TextDocument)
        untitled.editor?.replaceText(utf8: Data("draft".utf8))
        store.save()
        let backups = support.appending(path: "Backups")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 1)

        closeAllDocuments()
        store.save()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 0)
    }
}
