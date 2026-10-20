import XCTest
@testable import MacPad

@MainActor
final class FollowTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "MacPadFollowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for document in NSDocumentController.shared.documents {
            document.updateChangeCount(.changeCleared)
            document.close()
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private func text(_ document: TextDocument) -> String {
        String(decoding: document.editor?.utf8Text() ?? Data(), as: UTF8.self)
    }

    /// Runs the main loop until `condition` holds or a second passes.
    private func wait(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func testFollowsAppendedLinesReadOnly() throws {
        let url = directory.appending(path: "app.log")
        try Data("09:00 INFO start\n".utf8).write(to: url)
        let controller = NSDocumentController.shared
        let document = try XCTUnwrap(controller.makeDocument(withContentsOf: url, ofType: "public.plain-text") as? TextDocument)
        controller.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        let editorController = try XCTUnwrap((document.windowControllers.first as? DocumentWindowController)?.editorController)

        editorController.startFollowing()
        XCTAssertTrue(document.isFollowing)
        XCTAssertEqual(document.editor?.isReadOnly, true)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("09:01 ERROR boom\n".utf8))
        try handle.close()
        wait { text(document).hasSuffix("boom\n") }
        XCTAssertEqual(text(document), "09:00 INFO start\n09:01 ERROR boom\n")
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertNil(document.externalChange())

        editorController.stopFollowing()
        XCTAssertFalse(document.isFollowing)
        XCTAssertEqual(document.editor?.isReadOnly, false)
        XCTAssertEqual(text(document), "09:00 INFO start\n09:01 ERROR boom\n")
    }

    func testAsksToSaveBeforeFollowingAnUntitledDocument() throws {
        let document = try XCTUnwrap(NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? TextDocument)
        let editorController = try XCTUnwrap((document.windowControllers.first as? DocumentWindowController)?.editorController)
        editorController.startFollowing()
        XCTAssertFalse(document.isFollowing)
        document.windowControllers.first?.window?.attachedSheet.map { $0.sheetParent?.endSheet($0) }
    }
}
