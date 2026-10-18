# Changelog

All notable changes to MacPad++ are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Interface translations: English and Brazilian Portuguese. The app follows the macOS
  language or the one picked in Settings ▸ General; new languages are simple
  `.strings` files (see TRANSLATING.md).
- Search menu items for Replace, Replace All and Go to Line.
- About panel and Help menu links to macpad-plus-plus.org and the GitHub repository.
- An axolotl mascot, shown in the new app icon, the About window, the sidebar's empty
  states and the DMG window background.

### Changed

- Settings switch tabs without delay.
- The About window is now a custom window with the mascot, links and credits.
- The project moved to the macpad-plus-plus GitHub organization.

## [0.1.0] - 2026-10-18

First preview.

### Added

- Scintilla/Lexilla editor: multiple carets, column selection, folding, brace matching.
- About 95 languages, with keywords imported from Notepad++.
- Find bar and Find & Replace with regular expressions; Search menu with Go to Line.
- Encoding and line-ending detection and conversion.
- Native window tabs, toolbar and sidebar with Folder Workspace and Function List.
- Session snapshot: quitting never prompts; tabs and unsaved changes come back.
- Settings window and themes: Match System, Light, Dark and Classic (Mac OS 9 Platinum).

[Unreleased]: https://github.com/macpad-plus-plus/macpad-plus-plus/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/macpad-plus-plus/macpad-plus-plus/releases/tag/v0.1.0
