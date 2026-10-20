import XCTest
@testable import MacPad

@MainActor
final class TabTests: XCTestCase {
    override func setUp() async throws {
        closeAllDocuments()
    }

    override func tearDown() async throws {
        closeAllDocuments()
    }

    private func closeAllDocuments() {
        for document in NSDocumentController.shared.documents {
            document.updateChangeCount(.changeCleared)
            document.close()
        }
    }

    func testLowestFreeNumber() {
        XCTAssertEqual(TextDocument.lowestFreeNumber(excluding: []), 1)
        XCTAssertEqual(TextDocument.lowestFreeNumber(excluding: [1, 2, 4]), 3)
        XCTAssertEqual(TextDocument.lowestFreeNumber(excluding: [2]), 1)
    }

    func testUntitledNumbersAreReused() throws {
        let controller = NSDocumentController.shared
        let first = try XCTUnwrap(controller.openUntitledDocumentAndDisplay(true) as? TextDocument)
        let second = try XCTUnwrap(controller.openUntitledDocumentAndDisplay(true) as? TextDocument)
        let third = try XCTUnwrap(controller.openUntitledDocumentAndDisplay(true) as? TextDocument)
        XCTAssertEqual([first, second, third].map(\.untitledNumber), [1, 2, 3])
        second.close()
        let next = try XCTUnwrap(controller.openUntitledDocumentAndDisplay(true) as? TextDocument)
        XCTAssertEqual(next.untitledNumber, 2)
        XCTAssertEqual(next.displayName, String(localized: "Untitled \(2)"))
        // A renamed tab keeps its name and frees its number.
        next.customName = "ideas"
        XCTAssertEqual(next.displayName, "ideas")
        let after = try XCTUnwrap(controller.openUntitledDocumentAndDisplay(true) as? TextDocument)
        XCTAssertEqual(after.untitledNumber, 2)
    }

    func testPinnedTabsStayFirstAndTabsMoveWithinTheirKind() throws {
        let controller = NSDocumentController.shared
        let documents = try (0..<4).map { _ in try XCTUnwrap(controller.openUntitledDocumentAndDisplay(true) as? TextDocument) }
        let windows = documents.compactMap { $0.windowControllers.first?.window }
        let group = try XCTUnwrap(windows.first?.tabGroup)
        XCTAssertEqual(group.windows, windows)

        // Pinning the third moves it to the front.
        let third = try XCTUnwrap(windows[2].windowController as? DocumentWindowController)
        third.togglePinTab(nil)
        XCTAssertEqual(group.windows, [windows[2], windows[0], windows[1], windows[3]])
        XCTAssertFalse(TabOrder.canMove(windows[2], toEnd: false))
        XCTAssertFalse(TabOrder.canMove(windows[2], toEnd: true))

        // The others move among the unpinned only.
        TabOrder.move(windows[3], toEnd: false)
        XCTAssertEqual(group.windows, [windows[2], windows[3], windows[0], windows[1]])
        TabOrder.move(windows[3], toEnd: true)
        XCTAssertEqual(group.windows, [windows[2], windows[0], windows[1], windows[3]])
        XCTAssertEqual(group.windows.count, 4)
    }

    func testSplitsTerminalCommandsLikeAShell() {
        XCTAssertEqual(Terminal.splitWords(#"open -a "Some App" {dir}"#), ["open", "-a", "Some App", "{dir}"])
        XCTAssertEqual(Terminal.splitWords("  wezterm  start --cwd '{dir}' "), ["wezterm", "start", "--cwd", "{dir}"])
        XCTAssertEqual(Terminal.splitWords(#"x """#), ["x", ""])
        XCTAssertTrue(Terminal.splitWords("   ").isEmpty)
        XCTAssertThrowsError(try Terminal.open(URL(filePath: "/tmp"), choice: Terminal.custom, command: " "))
    }
}
