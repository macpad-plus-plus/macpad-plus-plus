# Developing MacPad++

How to build, test and release MacPad++, and where things live in the source tree.
For translations, see [TRANSLATING.md](../TRANSLATING.md).

## Requirements

- macOS 14 or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

The Xcode project is generated from `project.yml` and is not checked in.

```sh
xcodegen generate
open MacPad.xcodeproj        # then Run the MacPad scheme
```

Or from the command line:

```sh
xcodebuild -project MacPad.xcodeproj -scheme MacPad -configuration Debug build
```

Run the tests with:

```sh
xcodebuild -project MacPad.xcodeproj -scheme MacPad test
```

If `xcode-select` points at the Command Line Tools, prefix the command with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

> Keep DerivedData outside iCloud-synced folders (such as `~/Documents`):
> the metadata iCloud adds makes code signing fail.

A development build shares its settings and session (open tabs, unsaved text) with an
installed copy of MacPad++, so don't run both at once.

## Versioning

MacPad++ follows [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.
While the version is `0.y.z`, the app is a preview and any release may change behaviour.

- The version lives in one place, `MARKETING_VERSION` in `project.yml`; the About panel
  shows it as "Version 0.1.0".
- `CURRENT_PROJECT_VERSION` is the build number, increased on every distributed build
  (needed by macOS and future auto-updates) and not shown in About.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org)
  (`feat:` → minor, `fix:` → patch, `feat!:` or `BREAKING CHANGE:` → major).
- Each release gets a `CHANGELOG.md` entry and a `vX.Y.Z` git tag.

## Releasing

1. Set `MARKETING_VERSION` in `project.yml` and move the `[Unreleased]` notes in
   `CHANGELOG.md` under a new `## [X.Y.Z] - date` heading.
2. Commit, then tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. The [Release workflow](../.github/workflows/release.yml) builds both DMGs (below) with
   [create-dmg](https://github.com/sindresorhus/create-dmg), swaps in the axolotl background
   from `AppIcon/dmg`, and publishes a GitHub Release
   with the changelog section as notes, plus SHA-256 checksums.

Each release has two DMGs: `apple-silicon` (arm64 only, about a third smaller, for M-series
Macs) and `universal` (arm64 + x86_64, for Intel Macs or anyone unsure). Build them locally
with `scripts/build-dmg.sh apple-silicon` and `scripts/build-dmg.sh universal` (needs Node 20+);
they land in `dist/`.

Without an Apple Developer ID the app is ad-hoc signed, and macOS asks users to approve it
in System Settings ▸ Privacy & Security on first launch. With a Developer ID, add the
secrets listed at the top of the release workflow and releases are signed and notarized.

## Translations

Interface text is translated with `.strings` files, one per language; `TRANSLATING.md`
explains the format for translators. After changing user-facing text, run
`scripts/update-translations.py` to regenerate the English template and mark new lines in
every language, and `scripts/update-translations.py --check` to see the coverage.

## Layout

| Path                                       | Contents                                                                                                                                               |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Sources/MacPad/App`                       | Entry point, app delegate, main menu, session store, document controller                                                                               |
| `Sources/MacPad/Document`                  | `NSDocument` subclass, encoding and line-ending handling                                                                                               |
| `Sources/MacPad/Editor`                    | `ScintillaEditor` (Swift wrapper around `ScintillaView`), search, edit operations, language catalog, themes                                            |
| `Sources/MacPad/Window`                    | Window controller (native tab groups with a drawn tab bar), toolbar, editor view controller, find bar, status bar                                       |
| `Sources/MacPad/Window/Sidebar`            | Sidebar: folder workspace and function list                                                                                                            |
| `Sources/MacPad/Compare`                   | Side-by-side comparison of two tabs                                                                                                                    |
| `Sources/MacPad/Tools`                     | Password generator                                                                                                                                     |
| `Sources/MacPad/Resources/NotepadPlusPlus` | Language definitions from Notepad++                                                                                                                    |
| `Sources/MacPad/Resources/FunctionList`    | Function-list parsers from Notepad++ (plus Swift, Go, Markdown)                                                                                        |
| `Sources/MacPad/Resources/Localization`    | Interface translations, one `<language>.lproj/Localizable.strings` per language                                                                        |
| `Sources/MacPad/Resources/Fonts`           | ChicagoFLF (public domain), for the Classic theme                                                                                                      |
| `Sources/ScintillaModule`                  | Module map that exposes Scintilla and Lexilla to Swift                                                                                                 |
| `Vendor/scintilla`, `Vendor/lexilla`       | Upstream sources (Scintilla 5.6.6, Lexilla 5.5.3) with the patches in `Vendor/PATCHES.md`                                                              |
| `Tests/MacPadTests`                        | Unit tests                                                                                                                                             |
| `scripts/update-translations.py`           | Regenerates the English template and syncs every translation                                                                                           |
| `scripts/build-dmg.sh`                     | Release build and DMG packaging                                                                                                                        |
| `scripts/render-dmg-background.swift`      | Draws the DMG window background with the axolotl (`AppIcon/dmg`)                                                                                       |
| `.github/workflows`                        | CI (build and test) and Release (DMG on version tags)                                                                                                  |
| `AppIcon`                                  | Icon source art (SVG master, small-size variant, .icns, PNGs, favicon); `AppIcon.appiconset` is copied into `Sources/MacPad/Resources/Assets.xcassets` |
| `AppIcon/axolote`                          | The axolotl mascot (with and without "++"), SVG and PNG; the "sem-plus" version appears in the sidebar's empty states                                  |
| `docs/images`                              | Screenshots used in the README                                                                                                                         |
