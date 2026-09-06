#!/usr/bin/env python3
"""Prints NAME=value for each assignment in a key file, one per line.

The shell used to `source` these files directly, which executes them: a
UTF-8 BOM — three invisible bytes TextEdit adds — turned the first line
into a command that failed and aborted the whole file, so a key sitting
right there read as missing. Read here as data, decoded with utf-8-sig so
the BOM is dropped by the decoder itself.
"""

import re
import sys

QUOTES = "\"'"


def lines(path):
    with open(path, "rb") as f:
        raw = f.read().decode("utf-8-sig", "replace")
    for line in raw.splitlines():
        m = re.match(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)", line.strip())
        if not m:
            continue
        value = m.group(2).strip()
        if len(value) > 1 and value[0] == value[-1] and value[0] in QUOTES:
            value = value[1:-1]
        yield m.group(1) + "=" + value


if __name__ == "__main__":
    if len(sys.argv) > 1:
        try:
            for pair in lines(sys.argv[1]):
                print(pair)
        except OSError:
            pass
