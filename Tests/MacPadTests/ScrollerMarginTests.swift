import Scintilla
import XCTest
@testable import MacPad

/// Long lines must not end under the vertical scroller, nor the last line under
/// the horizontal one, when scrolling all the way with the trackpad.
@MainActor
final class ScrollerMarginTests: XCTestCase {
    func testDocumentLeavesRoomForScrollers() throws {
        for style in [NSScroller.Style.legacy, .overlay] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
            let editor = ScintillaEditor(frame: window.contentView!.bounds)
            // Swift owns the window; don't let close() release it a second time.
            window.isReleasedWhenClosed = false
            window.contentView!.addSubview(editor)
            window.orderFrontRegardless()
            defer { window.close() }
            let line = (0..<40).map { "word\($0)" }.joined(separator: " ")
            editor.load(utf8: Data((0..<30).map { "\($0): \(line)" }.joined(separator: "\n").utf8), lineEnding: .lf)
            editor.scrollView.scrollerStyle = style
            window.display()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))

            let scroller = try XCTUnwrap(editor.scrollView.verticalScroller)
            let covered = editor.scrollView.contentView.frame.maxX - scroller.frame.minX
            let margin = CGFloat(editor.send(SCI_GETMARGINRIGHT))
            XCTAssertGreaterThanOrEqual(margin, covered, "style \(style.rawValue): right margin covers the scroller")

            // NSScrollView scrolls to the end of the document view: it must extend past the text by the margin.
            let documentWidth = try XCTUnwrap(editor.scrollView.documentView).frame.width
            XCTAssertGreaterThanOrEqual(documentWidth, CGFloat(editor.send(SCI_GETSCROLLWIDTH)) + margin, "style \(style.rawValue)")
        }
    }
}
