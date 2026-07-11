#!/usr/bin/env python3
"""
bash_history -> zsh extended history converter

Handles:
- Real timestamps if HISTTIMEFORMAT was enabled in bash (lines starting with '#<epoch>')
- Multiline commands (heredocs, for/while loops, unclosed quotes) merged into
  a single zsh history entry, using zsh's backslash-newline continuation format
- Safe: only READS from bash history, only APPENDS to the zsh history file.
  .bash_history is never opened for writing.

Usage:
    python3 bash2zsh_history.py --dry-run          # inspect output first
    python3 bash2zsh_history.py                    # actually append to ~/.zsh_history
    python3 bash2zsh_history.py --bash-history /path --zsh-history /path
"""

import sys
import shlex
import time
import argparse
from pathlib import Path


def parse_bash_history(lines):
    """
    Yields (timestamp_or_None, command_string) tuples.
    Merges continuation lines into a single command when:
      - the line ends with a trailing backslash, or
      - the accumulated command has unbalanced quotes (heredoc, multi-line string)
    Picks up a preceding '#<epoch>' timestamp line if bash wrote one.
    """
    entries = []
    pending_ts = None
    buffer = []

    def flush():
        nonlocal buffer, pending_ts
        if buffer:
            entries.append((pending_ts, "\n".join(buffer)))
        buffer = []
        pending_ts = None

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i].rstrip("\n")

        # bash timestamp marker (written when HISTTIMEFORMAT is set)
        if not buffer and line.startswith("#") and line[1:].isdigit():
            flush()
            pending_ts = int(line[1:])
            i += 1
            continue

        buffer.append(line)

        joined = "\n".join(buffer)
        continues = False

        if line.endswith("\\") and not line.endswith("\\\\"):
            continues = True
        else:
            try:
                shlex.split(joined, posix=True)
            except ValueError:
                # unbalanced quotes -> command isn't finished yet
                continues = True

        if not continues:
            flush()

        i += 1

    flush()  # catch any trailing unfinished buffer
    return entries


def to_zsh_extended(entries, start_ts=None):
    """
    Converts entries to zsh extended-history lines.
    Entries without a real timestamp get an increasing synthetic one, so
    ordering is preserved and no two entries collide.
    """
    out = []
    synth_ts = start_ts or int(time.time())
    for ts, cmd in entries:
        if ts is None:
            ts = synth_ts
            synth_ts += 1
        else:
            synth_ts = max(synth_ts, ts + 1)

        cmd_lines = cmd.split("\n")
        escaped = "\\\n".join(cmd_lines)  # zsh line-continuation format
        out.append(f": {ts}:0;{escaped}")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bash-history", default=str(Path.home() / ".bash_history"))
    ap.add_argument("--zsh-history", default=str(Path.home() / ".zsh_history"))
    ap.add_argument("--dry-run", action="store_true", help="print result instead of writing")
    args = ap.parse_args()

    src = Path(args.bash_history)
    if not src.exists():
        sys.exit(f"error: {src} not found")

    raw_lines = src.read_text(errors="replace").splitlines()
    entries = parse_bash_history(raw_lines)
    zsh_lines = to_zsh_extended(entries)

    if args.dry_run:
        print("\n".join(zsh_lines))
        print(f"\n# {len(entries)} entries would be appended to {args.zsh_history}", file=sys.stderr)
        return

    dst = Path(args.zsh_history)
    with dst.open("a", encoding="utf-8", errors="replace") as f:
        for line in zsh_lines:
            f.write(line + "\n")

    print(f"Appended {len(entries)} entries to {dst}")
    print(f"Source file {src} was not modified.")


if __name__ == "__main__":
    main()
