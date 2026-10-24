<p align="center">
  <img src="AppIcon/axolote/axolote-512.png" width="200" alt="The MacPad++ axolotl">
</p>

# macpad-plus-plus

A text editor for macOS inspired by Notepad++, with a Mac touch and new features of its own.
It runs on the same editing engine (Scintilla + Lexilla), wrapped in a native AppKit app
that follows the Mac design language.

Website: [macpad-plus-plus.org](https://macpad-plus-plus.org) ·
Downloads: [GitHub Releases](https://github.com/macpad-plus-plus/macpad-plus-plus/releases)

<p align="center">
  <img src="docs/images/main-window.png" width="800" alt="MacPad++ editing a C file in the dark theme, with several documents open as tabs">
</p>

## Yes, but why?

When I moved to macOS, most of the apps I used on Windows were available, but I couldn't
find a simple alternative to Notepad++. Every app I tried was either too complex or too
simple. And being able to keep countless notes open without ever having to save them,
the feature I missed the most, was practically nonexistent elsewhere.

So I built it (with Claude's help).

## Looking for something else?

- If you want an app that works just like Notepad++ on the Mac, my recommendation is
  [Nextpad++](https://github.com/nextpad-plus-plus/nextpad-plus-plus-macos).
- If you'd like to try another text editor, have a look at
  [OxyPad](https://github.com/oxyapps/OxyPad).

## Features

- Scintilla editing engine: multiple carets, column selection (⌥-drag), folding, brace matching
- ~95 languages, with keywords imported from Notepad++'s `langs.model.xml` / `stylers.model.xml`
- Light and dark themes that follow the system appearance and accent colour
- Find bar (⌘F) and Find & Replace (⌥⌘F): match case, whole word, regular expressions
  (`\1` or `$1` in replacements), live match count and highlighting, shared find pasteboard (⌘E)
- Encoding detection (UTF-8, UTF-8 BOM, UTF-16 LE/BE, Windows-1252) and line-ending handling
- Follow File (tail -f, ⌥⌘T): read-only, shows what is appended, colors error/warning/debug
  lines, survives truncation and rotation
- Tabs drawn in the Mac style, each with its own close button and a soft background in the
  tab's color, reordered by dragging
- Tab menu: pin, rename, read-only, tab colors, revert to saved, compare with another tab,
  reveal in Finder, open in a terminal (Terminal, iTerm, Warp, Ghostty or your own command),
  copy path, move to start/end or to another window; print with colors
- Edit menu operations from Notepad++: indent, convert case, line operations (duplicate, move,
  join, split, remove duplicate or empty lines, 14 ways to sort), comment/uncomment, and
  blank operations (trim, tabs ↔ spaces)
- Compare two tabs side by side, with changed words highlighted and next/previous difference (F7)
- Password generator: length shared out among uppercase, lowercase, numbers and symbols,
  optionally without ambiguous characters
- Toolbar shortcuts (Convert Case, Find, Compare, Password Generator, Settings), customizable
- Zoom from the View menu, ⌘-scroll or pinch, with the level shown in the status bar
- Native window tabs, with a toolbar and a sidebar (⌃⌘S):
  - Folder Workspace (⇧⌘O): file tree of one or more folders, live-updated, drag and drop
  - Function List: Notepad++'s function-list parsers (38 languages, plus Swift, Go and Markdown),
    grouped by class, with a filter
- Search menu: Find, Replace, Replace All, Go to Line (⌘L)
- Settings (⌘,): font, tabs/spaces, line numbers, current line, indentation guides, wrapping,
  session, hidden files, defaults for new documents
- Interface in English and Brazilian Portuguese, following the macOS language or chosen in
  Settings; more languages are simple text files anyone can add ([TRANSLATING.md](TRANSLATING.md))
- Themes: Match System, Light, Dark and Classic (Mac OS 9 Platinum: pinstriped title bar with
  close, zoom and collapse boxes, Platinum tabs and scroll bars, Monaco, lavender highlight,
  Chicago font)
- Session snapshot: quitting never prompts; open tabs, unsaved changes and untitled
  documents come back on the next launch (backed up every 7 seconds)

Session data lives in `~/Library/Application Support/MacPad++/`.

## Download

Get the latest version from [GitHub Releases](https://github.com/macpad-plus-plus/macpad-plus-plus/releases).
MacPad++ needs macOS 14 or later. Each release has two DMGs: `apple-silicon` for M-series
Macs, and `universal` for Intel Macs or if you're not sure.

The app is not yet signed with an Apple Developer ID, so on first launch macOS asks you to
approve it in System Settings ▸ Privacy & Security.

## Translations

The interface is available in English and Brazilian Portuguese. Adding a language takes
only a text file, no programming: see [TRANSLATING.md](TRANSLATING.md).

## Development

Building, testing, releasing and the source layout are covered in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Credits

- [Notepad++](https://notepad-plus-plus.org) by Don Ho, the inspiration, and the source of
  the language definitions and function-list parsers.
- [Scintilla and Lexilla](https://www.scintilla.org) by Neil Hodgson, the editing engine.
- [ChicagoFLF](Sources/MacPad/Resources/Fonts/ChicagoFLF-LICENSE.txt) by Robin Casady
  (public domain), the font of the Classic theme.
- The side-by-side comparison is ported from [OxyPad](https://github.com/oxyapps/OxyPad).
- Built with [Claude](https://claude.ai).

## License

GPL v3, like Notepad++, from which the language definitions and function-list
parsers are taken.
Scintilla and Lexilla are under their own permissive license (see
`Vendor/*/License.txt`). Details in [LICENSE](LICENSE).
