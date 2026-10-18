import XCTest
@testable import MacPad

@MainActor
final class ExternalChangeTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "MacPadExternal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func openDocument(_ text: String) throws -> (TextDocument, URL) {
        let url = directory.appending(path: "notes.txt")
        try Data(text.utf8).write(to: url)
        let document = try XCTUnwrap(NSDocumentController.shared.makeDocument(withContentsOf: url, ofType: "public.plain-text") as? TextDocument)
        return (document, url)
    }

    func testUnchangedFileReportsNothing() throws {
        let (document, _) = try openDocument("one")
        XCTAssertNil(document.externalChange())
    }

    func testDetectsModificationByAnotherApp() throws {
        let (document, url) = try openDocument("one")
        try Data("two".utf8).write(to: url)
        // File systems store modification dates with limited precision; make it clearly newer.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        XCTAssertEqual(document.externalChange(), .modified)
    }

    func testDetectsDeletion() throws {
        let (document, url) = try openDocument("one")
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(document.externalChange(), .deleted)
    }

    func testMoveToTrashIsTreatedAsDeletion() throws {
        let (document, url) = try openDocument("one")
        let trash = try XCTUnwrap(FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first)
        document.presentedItemDidMove(to: trash.appending(path: "notes.txt"))
        XCTAssertEqual(document.fileURL, url, "The document keeps its original path")
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(document.externalChange(), .deleted)
    }

    func testUntitledDocumentsAreIgnored() {
        XCTAssertNil(TextDocument().externalChange())
    }
}
