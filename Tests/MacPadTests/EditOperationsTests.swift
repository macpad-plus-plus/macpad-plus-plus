import Scintilla
import XCTest
@testable import MacPad

@MainActor
final class EditOperationsTests: XCTestCase {
    private func makeEditor(_ text: String, language: String? = nil) -> ScintillaEditor {
        let editor = ScintillaEditor(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        editor.load(utf8: Data(text.utf8), lineEnding: .lf)
        if let language, let match = Language.with(id: language) {
            editor.setLanguage(match)
        }
        return editor
    }

    private func text(of editor: ScintillaEditor) -> String {
        String(decoding: editor.utf8Text(), as: UTF8.self)
    }

    // MARK: Lines

    func testSortWholeDocumentKeepsFinalNewline() throws {
        let editor = makeEditor("c\na\nb\n")
        try editor.sortLines(.lexicographicAscending)
        XCTAssertEqual(text(of: editor), "a\nb\nc\n")
    }

    func testSortSelectedLinesOnly() throws {
        let editor = makeEditor("z\nc\na\nb\ny")
        // From inside line 2 to inside line 4.
        editor.send(SCI_SETSEL, 3, 7)
        try editor.sortLines(.lexicographicAscending)
        XCTAssertEqual(text(of: editor), "z\na\nb\nc\ny")
    }

    func testSortIsOneUndoStep() throws {
        let editor = makeEditor("b\na")
        try editor.sortLines(.lexicographicAscending)
        editor.send(SCI_UNDO)
        XCTAssertEqual(text(of: editor), "b\na")
    }

    func testRemoveDuplicatesAndEmptyLines() {
        let editor = makeEditor("a\n\nb\na\n  \nb\n")
        editor.removeDuplicateLines(consecutiveOnly: false)
        XCTAssertEqual(text(of: editor), "a\n\nb\n  \n")
        editor.removeEmptyLines(includingBlank: true)
        XCTAssertEqual(text(of: editor), "a\nb\n")
    }

    func testInsertBlankLines() {
        let editor = makeEditor("one\ntwo")
        editor.send(SCI_GOTOPOS, 5)
        editor.insertBlankLine(above: true)
        XCTAssertEqual(text(of: editor), "one\n\ntwo")
        editor.insertBlankLine(above: false)
        XCTAssertEqual(text(of: editor), "one\n\n\ntwo")
    }

    func testIndentSingleLineKeepsCaretInText() {
        let editor = makeEditor("abc")
        editor.send(SCI_SETTABWIDTH, 4)
        editor.send(SCI_SETUSETABS, 0)
        editor.send(SCI_GOTOPOS, 1)
        editor.indentLines(increase: true)
        XCTAssertEqual(text(of: editor), "    abc")
        XCTAssertEqual(editor.send(SCI_GETCURRENTPOS), 5)
        editor.indentLines(increase: false)
        XCTAssertEqual(text(of: editor), "abc")
    }

    // MARK: Case

    func testConvertCaseOfSelection() {
        let editor = makeEditor("hello world")
        editor.send(SCI_SETSEL, 0, 5)
        editor.convertCase(to: .upper)
        XCTAssertEqual(text(of: editor), "HELLO world")
        XCTAssertEqual(editor.selectedText, "HELLO")
    }

    func testConvertCaseWithoutSelectionDoesNothing() {
        let editor = makeEditor("hello")
        editor.convertCase(to: .upper)
        XCTAssertEqual(text(of: editor), "hello")
    }

    // MARK: Comments

    func testToggleLineCommentKeepsIndentation() {
        let editor = makeEditor("int a;\n    int b;\n\nint c;", language: "cpp")
        editor.send(SCI_SETSEL, 0, editor.send(SCI_GETLENGTH))
        editor.lineComment(.toggle)
        XCTAssertEqual(text(of: editor), "// int a;\n    // int b;\n\n// int c;")
        editor.lineComment(.toggle)
        XCTAssertEqual(text(of: editor), "int a;\n    int b;\n\nint c;")
    }

    func testUncommentWithoutSpaceAndInAnyCase() {
        let editor = makeEditor("//a\n// b", language: "cpp")
        editor.send(SCI_SETSEL, 0, editor.send(SCI_GETLENGTH))
        editor.lineComment(.uncomment)
        XCTAssertEqual(text(of: editor), "a\nb")

        let batch = makeEditor("rem echo", language: "batch")
        batch.lineComment(.uncomment)
        XCTAssertEqual(text(of: batch), "echo")
    }

    func testLineCommentWrapsLinesWhenOnlyBlockCommentsExist() {
        let editor = makeEditor("<p>hi</p>", language: "html")
        editor.lineComment(.toggle)
        XCTAssertEqual(text(of: editor), "<!-- <p>hi</p> -->")
        editor.lineComment(.toggle)
        XCTAssertEqual(text(of: editor), "<p>hi</p>")
    }

    func testBlockCommentAndUncomment() {
        let editor = makeEditor("int a = 1;", language: "cpp")
        editor.send(SCI_SETSEL, 8, 9)
        editor.blockComment()
        XCTAssertEqual(text(of: editor), "int a = /* 1 */;")
        editor.send(SCI_GOTOPOS, 12)
        XCTAssertTrue(editor.blockUncomment())
        XCTAssertEqual(text(of: editor), "int a = 1;")
    }

    func testBlockCommentFallsBackToLineComment() {
        let editor = makeEditor("x = 1", language: "python")
        editor.blockComment()
        XCTAssertEqual(text(of: editor), "# x = 1")
    }

    // MARK: Blank operations

    func testTrimAndJoin() {
        let editor = makeEditor("  a  \n\tb\t\n")
        editor.trimLines(.trailing)
        XCTAssertEqual(text(of: editor), "  a\n\tb\n")
        editor.trimLines(.leading)
        XCTAssertEqual(text(of: editor), "a\nb\n")
        editor.lineEndingsToSpaces()
        XCTAssertEqual(text(of: editor).trimmingCharacters(in: .whitespaces), "a b")
    }

    func testTabSpaceConversion() {
        let editor = makeEditor("\tx\n")
        editor.send(SCI_SETTABWIDTH, 4)
        editor.convertTabsToSpaces()
        XCTAssertEqual(text(of: editor), "    x\n")
        editor.convertSpacesToTabs(leadingOnly: true)
        XCTAssertEqual(text(of: editor), "\tx\n")
    }

    // MARK: Zoom

    func testZoomPercent() {
        let editor = makeEditor("")
        XCTAssertEqual(editor.zoomPercent, 100)
        editor.send(SCI_SETZOOM, Int(Preferences.editor.fontSize))
        XCTAssertEqual(editor.zoomPercent, 200)
    }
}
