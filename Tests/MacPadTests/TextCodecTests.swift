import XCTest
@testable import MacPad

final class TextCodecTests: XCTestCase {
    func testDetectsUTF8AndLineEndings() {
        let decoded = TextCodec.decode(Data("a\r\nb\r\nc\n".utf8))
        XCTAssertEqual(decoded.format, TextFormat(encoding: .utf8, lineEnding: .crlf))
        XCTAssertEqual(decoded.utf8, Data("a\r\nb\r\nc\n".utf8))
    }

    func testStripsAndRestoresByteOrderMarks() throws {
        let original = Data([0xFF, 0xFE]) + "héllo".data(using: .utf16LittleEndian)!
        let decoded = TextCodec.decode(original)
        XCTAssertEqual(decoded.format.encoding, .utf16LE)
        XCTAssertEqual(String(decoding: decoded.utf8, as: UTF8.self), "héllo")
        XCTAssertEqual(try TextCodec.encode(decoded.utf8, format: decoded.format), original)
    }

    func testFallsBackToWindows1252() throws {
        let original = Data([0x63, 0x61, 0x66, 0xE9, 0x80])  // "café€"
        let decoded = TextCodec.decode(original)
        XCTAssertEqual(decoded.format.encoding, .windows1252)
        XCTAssertEqual(String(decoding: decoded.utf8, as: UTF8.self), "café€")
        XCTAssertEqual(try TextCodec.encode(decoded.utf8, format: decoded.format), original)
    }

    func testRejectsUnrepresentableCharacters() {
        let format = TextFormat(encoding: .windows1252, lineEnding: .lf)
        XCTAssertThrowsError(try TextCodec.encode(Data("日本".utf8), format: format))
    }
}
