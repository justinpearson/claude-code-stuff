#!/usr/bin/env python3
"""Inspect non-ASCII characters in a text file and optionally replace them
with ASCII equivalents (em-dash -> --, curly quotes -> straight, etc).
"""

import subprocess
import sys
import os
import shutil
import unicodedata
from collections import Counter

RED = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
BLUE = "\033[34m"  # dark (normal) blue, not bright
MAGENTA = "\033[95m"
LABEL = BLUE       # for line:col labels and menu keys
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"

# Curated replacements that beat NFKD/unidecode for these cases
REPLACEMENTS = {
    # Dashes / hyphens
    "‐": "-", "‑": "-", "‒": "-", "–": "-",
    "—": "--", "―": "--", "−": "-",
    # Single quotes
    "‘": "'", "’": "'", "‚": "'", "‛": "'",
    "‹": "'", "›": "'",
    # Double quotes
    "“": '"', "”": '"', "„": '"', "‟": '"',
    "«": '"', "»": '"',
    # Spaces (collapsible)
    " ": " ", " ": " ", " ": " ", " ": " ",
    " ": " ", " ": " ", " ": " ", " ": " ",
    " ": " ", " ": " ", " ": " ", " ": " ",
    " ": " ", " ": " ", "　": " ",
    # Zero-width / BOM (drop)
    "​": "", "‌": "", "‍": "", "﻿": "",
    # Punctuation
    "…": "...", "•": "*", "‣": ">", "·": "*",
    "‧": "*",
    # Symbols
    "©": "(c)", "®": "(R)", "™": "(TM)",
    "°": " deg", "±": "+/-", "×": "x", "÷": "/",
    "≠": "!=", "≤": "<=", "≥": ">=",
    "¼": "1/4", "½": "1/2", "¾": "3/4",
    # Currency
    "€": "EUR", "£": "GBP", "¥": "JPY", "¢": "c",
    # Arrows
    "←": "<-", "→": "->", "↑": "^", "↓": "v",
    "⇐": "<=", "⇒": "=>", "⇔": "<=>",
    # Stars / checks
    "★": "*", "☆": "*", "✓": "Y", "✔": "Y",
    "✗": "X", "✘": "X",
    # Emoji - common faces
    "\U0001F600": ":)",  "\U0001F601": ":D", "\U0001F602": ":')",
    "\U0001F923": ":')", "\U0001F603": ":D", "\U0001F604": ":D",
    "\U0001F605": ":')", "\U0001F606": ":D", "\U0001F60A": ":)",
    "\U0001F642": ":)",  "\U0001F609": ";)", "\U0001F60D": "<3",
    "\U0001F618": ":*",  "\U0001F61C": ";P", "\U0001F60E": "B)",
    "\U0001F622": ":'(", "\U0001F62D": ":'(", "\U0001F61E": ":(",
    "\U0001F61F": ":(",  "\U0001F641": ":(", "☹": ":(",
    "\U0001F621": ">:(", "\U0001F620": ">:(", "\U0001F631": ":O",
    "\U0001F62E": ":O",  "\U0001F62F": ":O", "\U0001F610": ":|",
    "\U0001F611": ":|",  "\U0001F615": ":/", "\U0001F914": ":?",
    # Hearts / thumbs
    "❤": "<3", "♥": "<3", "\U0001F494": "</3",
    "\U0001F44D": "+1", "\U0001F44E": "-1",
}


def _box_drawing_ascii(ch: str) -> str | None:
    """Map box-drawing (U+2500-257F) and block-element (U+2580-259F) chars
    to a sensible ASCII glyph based on the Unicode name."""
    cp = ord(ch)
    if 0x2580 <= cp <= 0x259F:
        return "#"
    if not (0x2500 <= cp <= 0x257F):
        return None
    try:
        name = unicodedata.name(ch)
    except ValueError:
        return "+"
    # Anything with " AND " in the name connects 2+ directions -> junction
    if " AND " in name:
        return "+"
    if "HORIZONTAL" in name:
        return "-"
    if "VERTICAL" in name:
        return "|"
    if "DIAGONAL" in name:
        return "X" if "CROSS" in name else "/"
    if "ARC" in name:
        return "+"
    return "+"


def ascii_equivalent(ch: str) -> str:
    """Return an ASCII substitute for one non-ASCII character (may be empty)."""
    if ch in REPLACEMENTS:
        return REPLACEMENTS[ch]
    box = _box_drawing_ascii(ch)
    if box is not None:
        return box
    decomposed = unicodedata.normalize("NFKD", ch)
    stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
    return stripped.encode("ascii", "ignore").decode("ascii")


def char_name(ch: str) -> str:
    try:
        return unicodedata.name(ch)
    except ValueError:
        return f"U+{ord(ch):04X}"


def find_non_ascii(text: str):
    """Yield (line_no, col, ch, line) for every non-ASCII char."""
    for i, line in enumerate(text.splitlines(), start=1):
        for j, ch in enumerate(line):
            if ord(ch) > 127:
                yield i, j, ch, line


def show_context(line: str, col: int, ch: str, width: int = 70) -> str:
    before = line[:col]
    after = line[col + 1:]
    # Truncate so the highlighted char stays visible
    if len(before) > width:
        before = "..." + before[-width:]
    if len(after) > width:
        after = after[:width] + "..."
    return f"{DIM}{before}{RESET}{BOLD}{RED}{ch}{RESET}{DIM}{after}{RESET}"


def display_repl(repl: str) -> str:
    if repl == "":
        return f"{YELLOW}(remove){RESET}"
    return f"{GREEN}{repl!r}{RESET}"


def read_clipboard() -> str:
    """Read the macOS clipboard via pbpaste; raise on failure."""
    result = subprocess.run(
        ["pbpaste"], capture_output=True, check=True, text=True
    )
    return result.stdout


def main() -> int:
    if len(sys.argv) > 2 or (len(sys.argv) == 2 and sys.argv[1] in ("-h", "--help")):
        print("Usage: asciiize [filename]   (no arg: read from clipboard)",
              file=sys.stderr)
        return 1

    path: str | None = None
    if len(sys.argv) == 2:
        path = sys.argv[1]
        if not os.path.isfile(path):
            print(f"{RED}Error:{RESET} file not found: {path}", file=sys.stderr)
            return 1
        try:
            with open(path, "r", encoding="utf-8") as f:
                text = f.read()
        except UnicodeDecodeError as e:
            print(f"{RED}Error:{RESET} {path} is not valid UTF-8 ({e})",
                  file=sys.stderr)
            return 1
    else:
        print(f"No file given. Read from clipboard? {LABEL}[y/N]{RESET}")
        try:
            answer = input("> ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            return 0
        if answer not in ("y", "yes"):
            print("no input; exiting")
            return 0
        try:
            text = read_clipboard()
        except (FileNotFoundError, subprocess.CalledProcessError) as e:
            print(f"{RED}Error:{RESET} could not read clipboard ({e})",
                  file=sys.stderr)
            return 1
        if not text:
            print("clipboard is empty")
            return 0

    occurrences = list(find_non_ascii(text))

    source = path if path else "clipboard"

    if not occurrences:
        print(f"{GREEN}OK{RESET} no non-ASCII characters in {BOLD}{source}{RESET}")
        return 0

    print(f"{BOLD}{LABEL}Non-ASCII characters in {source}:{RESET}\n")
    for line_no, col, ch, line in occurrences:
        repl = ascii_equivalent(ch)
        print(f"  {LABEL}line {line_no}:{col + 1}{RESET}  "
              f"{BOLD}{RED}{ch}{RESET} U+{ord(ch):04X} "
              f"{DIM}({char_name(ch)}){RESET} -> {display_repl(repl)}")
        print(f"    {show_context(line, col, ch)}")

    counts = Counter(ch for _, _, ch, _ in occurrences)
    print(f"\n{BOLD}Summary:{RESET}")
    print(f"  total non-ASCII chars : {BOLD}{len(occurrences)}{RESET}")
    print(f"  unique non-ASCII chars: {BOLD}{len(counts)}{RESET}")
    for ch, n in counts.most_common():
        repl = ascii_equivalent(ch)
        print(f"    {BOLD}{RED}{ch}{RESET}  x{n:<4}  U+{ord(ch):04X}  "
              f"{DIM}{char_name(ch)}{RESET} -> {display_repl(repl)}")

    if path is None:
        return 0  # clipboard mode: informational only

    print(f"\n{BOLD}Replace?{RESET}")
    print(f"  {LABEL}[i]{RESET} in place (writes backup to {path}.bak)")
    print(f"  {LABEL}[n]{RESET} new file with _ASCII suffix")
    print(f"  {LABEL}[q]{RESET} quit without changes")
    try:
        while True:
            choice = input("> ").strip().lower()
            if choice in ("i", "n", "q"):
                break
            print("please enter i, n, or q")
    except (EOFError, KeyboardInterrupt):
        print()
        return 0

    if choice == "q":
        print("no changes made")
        return 0

    new_text = "".join(
        ascii_equivalent(ch) if ord(ch) > 127 else ch for ch in text
    )

    if choice == "i":
        backup = path + ".bak"
        shutil.copy2(path, backup)
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_text)
        print(f"{GREEN}OK{RESET} replaced in place; backup at {backup}")
    else:
        base, ext = os.path.splitext(path)
        new_path = f"{base}_ASCII{ext}"
        with open(new_path, "w", encoding="utf-8") as f:
            f.write(new_text)
        print(f"{GREEN}OK{RESET} wrote {new_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
