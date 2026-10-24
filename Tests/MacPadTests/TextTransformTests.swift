import XCTest
@testable import MacPad

final class TextTransformTests: XCTestCase {
    // MARK: Case

    func testProperCase() {
        XCTAssertEqual(TextTransform.convert("hello wORLD it's", to: .properForce), "Hello World It's")
        XCTAssertEqual(TextTransform.convert("hello wORLD it's", to: .properBlend), "Hello WORLD It's")
    }

    func testSentenceCase() {
        XCTAssertEqual(TextTransform.convert("hello THERE. how are you? i am fine", to: .sentenceForce),
                       "Hello there. How are you? I am fine")
        XCTAssertEqual(TextTransform.convert("hello THERE. how", to: .sentenceBlend), "Hello THERE. How")
        // A decimal point does not start a sentence.
        XCTAssertEqual(TextTransform.convert("pi is 3.14 ok", to: .sentenceForce), "Pi is 3.14 ok")
        // A blank line does.
        XCTAssertEqual(TextTransform.convert("one\n\ntwo", to: .sentenceForce), "One\n\nTwo")
    }

    func testInvertAndRandomCase() {
        XCTAssertEqual(TextTransform.convert("aBc 1", to: .invert), "AbC 1")
        let random = TextTransform.convert("abcdef 123", to: .random)
        XCTAssertEqual(random.lowercased(), "abcdef 123")
    }

    // MARK: Sorting

    func testLexicographicSorts() throws {
        let lines = ["b", "B", "a", "C"]
        XCTAssertEqual(try TextTransform.sort(lines, .lexicographicAscending), ["B", "C", "a", "b"])
        XCTAssertEqual(try TextTransform.sort(lines, .lexicographicDescending), ["b", "a", "C", "B"])
        XCTAssertEqual(try TextTransform.sort(["b", "C", "a"], .caseInsensitiveAscending), ["a", "b", "C"])
    }

    func testIntegerSortComparesNumbersInsideText() throws {
        XCTAssertEqual(try TextTransform.sort(["file10", "file2", "file1", "-3", "7"], .integerAscending),
                       ["-3", "7", "file1", "file2", "file10"])
        XCTAssertEqual(try TextTransform.sort(["10", "9", "100"], .integerDescending), ["100", "10", "9"])
    }

    func testDecimalSorts() throws {
        XCTAssertEqual(try TextTransform.sort(["1,5", "", "-2", "1,25"], .decimalCommaAscending), ["", "-2", "1,25", "1,5"])
        XCTAssertEqual(try TextTransform.sort(["1.5", "10", "2.25"], .decimalDotDescending), ["10", "2.25", "1.5"])
        XCTAssertThrowsError(try TextTransform.sort(["1", "x", "2"], .decimalDotAscending)) { error in
            XCTAssertEqual(error as? TextTransform.SortError, TextTransform.SortError(lineIndex: 1))
        }
    }

    func testLengthReverseAndRandom() throws {
        XCTAssertEqual(try TextTransform.sort(["ccc", "a", "bb"], .lengthAscending), ["a", "bb", "ccc"])
        XCTAssertEqual(try TextTransform.sort(["1", "2", "3"], .reverse), ["3", "2", "1"])
        XCTAssertEqual(try TextTransform.sort(["1", "2", "3"], .random).sorted(), ["1", "2", "3"])
    }

    // MARK: Lines and whitespace

    func testDuplicatesAndEmptyLines() {
        XCTAssertEqual(TextTransform.removingDuplicates(["a", "b", "a", "c", "b"]), ["a", "b", "c"])
        XCTAssertEqual(TextTransform.removingConsecutiveDuplicates(["a", "a", "b", "a"]), ["a", "b", "a"])
        XCTAssertEqual(TextTransform.removingEmptyLines(["a", "", " \t", "b"], includingBlank: false), ["a", " \t", "b"])
        XCTAssertEqual(TextTransform.removingEmptyLines(["a", "", " \t", "b"], includingBlank: true), ["a", "b"])
    }

    func testTrim() {
        XCTAssertEqual(TextTransform.trim(" \t a b \t", .leading), "a b \t")
        XCTAssertEqual(TextTransform.trim(" \t a b \t", .trailing), " \t a b")
        XCTAssertEqual(TextTransform.trim(" \t a b \t", .both), "a b")
    }

    func testTabsAndSpaces() {
        XCTAssertEqual(TextTransform.tabsToSpaces("\tab\tc", tabWidth: 4), "    ab  c")
        XCTAssertEqual(TextTransform.spacesToTabs("        x   y", tabWidth: 4, leadingOnly: false), "\t\tx\ty")
        XCTAssertEqual(TextTransform.spacesToTabs("        x   y", tabWidth: 4, leadingOnly: true), "\t\tx   y")
        // A single space reaching a tab stop stays a space.
        XCTAssertEqual(TextTransform.spacesToTabs("abc d", tabWidth: 4, leadingOnly: false), "abc d")
    }
}
