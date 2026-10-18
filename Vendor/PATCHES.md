# Changes to the vendored sources

`scintilla/` (5.6.6) and `lexilla/` (5.5.3) are the upstream releases from
[scintilla.org](https://www.scintilla.org), with the patches below. Re-apply them when
updating, and keep this list current.

## cocoa/ScintillaCocoa.mm — room for the scrollers

`ScintillaCocoa::SetScrollingSize` sizes the scroll view's document view. On macOS the
clip view extends under the scrollers, and trackpad scrolling can reach the very end of
the document view, so the end of long lines ended up under the vertical scroller and the
last line under the horizontal one.

The patch widens the document view by the right margin (`SCI_SETMARGINRIGHT`, which
MacPad++ sizes to the scroller in `ScintillaEditor.updateScrollerMargin()`), and, when
lines overflow horizontally, makes it taller by the horizontal scroller's height.
Covered by `ScrollerMarginTests`. Search for "MacPad++ patch" to find it.
