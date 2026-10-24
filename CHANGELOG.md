# Changelog

All notable changes to MacPad++ are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-10-24

### Added

- Edit menu operations from Notepad++, each undone in one step and acting on the selected
  lines or, with no selection, the whole document:
  - Indent: increase (⌘]) and decrease (⌘[) line indent.
  - Convert Case To: UPPERCASE, lowercase, Proper Case, Sentence case (each also as a
    blend that keeps existing capitals), iNVERT cASE and ranDOm CasE.
  - Line Operations: duplicate (⇧⌘D), move up and down (⌥⌘↑ ⌥⌘↓), join (⌃⌘J) and split
    lines, remove duplicate, consecutive duplicate and empty lines, insert a blank line
    above (⇧⌘↩) or below (⌘↩), reverse or randomize the order, and sort 14 ways
    (alphabetically, ignoring case, in locale order, as integers, as decimals with a comma
    or a dot, and by length, each ascending or descending).
  - Comment/Uncomment: toggle (⌘/), comment and uncomment single lines, block comment
    (⌥⌘/) and block uncomment, with each language's own comment symbols.
  - Blank Operations: trim leading, trailing or both, line endings to spaces, tabs to
    spaces and spaces to tabs.
- Compare: two open tabs side by side in a new tab, with changed lines tinted, the
  changed words highlighted, F7 and ⇧F7 to move between differences and Compare Again.
  From the toolbar, the Tab menu or a tab's right-click menu.
- A password generator: the length is shared out among uppercase, lowercase, numbers and
  symbols (16 characters are 5, 5, 4 and 2 by default), optionally without ambiguous
  characters, to copy or insert at the caret. Its settings are kept.
- Toolbar buttons for Convert Case, Find, Compare, the password generator and Settings,
  customizable with Customize Toolbar…; the Classic theme draws them as Platinum buttons.
- Revert to Saved and Move Tab to Window on a tab's right-click menu and in the Tab menu.
- View ▸ Zoom, with the zoom level in the status bar (click it to go back to 100%), and
  zooming with ⌘ and the scroll wheel.

### Changed

- Tabs are drawn in the Mac style: the selected tab joins the editor, a tab's color tints
  its background, every tab can be closed, and tabs are reordered by dragging. An edited
  tab shows a dot where its close button is until you point at it.
- When there are more tabs than fit, a » button lists them all, and the selected tab
  always stays visible.
- Tabs and the buttons beside them are announced by VoiceOver.
- The README is about the app; building and releasing moved to docs/DEVELOPMENT.md.

### Fixed

- The Settings window and the password generator no longer scroll and bounce.

## [0.4.1] - 2026-10-20

### Changed

- A new app icon: the axolotl mascot with its ++, centred on a white tile.

## [0.4.0] - 2026-10-20

### Added

- Follow File (tail -f), in the View menu (⌥⌘T), like Notepad++'s Monitoring: the
  document becomes read-only and shows what other apps append to the file, staying at
  the bottom unless you scroll up. Error, warning and debug lines are colored, and
  following survives the file being truncated or rotated. It comes back with the session.
- A Tab menu with what Notepad++ has on a tab's context menu, for the front tab: pin
  (pinned tabs stay first, with a pin), rename (untitled documents get a new name, saved
  ones Save As), read-only, a tab color, reveal in Finder, open the folder in a terminal,
  copy the folder path, file name or full path, and move to the start or end. Native tabs
  keep the system's own right-click menu; with the Classic theme, right-clicking a tab
  shows the Tab menu for it, and double-clicking the free space of the tab bar opens a
  new document.
- Settings ▸ General ▸ Terminal: Terminal, iTerm, Warp, Ghostty (those installed) or a
  command of your own, with `{dir}` for the folder.
- File ▸ Print… (⌘P) and Page Setup…, with syntax colors.

### Changed

- Untitled documents take the lowest free number, as in Notepad++: after closing
  "Untitled 3", the next one is "Untitled 3" again. Their names, pins, colors and
  read-only state are kept in the session.

## [0.3.2] - 2026-10-18

### Fixed

- Opening About MacPad++ no longer quits the app. The window kept resizing itself until
  macOS stopped the app; this is also what made MacPad++ quit after waking from sleep,
  which 0.3.1 did not fix.

## [0.3.1] - 2026-10-18

### Fixed

- MacPad++ no longer quits when the Mac wakes from sleep or the displays change: the
  sidebar's layout could keep the window recalculating until macOS stopped the app.

## [0.3.0] - 2026-10-18

### Changed

- The Classic theme now dresses the whole window as Mac OS 9 Platinum: a grey frame, a
  pinstriped title bar with close, zoom and collapse boxes in place of the traffic lights,
  Platinum tabs (click to switch, close box on each, "+" for a new document), Platinum
  scroll bars with arrow buttons, and a plain grey sidebar that runs the full height of
  the window. Dialogs, menus and Settings use the dark appearance under Classic.
- The Folder Workspace / Function List switcher moved from the top of the sidebar to the
  toolbar row above it (in Classic, to the tab strip), and the lists start right below it.
- The sidebar can no longer be narrowed below 220 points, so the switcher always fits.

## [0.2.1] - 2026-10-18

### Fixed

- The app downloaded from the release DMGs no longer quits at launch: without a Developer ID,
  it is built without the hardened runtime, which refused to load the bundled Scintilla
  framework.

## [0.2.0] - 2026-10-18

### Added

- When a file open in MacPad++ is changed by another app, returning to it offers to
  reload it, keep the current version or close it. When the file was deleted (or moved
  to the Trash), it offers Save, Save As or Close Without Saving.
- Two downloads per release: a smaller Apple silicon DMG (arm64 only) and a universal
  DMG that also runs on Intel Macs.

### Fixed

- The end of long lines and the last line no longer hide under the scroll bars when
  scrolling all the way with the trackpad or mouse.
- The Settings window is titled after the selected tab instead of "Untitled".
- The find bar's match count is translated.

### Changed

- The font sample moved from Settings ▸ Editor to the Appearance preview, which now
  uses the chosen font and size.
- Shorter explanations in Settings ▸ General, with a link for helping translate the app.

## [0.1.0] - 2026-10-18

First release: a preview of Notepad++'s editing experience as a native Mac app.

### Added

- Scintilla/Lexilla editor: multiple carets, column selection, folding, brace matching.
- About 95 languages, with keywords imported from Notepad++.
- Function List for 41 languages, using Notepad++'s parsers (plus Swift, Go and Markdown).
- Find bar and Find & Replace with regular expressions; Search menu with Replace,
  Replace All and Go to Line.
- Encoding and line-ending detection and conversion.
- Native window tabs, toolbar and sidebar with Folder Workspace and Function List.
- Session snapshot: quitting never prompts; tabs and unsaved changes come back.
- Settings window and themes: Match System, Light, Dark and Classic (Mac OS 9 Platinum).
- Interface in English and Brazilian Portuguese. The app follows the macOS language or
  the one picked in Settings ▸ General; new languages are simple `.strings` files
  (see TRANSLATING.md).
- An axolotl mascot, in the app icon, the About window, the sidebar's empty states and
  the DMG window.
- Links to [macpad-plus-plus.org](https://macpad-plus-plus.org) and the GitHub
  repository in the About window and the Help menu.

[Unreleased]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/macpad-plus-plus/macpad-plus-plus/releases/tag/v0.1.0
