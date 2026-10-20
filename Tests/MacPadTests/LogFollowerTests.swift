import XCTest
@testable import MacPad

final class LogFollowerTests: XCTestCase {
    private var directory: URL!
    private var url: URL { directory.appending(path: "app.log") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "MacPadFollowerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private func string(_ event: LogFollower.Event?) -> String? {
        switch event {
        case .appended(let data): String(decoding: data, as: UTF8.self)
        case .reset(let data, _): String(decoding: data, as: UTF8.self)
        case nil: nil
        }
    }

    func testReturnsOnlyAppendedText() throws {
        try Data("one\ntwo\n".utf8).write(to: url)
        let (follower, initial) = try LogFollower.open(url, initialBytes: 1024)
        XCTAssertEqual(String(decoding: initial, as: UTF8.self), "one\ntwo\n")
        XCTAssertNil(try follower.poll())
        try append("three\n")
        XCTAssertEqual(string(try follower.poll()), "three\n")
        XCTAssertNil(try follower.poll())
    }

    func testStartsAtALineWhenTheFileIsCut() throws {
        try Data("first line\nsecond line\nthird\n".utf8).write(to: url)
        let (_, initial) = try LogFollower.open(url, initialBytes: 15)
        XCTAssertEqual(String(decoding: initial, as: UTF8.self), "third\n")
    }

    func testSurvivesTruncation() throws {
        try Data("a long first version\n".utf8).write(to: url)
        let (follower, _) = try LogFollower.open(url, initialBytes: 1024)
        // Truncated in place, as `> app.log` does: same file, shorter.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("new\n".utf8))
        try handle.close()
        let event = try follower.poll()
        XCTAssertEqual(string(event), "new\n")
        if case .reset(_, let reason) = event { XCTAssertEqual(reason, .truncated) } else { XCTFail("\(String(describing: event))") }
    }

    func testSurvivesRotation() throws {
        try Data("old\n".utf8).write(to: url)
        let (follower, _) = try LogFollower.open(url, initialBytes: 1024)
        try FileManager.default.moveItem(at: url, to: directory.appending(path: "app.log.1"))
        // Missing for a moment: nothing happens.
        XCTAssertNil(try follower.poll())
        try Data("fresh start\n".utf8).write(to: url)
        let event = try follower.poll()
        XCTAssertEqual(string(event), "fresh start\n")
        if case .reset(_, let reason) = event { XCTAssertEqual(reason, .rotated) } else { XCTFail("\(String(describing: event))") }
    }
}
