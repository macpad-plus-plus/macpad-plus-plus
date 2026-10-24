import XCTest
@testable import MacPad

final class TabStripLayoutTests: XCTestCase {
    private func make(count: Int, selected: Int?, available: CGFloat, first: inout Int) -> TabStripLayout {
        TabStripLayout.make(count: count, selected: selected, available: available, minWidth: 90, maxWidth: 200,
                            overflowWidth: 40, first: &first)
    }

    func testEverythingFits() {
        var first = 3
        let layout = make(count: 4, selected: 0, available: 1000, first: &first)
        XCTAssertEqual(layout.visible, 0..<4)
        XCTAssertEqual(layout.width, 200)
        XCTAssertFalse(layout.overflows)
        XCTAssertEqual(first, 0)
    }

    func testTabsShrinkBeforeOverflowing() {
        var first = 0
        let layout = make(count: 10, selected: 0, available: 1000, first: &first)
        XCTAssertEqual(layout.visible, 0..<10)
        XCTAssertEqual(layout.width, 100)
    }

    func testOverflowKeepsTheSelectedTabVisible() {
        var first = 0
        // 960 points minus the overflow button fit 10 tabs of at least 90.
        var layout = make(count: 40, selected: 25, available: 960, first: &first)
        XCTAssertTrue(layout.overflows)
        XCTAssertEqual(layout.visible.count, 10)
        XCTAssertTrue(layout.visible.contains(25))
        XCTAssertGreaterThanOrEqual(layout.width, 90)

        // Selecting a tab already shown does not scroll the strip.
        let shown = layout.visible
        layout = make(count: 40, selected: shown.lowerBound + 1, available: 960, first: &first)
        XCTAssertEqual(layout.visible, shown)

        // Selecting one before the window brings it to the start.
        layout = make(count: 40, selected: 2, available: 960, first: &first)
        XCTAssertEqual(layout.visible.lowerBound, 2)
    }

    func testAlwaysShowsAtLeastOneTab() {
        var first = 0
        let layout = make(count: 5, selected: 4, available: 60, first: &first)
        XCTAssertEqual(layout.visible, 4..<5)
    }
}
