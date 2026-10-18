# Translating MacPad++

MacPad++ can be translated into any language, like Notepad++. Each language is a
single text file, and you don't need Xcode or any programming knowledge to write one.

## How translations work

Every language lives in its own folder:

```
Sources/MacPad/Resources/Localization/
├── en.lproj/Localizable.strings      ← English template (do not translate this one)
├── pt-BR.lproj/Localizable.strings   ← Português (Brasil)
└── …
```

Each line pairs the English text with its translation:

```
/* Search menu */
"Find…" = "Buscar…";
"Replace All" = "Substituir Tudo";
"Ln %lld, Col %lld" = "Lin %lld, Col %lld";
```

Only change the text on the **right**. The left side is how the app finds the line.

The app follows the macOS language by default. People can also pick a language in
**MacPad++ ▸ Settings ▸ General ▸ Interface Language**. Any line that is missing or
marked `TODO` falls back to English.

## Adding a new language

1. Copy `en.lproj` to a folder named after the language code, for example
   `fr.lproj` (French), `es.lproj` (Spanish), `de.lproj` (German), `zh-Hans.lproj`
   (Simplified Chinese) or `pt-PT.lproj` (European Portuguese). Use the codes Apple
   lists in [Language and region IDs](https://developer.apple.com/documentation/xcode/choosing-localization-regions-and-scripts).
2. Translate the right-hand side of every line in `Localizable.strings`.
3. Open a pull request. The CI checks that the file is valid; if you can, run the
   app and look at your language in Settings.

## Updating a language

When the app gains new text, the maintainers run `scripts/update-translations.py`,
which adds the new lines to every language marked with `/* TODO: translate */`.
Search for `TODO`, translate those lines, delete the `TODO` comment above each one,
and open a pull request.

## Rules that keep the app working

- **Keep placeholders.** `%@` (text) and `%lld` (number) are filled in by the app.
  Keep the same ones, in any order that suits your language:
  `"Length: %@  ·  Lines: %@"` → `"Tamanho: %@  ·  Linhas: %@"`.
- **Keep links.** Some lines contain Markdown links, `[text](url)`. Translate the
  text in brackets, but leave the address in parentheses as it is.
- **Escape quotes and backslashes.** Inside the quotes, write `\"` for a quote and
  `\\` for a backslash. Curly quotes (“ ”) need no escaping.
- **Keep the ellipsis.** Menu items ending in `…` open a window or ask for more
  input; keep the `…` (a single character) in the translation.
- **Follow the system's words.** Use the same terms macOS uses in your language
  (for example the names of Edit menu items), so MacPad++ feels at home next to
  other apps.
- **Not translated:** programming language names (C++, Python…), encoding names
  (UTF-8…) and keyboard shortcuts.

The `TranslationTests` unit test rejects files that do not parse, contain lines that
are not in the English template, or change placeholders.

## For maintainers

- Text in AppKit code goes through `String(localized: "…")`. String literals in
  SwiftUI views (`Text("…")`, `Toggle("…")`) are localized automatically.
- Interpolations become placeholders: `String(localized: "Ln \(line)")` is the key
  `"Ln %lld"`.
- After changing UI text, run `scripts/update-translations.py` and commit the
  updated `.strings` files. CI runs it with `--check` and fails when they are stale.
- If one English word needs two translations (for example "Language" for programming
  languages and for the interface language), use two different English texts.
