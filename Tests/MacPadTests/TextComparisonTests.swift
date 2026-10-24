import XCTest
@testable import MacPad

/// Ported from OxyPad's `compare.rs` tests.
final class TextComparisonTests: XCTestCase {
    private func kinds(_ comparison: TextComparison) -> [TextComparison.Kind] {
        comparison.rows.map(\.kind)
    }

    private func substring(_ line: String, _ range: Range<Int>) -> String {
        String(decoding: Array(line.utf8)[range], as: UTF8.self)
    }

    func testIdenticalTextsAlignLineByLine() {
        let comparison = TextComparison(left: "a\nb\n", right: "a\nb\n")
        XCTAssertTrue(comparison.isIdentical)
        XCTAssertEqual(kinds(comparison), [.equal, .equal])
    }

    func testPairsChangedLinesAndFillsTheRest() {
        let comparison = TextComparison(left: "keep\nold one\nold two\nend\n", right: "keep\nnew one\nend\nextra\n")
        XCTAssertEqual(kinds(comparison), [.equal, .changed, .removed, .equal, .added])
        XCTAssertEqual(comparison.changes, [1, 4])
        XCTAssertEqual([comparison.changed, comparison.removed, comparison.added], [1, 1, 1])
        // The filler side of a removed row is empty.
        XCTAssertNil(comparison.rows[2].right)
        XCTAssertEqual(comparison.rows[2].left?.line, 2)
    }

    func testEmphasizesOnlyTheWordsThatChanged() throws {
        let left = "let value = compute(60);", right = "let value = compute_fast(60);"
        let comparison = TextComparison(left: left + "\n", right: right + "\n")
        let row = comparison.rows[0]
        XCTAssertEqual(row.kind, .changed)
        XCTAssertEqual(substring(left, try XCTUnwrap(row.left?.emphasis.first)), "compute")
        XCTAssertEqual(substring(right, try XCTUnwrap(row.right?.emphasis.first)), "compute_fast")
    }

    func testJoinsChangedWordsAcrossSpaces() throws {
        let left = "/// Counts how often each word appears."
        let comparison = TextComparison(left: left + "\n", right: "/// Counts words in this text.\n")
        let emphasis = try XCTUnwrap(comparison.rows[0].left?.emphasis)
        XCTAssertEqual(emphasis.count, 1)
        XCTAssertEqual(substring(left, emphasis[0]), "how often each word appears")
    }

    func testUnrelatedLinesGetNoWordEmphasis() {
        let comparison = TextComparison(left: "alpha beta gamma\n", right: "one two three four\n")
        XCTAssertEqual(comparison.rows[0].left?.emphasis, [])
    }

    func testMissingFinalNewlineDoesNotAddALine() {
        XCTAssertEqual(TextComparison.lines("a\nb"), TextComparison.lines("a\nb\n"))
        XCTAssertTrue(TextComparison(left: "a\nb", right: "a\nb\n").isIdentical)
        XCTAssertTrue(TextComparison(left: "a\r\nb\r\n", right: "a\nb\n").isIdentical)
    }

    func testEmphasisUsesByteOffsets() throws {
        let left = "café = 1", right = "café = 2"
        let comparison = TextComparison(left: left, right: right)
        XCTAssertEqual(substring(right, try XCTUnwrap(comparison.rows[0].right?.emphasis.first)), "2")
    }

    func testOneSideEmpty() {
        let comparison = TextComparison(left: "", right: "a\nb")
        XCTAssertEqual(kinds(comparison), [.added, .added])
        XCTAssertEqual(comparison.changes, [0])
    }
}
