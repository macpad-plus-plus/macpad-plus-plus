import XCTest
@testable import MacPad

final class FunctionListTests: XCTestCase {
    private static let parsers = FunctionListParser.loadBundled()

    private func symbols(_ language: String, _ source: String) throws -> [Symbol] {
        try XCTUnwrap(Self.parsers[language], "No parser for \(language)").parse(source)
    }

    func testEveryBundledParserCompiles() throws {
        let directory = try XCTUnwrap(Bundle.main.url(forResource: "FunctionList", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var failures: [String] = []
        for file in files where file.pathExtension == "xml" {
            do {
                _ = try FunctionListParser.load(from: file)
            } catch {
                failures.append("\(file.lastPathComponent): \(error)")
            }
        }
        // ICU has no Boost conditionals ("(?(...)"), used by these parsers;
        // Notepad++'s fortran77 comment pattern has an unbalanced parenthesis.
        let unsupported = ["fortran77.xml", "pascal.xml", "sql.xml", "vhdl.xml"]
        XCTAssertEqual(failures.filter { failure in !unsupported.contains { failure.hasPrefix($0) } }, [])
        XCTAssertGreaterThanOrEqual(Self.parsers.count, 41)
    }

    func testCpp() throws {
        let found = try symbols("cpp", """
        // void commented() {}
        class Widget : public Base {
        public:
            void draw(int x) { if (x) { return; } }
            int size() const;
        };
        int Widget::size() const { return 1; }
        static void helper(const char *s) {
        }
        """)
        let names = found.map { [$0.container ?? "", $0.name] }
        XCTAssertTrue(names.contains(["Widget", "draw"]), "\(names)")
        XCTAssertTrue(names.contains(["Widget", "size"]), "\(names)")
        XCTAssertTrue(names.contains(["", "helper"]), "\(names)")
        XCTAssertFalse(names.contains { $0[1] == "commented" })
        XCTAssertEqual(found.first { $0.name == "helper" }?.line, 8)
    }

    func testPython() throws {
        let found = try symbols("python", """
        class Greeter:
            def hello(self):
                pass

        async def main():
            pass
        """)
        XCTAssertEqual(found.map(\.name), ["hello(self)", "main()"])
        XCTAssertEqual(found.first?.container, "Greeter")
    }

    func testSwift() throws {
        let found = try symbols("swift", """
        struct Point {
            init(x: Int) {}
            func length() -> Double { 0 }
        }
        func free<T>(_ value: T) {}
        """)
        XCTAssertEqual(found.map(\.name), ["init", "length", "free"])
        XCTAssertEqual(found.first?.container, "Point")
    }

    func testJava() throws {
        let found = try symbols("java", """
        public class Shop<T extends Item> {
            private int count;
            public List<Map<String, T>> items(int max) throws IOException {
                return null;
            }
        }
        """)
        XCTAssertEqual(found.map(\.name), ["items"])
        XCTAssertEqual(found.first?.container?.hasPrefix("Shop"), true)
    }

    func testJavaScript() throws {
        let found = try symbols("javascript.js", """
        function load(url) {
        }
        const save = function (data) {};
        class Store {
            get size() { return 0; }
        }
        """)
        XCTAssertTrue(found.map(\.name).contains("load"), "\(found)")
        XCTAssertTrue(found.map(\.name).contains("save"), "\(found)")
    }

    func testMarkdownHeadings() throws {
        let found = try symbols("markdown", "# Title\ntext\n```\n# not a heading\n```\n## Section\n")
        XCTAssertEqual(found.map(\.name), ["Title", "Section"])
        XCTAssertEqual(found.map(\.line), [1, 6])
    }

    func testTranslation() throws {
        XCTAssertEqual(try BoostRegex.translate("^def\\x20\\K\\w+").0, "^def\\x20(?<mpkeep>\\w+)")
        XCTAssertEqual(try BoostRegex.translate("(?'name'\\w+)").0, "(?<name>\\w+)")
        let regex = try BoostRegex("fn\\s+\\K\\w+")
        let text = "pub fn main() {}" as NSString
        XCTAssertEqual(regex.firstMatch(in: text, range: NSRange(location: 0, length: text.length)), NSRange(location: 7, length: 4))
    }
}
