#!/usr/bin/env python3
"""Structural checks for the AutoHotkey files this fork owns.

Four faults have each cost a day here, and not one of them was caught by a brace
count or a grep. They are checked for by name:

    duplicate   the same function defined twice, the second silently winning
    overwrite   a global assignment destroying a function of the same name,
                because AutoHotkey identifiers are case insensitive
    shadow      a local or a parameter hiding a function within one body
    ternary     a statement opening with an expression and a question mark,
                which AutoHotkey reads as a function call

Plus the things that keep a file loadable at all: balanced braces, CRLF endings
and a UTF-8 BOM, both of which a file written from macOS lacks.

Only the files this fork wrote are checked. Upstream libraries are not ours to
police, and a checker that reports eleven faults it will never fix on its first
run is a checker nobody reads again.

This is a sieve, not a compiler. It says a file is not obviously broken. Only
/Validate in the Windows VM says it will load.

    python3 tools/nm-check.py
"""

import glob
import re
import sys

# braces inside upstream string literals, which are not ours to balance
BASELINE = {"submacros/natro_macro.ahk": 4}

OWNED = (["submacros/natro_macro.ahk",
          "lib/Socket.ahk", "lib/FleetProtocol.ahk", "lib/FleetRoster.ahk",
          "submacros/Fleet.ahk", "submacros/FleetSelfTest.ahk",
          "submacros/SocketSelfTest.ahk"]
         + sorted(glob.glob("submacros/extensions/*.ahk")))

FUNC = re.compile(r"^(\w+)\([^)]*\)\s*\{", re.M)
ASSIGN = re.compile(r"^(\w+)\s*:=", re.M)
LOCAL = re.compile(r"^\s*local\s+([^\r\n]+)", re.M)
PARAMS = re.compile(r"^\w+\(([^)]*)\)\s*\{", re.M)
# a plain name or a property chain only: a ternary inside brackets or an
# argument list is an expression, not the start of a statement
TERNARY = re.compile(r"^\s*[A-Za-z_]\w*(?:\.\w+)*\s+\?\s")


def declared(code):
    """Every name introduced as a local or as a parameter."""
    names = set()
    for match in LOCAL.finditer(code):
        names |= {p.strip().split(":=")[0].strip() for p in match.group(1).split(",")}
    for match in PARAMS.finditer(code):
        names |= {p.strip().split(":=")[0].strip().lstrip("&*")
                  for p in match.group(1).split(",")}
    return {n for n in names if n}


def check(path):
    """Return a list of complaints about one file, empty when it looks sound."""
    raw = open(path, "rb").read()
    text = open(path, encoding="utf-8-sig", newline="").read()
    lines = text.split("\r\n")
    code = "\n".join(l for l in lines if not l.lstrip().startswith(";"))

    funcs = FUNC.findall(code)
    lowered = {f.lower() for f in funcs}
    out = []

    if dupes := sorted({f for f in funcs if funcs.count(f) > 1}):
        out.append(f"defined twice: {', '.join(dupes)}")
    if over := sorted({a for a in set(ASSIGN.findall(code)) if a.lower() in lowered}):
        out.append(f"global assignment overwrites a function: {', '.join(over)}")
    if shadow := sorted({n for n in declared(code) if n.lower() in lowered}):
        out.append(f"local or parameter shadows a function: {', '.join(shadow)}")
    if tern := [str(i) for i, l in enumerate(lines, 1)
                if not l.lstrip().startswith(";") and TERNARY.match(l)]:
        out.append(f"ternary opening a statement, line {', '.join(tern)}")

    delta = text.count("{") - text.count("}")
    if delta != BASELINE.get(path, 0):
        out.append(f"brace delta {delta:+d}, expected {BASELINE.get(path, 0):+d}")
    if text.count("\n") != text.count("\r\n"):
        out.append("line endings are not all CRLF")
    if not raw.startswith(b"\xef\xbb\xbf"):
        out.append("no UTF-8 BOM")
    return out


def cross_reference():
    """Our own functions should all be called, and all calls should resolve."""
    blob = "".join(open(p, encoding="utf-8-sig", newline="").read() for p in OWNED)
    # case insensitively, because AutoHotkey is: ba_getLastField and
    # ba_getlastfield are one name, and comparing them exactly invents a fault
    defined = {f.lower() for f in FUNC.findall(blob)}
    ours = re.compile(r"\b(ext_\w+|fleet_\w+|sock_\w+|roster_\w+|ba_\w+)")
    out = []
    missing = sorted({n for n in ours.findall(blob)
                      if n.lower() not in defined
                      and re.search(r"\b" + n + r"\s*\(", blob)
                      and not re.search(r"^" + n + r"\s*:=", blob, re.M)})
    if missing:
        out.append(f"called but never defined: {', '.join(missing)}")
    unused = sorted(f for f in set(FUNC.findall(blob))
                    if ours.match(f)
                    and len(re.findall(r"\b" + f + r"\b", blob, re.I)) < 2)
    if unused:
        out.append(f"defined but never used: {', '.join(unused)}")
    return out


def main():
    problems = 0
    for path in OWNED:
        for complaint in check(path):
            print(f"{path}: {complaint}")
            problems += 1
    for complaint in cross_reference():
        print(complaint)
        problems += 1
    print(f"\n{len(OWNED)} files checked, {problems} problem"
          f"{'' if problems == 1 else 's'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
