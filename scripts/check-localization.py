#!/usr/bin/env python3
"""Localization check for Versoline (standard library only).

1. en.lproj and tr.lproj Localizable.strings must define exactly the same keys, no key may be
   defined twice in one file, and each key must use the same format specifiers in both languages.
2. Every user-facing string literal in Sources/**/*.swift must have a key in both files.
   Literals are found in SwiftUI initialisers/modifiers that take a localized key
   (Text, Button, Label, Toggle, Section, ...) and in String(localized:).
   Literals with interpolation are matched loosely: every \\(...) and every format specifier
   (%@, %lld, %d, ...) counts as the same placeholder, because SwiftUI derives the exact specifier
   from the argument type.

Strings that are intentionally not translated (brand names, feed titles, symbols) go in
scripts/localization-allowlist.txt, one literal per line.

Exit status: 0 when clean, 1 when keys are missing or the two files differ.
Usage: scripts/check-localization.py [--list]   (--list prints every missing key)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
STRINGS = {lang: SOURCES / "Resources" / f"{lang}.lproj" / "Localizable.strings" for lang in ("en", "tr")}
ALLOWLIST = Path(__file__).resolve().parent / "localization-allowlist.txt"

KEY_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)

# Calls whose first string-literal argument is a localized key.
CALLERS = (
    "Text|Button|Label|Toggle|Section|Picker|TextField|SecureField|Menu|Link|GroupBox|DisclosureGroup|"
    "LabeledContent|ProgressView|ContentUnavailableView|Stepper|DatePicker|"
    "navigationTitle|navigationSubtitle|help|alert|confirmationDialog|sheet|"
    "accessibilityLabel|accessibilityHint|badge|prompt|placeholder"
)
LITERAL_RE = re.compile(r'\b(?:' + CALLERS + r')\(\s*"((?:[^"\\]|\\.)*)"')
LOCALIZED_RE = re.compile(r'String\(\s*localized:\s*"((?:[^"\\]|\\.)*)"')


def unescape(s: str) -> str:
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")


def load_keys(path: Path) -> dict:
    return {unescape(k): unescape(v) for k, v in KEY_RE.findall(path.read_text(encoding="utf-8"))}


def load_allowlist() -> set:
    if not ALLOWLIST.exists():
        return set()
    return {l.rstrip("\n") for l in ALLOWLIST.read_text(encoding="utf-8").splitlines() if l and not l.startswith("#")}


INTERP_RE = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")
FORMAT_RE = re.compile(r"%(?:\d+\$)?(?:l{0,2}[dfiu]|@)")


def shape(key: str) -> str:
    """Key with every interpolation / format specifier replaced by a neutral placeholder."""
    return FORMAT_RE.sub("%", INTERP_RE.sub("%", key))


def is_translatable(s: str) -> bool:
    # Needs at least two letters in a row; skips symbols, numbers, punctuation-only text.
    return re.search(r"[^\W\d_]{2,}", s) is not None


def collect_literals():
    plain, interpolated = {}, {}
    for path in sorted(SOURCES.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for rx in (LITERAL_RE, LOCALIZED_RE):
            for m in rx.finditer(text):
                raw = m.group(1)
                line = text.count("\n", 0, m.start()) + 1
                where = f"{path.relative_to(ROOT)}:{line}"
                target = interpolated if "\\(" in raw else plain
                target.setdefault(unescape(raw), where)
    return plain, interpolated


def main() -> int:
    show_all = "--list" in sys.argv
    en, tr = load_keys(STRINGS["en"]), load_keys(STRINGS["tr"])
    allow = load_allowlist()
    failed = False

    for lang, path in STRINGS.items():
        raw = [unescape(k) for k, _ in KEY_RE.findall(path.read_text(encoding="utf-8"))]
        dupes = sorted({k for k in raw if raw.count(k) > 1})
        if dupes:
            failed = True
            print(f"Duplicate keys in {lang}.lproj: {dupes}")
    for k in sorted(set(en) & set(tr)):
        if sorted(FORMAT_RE.findall(en[k])) != sorted(FORMAT_RE.findall(tr[k])):
            failed = True
            print(f"Format specifiers differ for {k!r}: en={en[k]!r} tr={tr[k]!r}")

    only_en, only_tr = sorted(set(en) - set(tr)), sorted(set(tr) - set(en))
    if only_en or only_tr:
        failed = True
        print(f"Key mismatch between en and tr ({len(only_en)} only in en, {len(only_tr)} only in tr):")
        for k in only_en:
            print(f"  only in en: {k!r}")
        for k in only_tr:
            print(f"  only in tr: {k!r}")

    plain, interpolated = collect_literals()
    missing = {k: w for k, w in plain.items() if is_translatable(k) and k not in tr and k not in allow}
    if missing:
        failed = True
        print(f"{len(missing)} UI string(s) have no key in tr.lproj/Localizable.strings:")
        for k, w in (sorted(missing.items(), key=lambda kv: kv[1]) if show_all else sorted(missing.items(), key=lambda kv: kv[1])[:25]):
            print(f"  {w}: {k!r}")
        if not show_all and len(missing) > 25:
            print(f"  ... and {len(missing) - 25} more (run with --list)")

    tr_shapes = {shape(k) for k in tr}
    missing_fmt = {k: w for k, w in interpolated.items()
                   if is_translatable(INTERP_RE.sub("", k)) and shape(k) not in tr_shapes and k not in allow}
    if missing_fmt:
        failed = True
        print(f"{len(missing_fmt)} interpolated UI string(s) have no matching key in tr.lproj/Localizable.strings:")
        for k, w in sorted(missing_fmt.items(), key=lambda kv: kv[1]):
            print(f"  {w}: {k!r}")

    if not failed:
        print(f"OK: {len(tr)} keys, en and tr match, no untranslated UI literals.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
