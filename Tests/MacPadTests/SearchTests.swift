import Scintilla
import XCTest
@testable import MacPad

@MainActor
final class SearchTests: XCTestCase {
    private func makeEditor(_ text: String) -> ScintillaEditor {
        let editor = ScintillaEditor(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        editor.load(utf8: Data(text.utf8), lineEnding: .lf)
        return editor
    }

    private func text(of editor: ScintillaEditor) -> String {
        String(decoding: editor.utf8Text(), as: UTF8.self)
    }

    func testFindNextWrapsAround() throws {
        let editor = makeEditor("foo bar foo")
        let first = try XCTUnwrap(try editor.find(SearchOptions(query: "foo")))
        XCTAssertEqual(first.range, 0..<3)
        XCTAssertFalse(first.wrapped)
        let second = try XCTUnwrap(try editor.find(SearchOptions(query: "foo")))
        XCTAssertEqual(second.range, 8..<11)
        let third = try XCTUnwrap(try editor.find(SearchOptions(query: "foo")))
        XCTAssertEqual(third.range, 0..<3)
        XCTAssertTrue(third.wrapped)
    }

    func testFindPrevious() throws {
        let editor = makeEditor("foo bar foo")
        let match = try XCTUnwrap(try editor.find(SearchOptions(query: "foo"), forward: false))
        XCTAssertEqual(match.range, 8..<11)
    }

    func testOptions() throws {
        let editor = makeEditor("Foo foo food")
        XCTAssertEqual(try editor.allMatches(SearchOptions(query: "foo")).ranges.count, 3)
        XCTAssertEqual(try editor.allMatches(SearchOptions(query: "foo", matchCase: true)).ranges.count, 2)
        XCTAssertEqual(try editor.allMatches(SearchOptions(query: "foo", wholeWord: true)).ranges.count, 2)
        XCTAssertEqual(try editor.allMatches(SearchOptions(query: "fo+d?\\b", regex: true)).ranges.count, 3)
    }

    func testMultibyteText() throws {
        let editor = makeEditor("ação e reação")
        let matches = try editor.allMatches(SearchOptions(query: "ação"))
        XCTAssertEqual(matches.ranges.count, 2)
    }

    func testReplaceAllWithGroupsIsOneUndoStep() throws {
        let editor = makeEditor("x=1\ny=22\n")
        let options = SearchOptions(query: "(\\w)=(\\d+)", regex: true)
        XCTAssertEqual(try editor.replaceAll(options, with: "$2 -> \\1"), 2)
        XCTAssertEqual(text(of: editor), "1 -> x\n22 -> y\n")
        editor.send(SCI_UNDO)
        XCTAssertEqual(text(of: editor), "x=1\ny=22\n")
    }

    func testReplaceAllHandlesEmptyMatches() throws {
        let editor = makeEditor("a\nb\nc")
        XCTAssertEqual(try editor.replaceAll(SearchOptions(query: "^", regex: true), with: "> "), 3)
        XCTAssertEqual(text(of: editor), "> a\n> b\n> c")
    }

    func testReplaceSelectionOnlyReplacesAMatch() throws {
        let editor = makeEditor("cat cat")
        let options = SearchOptions(query: "cat")
        // Nothing selected yet: the first call just finds.
        XCTAssertFalse(try editor.replaceSelection(options, with: "dog"))
        XCTAssertTrue(try editor.replaceSelection(options, with: "dog"))
        XCTAssertEqual(text(of: editor), "dog cat")
        XCTAssertEqual(editor.selectionRange, 4..<7)
    }

    func testInvalidPatternThrows() {
        let editor = makeEditor("abc")
        XCTAssertThrowsError(try editor.allMatches(SearchOptions(query: "(", regex: true)))
    }
}
