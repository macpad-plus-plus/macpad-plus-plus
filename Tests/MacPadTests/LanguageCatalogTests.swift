import Scintilla
import XCTest
@testable import MacPad

final class LanguageCatalogTests: XCTestCase {
    func testLoadsNotepadPlusPlusLanguages() {
        XCTAssertGreaterThanOrEqual(Language.all.count, 85)
        XCTAssertEqual(Language.all.first?.id, "normal")
        XCTAssertNil(Language.with(id: "searchResult"))
    }

    func testEveryLexerExistsInLexilla() {
        for language in Language.all {
            XCTAssertNotNil(CreateLexer(language.lexer), "No Lexilla lexer '\(language.lexer)' for \(language.id)")
        }
    }

    func testCppKeywordSetsFollowNotepadPlusPlus() throws {
        let cpp = try XCTUnwrap(Language.with(id: "cpp"))
        XCTAssertEqual(cpp.lexer, "cpp")
        XCTAssertTrue(try XCTUnwrap(cpp.keywords[0]).contains("co_await"))   // instre1
        XCTAssertTrue(try XCTUnwrap(cpp.keywords[1]).contains("constexpr"))  // type1
        XCTAssertTrue(try XCTUnwrap(cpp.keywords[2]).contains("brief"))      // doxygen
        XCTAssertEqual(cpp.styles[.keyword], [SCE_C_WORD])
        XCTAssertEqual(cpp.styles[.type], [SCE_C_WORD2])
    }

    func testStyleClassification() {
        func kind(_ name: String, _ keywordClass: String? = nil) -> TokenKind? {
            LanguageCatalog.classify(.init(name: name, id: 1, keywordClass: keywordClass))
        }
        XCTAssertEqual(kind("COMMENT LINE"), .comment)
        XCTAssertEqual(kind("COMMENT DOC KEYWORD", "type2"), .docComment)
        XCTAssertEqual(kind("INSTRUCTION WORD", "instre1"), .keyword)
        XCTAssertEqual(kind("TYPE WORD", "type1"), .type)
        XCTAssertEqual(kind("DOUBLE QUOTED STRING"), .string)
        XCTAssertEqual(kind("STRING EOL"), .error)
        XCTAssertEqual(kind("NUMBER"), .number)
        XCTAssertEqual(kind("TAG UNKNOWN"), .error)
        XCTAssertEqual(kind("USER KEYWORDS 1", "substyle1"), nil)
        XCTAssertNil(kind("DEFAULT"))
        XCTAssertNil(kind("IDENTIFIER"))
    }

    func testDetection() {
        XCTAssertEqual(Language.detect(for: URL(fileURLWithPath: "/tmp/a.py")).id, "python")
        XCTAssertEqual(Language.detect(for: URL(fileURLWithPath: "/tmp/Makefile")).id, "makefile")
        XCTAssertEqual(Language.detect(for: URL(fileURLWithPath: "/tmp/README.md")).id, "markdown")
        XCTAssertEqual(Language.detect(for: URL(fileURLWithPath: "/tmp/run"), firstLine: "#!/usr/bin/env python3").id, "python")
        XCTAssertEqual(Language.detect(for: nil).id, "normal")
    }
}

extension LanguageCatalogTests {
    func testEveryLanguageHasHighlighting() {
        let plain: Set<String> = ["normal", "nfo"]
        let unstyled = Language.all.filter { !plain.contains($0.id) && $0.styles.isEmpty }.map(\.id)
        XCTAssertEqual(unstyled, [])
    }
}
