import Foundation

/// Follows a growing file, like `tail -F`: each poll returns only what was
/// appended since the last one, and following survives the file being
/// truncated (`> app.log`) or rotated (renamed and recreated by logrotate and
/// most logging frameworks).
///
/// It is polled rather than driven by file-system events on purpose: events
/// are unreliable on network volumes, and a stat call every few hundred
/// milliseconds is cheap. Not thread-safe: poll it from one queue.
final class LogFollower: @unchecked Sendable {
    enum ResetReason: Equatable, Sendable {
        case truncated
        case rotated
    }

    enum Event: Equatable, Sendable {
        /// New bytes at the end of the file.
        case appended(Data)
        /// The file started over; this is its new content (its last bytes).
        case reset(Data, ResetReason)
    }

    /// Upper bound of bytes returned by one poll, so a burst of logging never
    /// blocks the interface with a giant chunk; the rest comes next poll.
    static let maxChunk = 4 * 1024 * 1024

    let url: URL
    /// How much of the end of a file is read when following starts or the
    /// file starts over.
    let initialBytes: Int
    private var offset: UInt64
    private var identity: FileIdentity?

    private struct FileIdentity: Equatable {
        var device: UInt64
        var inode: UInt64
    }

    /// Opens `url` and returns the follower with the file's last
    /// `initialBytes` bytes, starting at a line boundary when cut.
    static func open(_ url: URL, initialBytes: Int) throws -> (LogFollower, Data) {
        let follower = LogFollower(url: url, initialBytes: initialBytes)
        let (data, size) = try follower.readTail()
        follower.offset = size
        return (follower, data)
    }

    private init(url: URL, initialBytes: Int) {
        self.url = url
        self.initialBytes = initialBytes
        offset = 0
    }

    /// What changed since the last poll, or nil when nothing did or the file
    /// is missing for now (it is waited for, as during a rotation).
    func poll() throws -> Event? {
        guard let (size, identity) = Self.fileStatus(url) else { return nil }
        if identity != self.identity {
            let (data, end) = try readTail()
            offset = end
            return .reset(data, .rotated)
        }
        if size < offset {
            let (data, end) = try readTail()
            offset = end
            return .reset(data, .truncated)
        }
        guard size > offset else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: Int(min(size - offset, UInt64(Self.maxChunk)))) ?? Data()
        offset += UInt64(data.count)
        return data.isEmpty ? nil : .appended(data)
    }

    /// The last `initialBytes` of the file and where the file ends.
    private func readTail() throws -> (Data, UInt64) {
        guard let (_, identity) = Self.fileStatus(url) else { throw CocoaError(.fileNoSuchFile) }
        self.identity = identity
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let start = size > UInt64(initialBytes) ? size - UInt64(initialBytes) : 0
        try handle.seek(toOffset: start)
        var data = try handle.read(upToCount: Int(size - start)) ?? Data()
        // A cut start: drop the partial first line.
        if start > 0, let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
            data = data[data.index(after: newline)...]
        }
        return (Data(data), try handle.offset())
    }

    /// The file's size and identity; nil while it does not exist.
    private static func fileStatus(_ url: URL) -> (UInt64, FileIdentity)? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return (UInt64(info.st_size), FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino)))
    }
}
