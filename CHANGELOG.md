# Changelog

All notable changes to MacPad++ are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/macpad-plus-plus/macpad-plus-plus/releases/tag/v0.1.0
