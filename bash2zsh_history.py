#!/usr/bin/env python3
"""
bash_history -> zsh extended history converter

Converts a bash history file into zsh's extended history format
(": <epoch>:<duration>;<command>") and appends it to the zsh history file.

Format handling (verified against bash 5.2 and zsh 5.9 behaviour):
- If bash wrote timestamps (HISTTIMEFORMAT set -> "#<epoch>" marker lines),
  every line between two markers belongs to one entry, exactly as bash
  itself reads the file.  This preserves heredocs, loops and multi-line
  strings losslessly, and the real timestamps are kept.
- Without timestamps, each line is one entry, except that multi-line
  quoted strings (which bash writes across several lines even with default
  settings) and backslash-continuations are merged using a bash-aware
  quote scanner (single/double/$'...' quotes, comments, escapes).
- Entries are written the way zsh itself writes them: embedded newlines
  become backslash-newline, bytes 0x00 and 0x83-0xa2 are metafied
  (0x83 + byte^0x20), and a command ending in a backslash gets a
  disambiguating trailing space.  The file is treated as raw bytes
  throughout, so non-UTF-8 histories survive unchanged.
- Entries without a real timestamp get synthetic ones that count up to
  "now", so ordering is stable and nothing is dated in the future.
- Safe: the bash history is only READ; the zsh history is only APPENDED
  to (created 0600 if missing, exclusively locked while writing).

Note: if a zsh session is running while you import, run `fc -R` inside it
(or restart zsh) afterwards - a session without INC_APPEND_HISTORY or
SHARE_HISTORY rewrites the history file on exit and would drop the import.

Usage:
    python3 bash2zsh_history.py --dry-run          # inspect output first
    python3 bash2zsh_history.py                    # append to ~/.zsh_history
    python3 bash2zsh_history.py --bash-history /path --zsh-history /path
"""

import os
import sys
import time
import argparse
from pathlib import Path

# A "#<digits>" line only counts as a bash timestamp marker if it is a
# plausible epoch, so ordinary numeric comments are not eaten.
TS_MIN = 100_000_000      # 1973
TS_MAX = 100_000_000_000  # year ~5138


def timestamp_of(line):
    """Return the epoch int if this line is a bash timestamp marker, else None."""
    if line.startswith(b"#") and line[1:].isdigit():
        ts = int(line[1:])
        if TS_MIN <= ts < TS_MAX:
            return ts
    return None


def scan_line(line, quote):
    """
    Scan one line of bash with `quote` as the quoting state carried in from
    previous lines (None, "'", '"' or "$'").  Returns (quote_after_line,
    ends_with_line_continuation).  Comments and backslash escapes are
    handled; this is what decides whether a command continues on the next line.
    """
    dangling = False
    i, n = 0, len(line)
    while i < n:
        c = line[i:i + 1]
        if quote == b"'":
            if c == b"'":
                quote = None
            i += 1
        elif quote in (b'"', b"$'"):
            if c == b"\\":
                i += 2  # escapes next char (or the newline, if last)
            elif c == (b'"' if quote == b'"' else b"'"):
                quote = None
                i += 1
            else:
                i += 1
        else:
            if c == b"\\":
                if i == n - 1:
                    dangling = True
                i += 2
            elif c == b"'":
                quote = b"'"
                i += 1
            elif c == b'"':
                quote = b'"'
                i += 1
            elif c == b"$" and line[i + 1:i + 2] in (b"'", b'"'):
                quote = b"$'" if line[i + 1:i + 2] == b"'" else b'"'
                i += 2
            elif c == b"#" and (i == 0 or line[i - 1:i] in
                                (b" ", b"\t", b";", b"|", b"&", b"(", b"<", b">")):
                break  # comment runs to end of line
            else:
                i += 1
    return quote, dangling


def parse_bash_history(data):
    """
    Parses raw bash history bytes into a list of (timestamp_or_None, command)
    tuples, where command is bytes (may contain newlines).
    """
    lines = data.split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()  # file's trailing newline, not an empty entry

    entries = []
    pending_ts = None   # timestamp waiting for its command
    buffer = []
    quote = None        # quoting state across buffered lines
    in_ts_entry = False  # True while collecting lines that follow a marker

    def flush():
        nonlocal buffer, pending_ts, quote, in_ts_entry
        if buffer:
            cmd = b"\n".join(buffer).rstrip(b"\n")
            if cmd.strip():
                entries.append((pending_ts, cmd))
        buffer = []
        pending_ts = None
        quote = None
        in_ts_entry = False

    for raw in lines:
        line = raw.rstrip(b"\r")  # tolerate CRLF files

        ts = timestamp_of(line)
        if ts is not None:
            # A marker always starts a new entry, exactly like bash's reader.
            flush()
            pending_ts = ts
            in_ts_entry = True
            continue

        buffer.append(line)

        if in_ts_entry:
            # Timestamped entries run until the next marker; nothing to decide.
            continue

        quote, dangling = scan_line(line, quote)
        if quote is None and not dangling:
            flush()

    flush()
    return entries


def metafy(data):
    """Escape bytes the way zsh stores them in its history file."""
    out = bytearray()
    for b in data:
        if b == 0x00 or 0x83 <= b <= 0xA2:
            out.append(0x83)
            out.append(b ^ 0x20)
        else:
            out.append(b)
    return bytes(out)


def to_zsh_extended(entries, now=None):
    """
    Converts entries to zsh extended-history lines (bytes, no trailing
    newline).  Entries without a real timestamp get increasing synthetic
    ones ending at "now", so order is kept and nothing is post-dated.
    """
    now = now or int(time.time())
    synth = max(1, now - sum(1 for ts, _ in entries if ts is None))

    out = []
    for ts, cmd in entries:
        if ts is None:
            ts = synth
            synth += 1
        else:
            synth = max(synth, ts + 1)

        text = b"\\\n".join(metafy(cmd).split(b"\n"))
        if text.endswith(b"\\"):
            # zsh's own writer does this: a trailing backslash would make
            # the reader join the next entry onto this one.
            text += b" "
        out.append(b": %d:0;%s" % (ts, text))
    return out


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bash-history", default=str(Path.home() / ".bash_history"))
    ap.add_argument("--zsh-history", default=str(Path.home() / ".zsh_history"))
    ap.add_argument("--dry-run", action="store_true",
                    help="print result instead of writing")
    args = ap.parse_args()

    src = Path(args.bash_history)
    try:
        data = src.read_bytes()
    except OSError as e:
        sys.exit(f"error: cannot read {src}: {e.strerror or e}")

    entries = parse_bash_history(data)
    payload = b"".join(line + b"\n" for line in to_zsh_extended(entries))

    if args.dry_run:
        sys.stdout.buffer.write(payload)
        sys.stdout.buffer.flush()
        print(f"\n# {len(entries)} entries would be appended to {args.zsh_history}",
              file=sys.stderr)
        return

    try:
        fd = os.open(args.zsh_history,
                     os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    except OSError as e:
        sys.exit(f"error: cannot open {args.zsh_history}: {e.strerror or e}")
    try:
        try:
            import fcntl
            fcntl.flock(fd, fcntl.LOCK_EX)
        except ImportError:
            pass
        # If an existing file doesn't end in a newline, our first entry
        # would glue itself onto the last existing one.
        size = os.fstat(fd).st_size
        if size > 0:
            with open(args.zsh_history, "rb") as chk:
                chk.seek(size - 1)
                if chk.read(1) != b"\n":
                    payload = b"\n" + payload
        view = memoryview(payload)
        while view:
            view = view[os.write(fd, view):]
    finally:
        os.close(fd)

    print(f"Appended {len(entries)} entries to {args.zsh_history}")
    print(f"Source file {src} was not modified.")
    print("If a zsh session is currently open, run `fc -R` in it (or restart zsh)"
          " so the session picks up the imported entries instead of overwriting them.")


if __name__ == "__main__":
    main()
