import XCTest
@testable import MacPad

final class PasswordGeneratorTests: XCTestCase {
    private func count(_ password: String, in set: String) -> Int {
        password.filter { set.contains($0) }.count
    }

    func testLengthAndMinimums() throws {
        let generator = PasswordGenerator(length: 16, minimumUppercase: 3, minimumLowercase: 2, minimumDigits: 4, minimumSymbols: 5)
        for _ in 0..<200 {
            let password = try XCTUnwrap(generator.generate())
            XCTAssertEqual(password.count, 16)
            XCTAssertGreaterThanOrEqual(count(password, in: PasswordGenerator.uppercase), 3)
            XCTAssertGreaterThanOrEqual(count(password, in: PasswordGenerator.lowercase), 2)
            XCTAssertGreaterThanOrEqual(count(password, in: PasswordGenerator.digits), 4)
            XCTAssertGreaterThanOrEqual(count(password, in: PasswordGenerator.symbols), 5)
        }
    }

    func testZeroMinimumLeavesKindOut() throws {
        let generator = PasswordGenerator(length: 64, minimumUppercase: 0, minimumLowercase: 1, minimumDigits: 1, minimumSymbols: 0)
        for _ in 0..<50 {
            let password = try XCTUnwrap(generator.generate())
            XCTAssertEqual(count(password, in: PasswordGenerator.uppercase), 0)
            XCTAssertEqual(count(password, in: PasswordGenerator.symbols), 0)
        }
    }

    func testExcludeAmbiguous() throws {
        let generator = PasswordGenerator(length: 128, excludeAmbiguous: true)
        for _ in 0..<50 {
            let password = try XCTUnwrap(generator.generate())
            XCTAssertEqual(count(password, in: PasswordGenerator.ambiguous), 0)
        }
    }

    func testProblems() {
        XCTAssertEqual(PasswordGenerator(minimumUppercase: 0, minimumLowercase: 0, minimumDigits: 0, minimumSymbols: 0).problem, .noKinds)
        XCTAssertEqual(PasswordGenerator(length: 4, minimumUppercase: 2, minimumLowercase: 2, minimumDigits: 1, minimumSymbols: 0).problem,
                       .minimumsExceedLength)
        // Minimums that fill the length exactly are fine.
        XCTAssertEqual(PasswordGenerator(length: 4, minimumUppercase: 2, minimumLowercase: 2, minimumDigits: 0, minimumSymbols: 0)
            .generate()?.count, 4)
    }

    // MARK: Distribution

    func testDefaultsAreFiveFiveFourTwo() {
        let generator = PasswordGenerator()
        XCTAssertEqual(generator.length, 16)
        XCTAssertEqual(generator.counts, [5, 5, 4, 2])
    }

    func testLengthIsSharedOutInProportion() {
        var generator = PasswordGenerator()
        generator.setLength(20)
        XCTAssertEqual(generator.counts, [6, 6, 5, 3])
        generator.setLength(32)
        XCTAssertEqual(generator.counts, [10, 10, 8, 4])
        generator.setLength(4)
        XCTAssertEqual(generator.counts, [1, 1, 1, 1])
        for length in PasswordGenerator.lengthRange {
            generator.setLength(length)
            XCTAssertEqual(generator.counts.reduce(0, +), length)
        }
    }

    func testKindsLeftOutStayOut() {
        var generator = PasswordGenerator()
        generator.setCount(0, at: 3)
        XCTAssertEqual(generator.counts, [6, 6, 4, 0])
        generator.setLength(28)
        XCTAssertEqual(generator.counts[3], 0)
        XCTAssertEqual(generator.counts.reduce(0, +), 28)
    }

    func testSettingAKindAdjustsTheOthers() {
        var generator = PasswordGenerator()
        generator.setCount(8, at: 2)
        XCTAssertEqual(generator.length, 16)
        XCTAssertEqual(generator.counts[2], 8)
        XCTAssertEqual(generator.counts.reduce(0, +), 16)
        // Others keep at least one each.
        generator.setCount(16, at: 0)
        XCTAssertEqual(generator.counts, [13, 1, 1, 1])
        // A kind left out comes back by taking from the others.
        generator.setCount(0, at: 3)
        generator.setCount(3, at: 3)
        XCTAssertEqual(generator.counts[3], 3)
        XCTAssertEqual(generator.counts.reduce(0, +), 16)
    }

    func testTheOnlyKindKeepsTheWholeLength() {
        var generator = PasswordGenerator(length: 10, minimumUppercase: 0, minimumLowercase: 10, minimumDigits: 0, minimumSymbols: 0)
        generator.setCount(4, at: 1)
        XCTAssertEqual(generator.counts, [0, 10, 0, 0])
    }
}
