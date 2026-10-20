import XCTest
@testable import MacPad

final class LogLevelTests: XCTestCase {
    private func level(_ line: String) -> LogLevel? {
        LogLevel.classify(Array(line.utf8))
    }

    func testClassifiesCommonFormats() {
        XCTAssertEqual(level("2026-10-19 12:00:01 ERROR db: timeout"), .error)
        XCTAssertEqual(level("[WARN] disk at 91%"), .warning)
        XCTAssertEqual(level("12:00:01.123 INFO  started"), .info)
        XCTAssertEqual(level("level=DEBUG msg=hi"), .debug)
        XCTAssertEqual(level("10-19 12:00:01.123  1234  5678 E ActivityManager: crash"), .error)
    }

    func testClassifiesCapitalizedAndColonForms() {
        XCTAssertEqual(level("2026-10-20 09:00:01 [Error] Access denied"), .error)
        XCTAssertEqual(level("2026-10-20 09:00:02 [Warning] Low disk"), .warning)
        XCTAssertNil(level("2026-10-20 09:00:03 [Information] Started"))
        XCTAssertEqual(level("fail: Microsoft.AspNetCore[0]"), .error)
        XCTAssertEqual(level("dbug: App.Startup[1]"), .debug)
        XCTAssertEqual(level("src/main.rs:3: warning: unused variable"), .warning)
        XCTAssertEqual(level("error: could not compile"), .error)
    }

    func testIgnoresLevelsInRunningText() {
        XCTAssertNil(level("retrying after an error in the network"))
        XCTAssertNil(level("no warnings, all fine"))
        XCTAssertNil(level("eRRor mixed case"))
        XCTAssertNil(level("INFORMATION about ERRORS"))
        XCTAssertNil(level("GET /index.html 200"))
    }

    func testSpansCoverLinesWithoutTheirBreaks() {
        let text = Data("a INFO x\nplain\r\nb ERROR y\r\n".utf8)
        let spans = LogLevel.spans(in: text, base: 100)
        XCTAssertEqual(spans.map(\.range), [100..<108, 116..<125])
        XCTAssertEqual(spans.map(\.level), [.info, .error])
    }
}
