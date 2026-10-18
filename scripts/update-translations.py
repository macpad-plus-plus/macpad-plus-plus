#!/usr/bin/env python3 -I
"""Keeps the translation files in sync with the source code.

    scripts/update-translations.py            # regenerate en, sync every language
    scripts/update-translations.py --check    # only report coverage; exit 1 if files are stale

1. Extracts every user-facing string with `xcodebuild -exportLocalizations`
   (String(localized:) in AppKit code and string literals in SwiftUI views).
2. Rewrites Resources/Localization/en.lproj/Localizable.strings, the template
   translators copy (like Notepad++'s english.xml).
3. For each other language, keeps existing translations in template order, adds
   new strings marked /* TODO: translate */ with the English text, and drops
   strings the app no longer uses.

Maintainers run it after changing UI text; translators only edit .strings files.
"""
import os
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALIZATION = ROOT / "Sources/MacPad/Resources/Localization"
TABLE = "Localizable.strings"
TODO = "/* TODO: translate */"
ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')

HEADER = """\
/*
 MacPad++ interface strings: {name}

 Each line is  "English text" = "Translation";
 - Translate only the text on the right, and keep it between quotes.
 - Keep placeholders such as %@ and %lld: they are replaced by names and numbers.
 - Inside quotes, write \\" for a quote and \\n for a line break.
 - Lines marked TODO still show English in the app.

 See TRANSLATING.md. This file is kept in sync by scripts/update-translations.py.
*/

"""


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def extract_keys():
    """English source strings, in the order Xcode reports them."""
    # Xcode's export merges our own template into the code's strings, so stale
    # keys would never disappear: empty the template while exporting.
    template = LOCALIZATION / "en.lproj" / TABLE
    saved = template.read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ)
        env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
        subprocess.run(["xcodegen", "generate", "--quiet"], cwd=ROOT, check=True)
        template.write_text("", encoding="utf-8")
        try:
            subprocess.run(
                ["xcodebuild", "-exportLocalizations", "-project", "MacPad.xcodeproj",
                 "-localizationPath", tmp, "-exportLanguage", "en"],
                cwd=ROOT, env=env, check=True, stdout=subprocess.DEVNULL)
        finally:
            template.write_text(saved, encoding="utf-8")
        xliff = next(Path(tmp).rglob("en.xliff"))
        namespace = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
        keys = []
        for file in ET.parse(xliff).getroot().findall("x:file", namespace):
            # The app's table only (the Scintilla framework has its own).
            if not file.get("original", "").startswith("Sources/MacPad/") or not file.get("original", "").endswith(TABLE):
                continue
            for unit in file.iter(f"{{{namespace['x']}}}trans-unit"):
                key = unit.get("id")
                if key and key not in keys:
                    keys.append(key)
        return sorted(keys, key=str.casefold)


def read_strings(path):
    """{escaped key: (escaped value, translated?)} from a .strings file."""
    entries = {}
    if not path.exists():
        return entries
    pending_todo = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if TODO in line:
            pending_todo = True
        # Entries start the line; the header's example line is indented.
        match = ENTRY.match(line)
        if match:
            entries[match.group(1)] = (match.group(2), not pending_todo)
            pending_todo = False
    return entries


def language_name(code):
    names = {"en": "English (template)", "pt-BR": "Português (Brasil)"}
    return names.get(code, code)


def render(code, keys, existing):
    lines = [HEADER.format(name=language_name(code))]
    translated = 0
    for key in keys:
        escaped = escape(key)
        value, done = existing.get(escaped, (escaped, False))
        if code == "en":
            lines.append(f'"{escaped}" = "{escaped}";\n')
            continue
        if done:
            translated += 1
            lines.append(f'"{escaped}" = "{value}";\n')
        else:
            lines.append(f'{TODO}\n"{escaped}" = "{escaped}";\n')
    return "".join(lines), translated


def main():
    check = "--check" in sys.argv
    keys = extract_keys()
    if len(keys) < 50:
        sys.exit(f"error: only {len(keys)} strings extracted; refusing to rewrite translations")
    stale = False
    print(f"{len(keys)} strings")
    for folder in sorted(LOCALIZATION.glob("*.lproj")):
        code = folder.name.removesuffix(".lproj")
        path = folder / TABLE
        existing = read_strings(path)
        content, translated = render(code, keys, existing)
        obsolete = [k for k in existing if k not in {escape(k2) for k2 in keys}]
        current = path.read_text(encoding="utf-8") if path.exists() else ""
        if content != current:
            stale = True
            if not check:
                path.write_text(content, encoding="utf-8")
        if code != "en":
            percent = 100 * translated // max(len(keys), 1)
            note = f", {len(obsolete)} obsolete removed" if obsolete and not check else ""
            print(f"  {code:8} {translated:4}/{len(keys)} translated ({percent}%){note}")
    if check and stale:
        print("Translation files are out of date: run scripts/update-translations.py")
        sys.exit(1)


if __name__ == "__main__":
    main()
