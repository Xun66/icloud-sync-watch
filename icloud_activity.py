#!/usr/bin/env python3

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import TextIO

from activity_parser import ActivityParser, Resolver, parse_lines


def read_lines(paths: list[Path]) -> list[str]:
    lines: list[str] = []
    for path in paths:
        lines.extend(path.read_text(encoding="utf-8").splitlines())
    return lines


def build_live_log_command() -> list[str]:
    return [
        "/usr/bin/log",
        "stream",
        "--style",
        "compact",
        "--level",
        "debug",
        "--predicate",
        '(process == "fileproviderd") OR (process == "com.apple.CloudDocs.iCloudDriveFileProvider")',
    ]


def watch_live(
    volume_path: Path,
    *,
    verbose: bool = False,
    status_stream: TextIO = sys.stderr,
    output_stream: TextIO = sys.stdout,
) -> int:
    parser = ActivityParser(resolver=Resolver(volume_path=volume_path), verbose=verbose)
    print(
        "Watching live iCloud activity from the macOS unified log. Press Ctrl-C to stop.",
        file=status_stream,
        flush=True,
    )
    process = subprocess.Popen(
        build_live_log_command(),
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None
    try:
        for line in process.stdout:
            for event in parser.feed_line(line):
                print(event, file=output_stream, flush=True)
        return process.wait()
    except KeyboardInterrupt:
        process.terminate()
        process.wait()
        return 130


def main(argv: list[str] | None = None) -> int:
    arg_parser = argparse.ArgumentParser(
        description="Extract likely iCloud upload/download file activity from logs."
    )
    arg_parser.add_argument("logs", nargs="*", type=Path, help="Paths to iCloud log files")
    arg_parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Also print in-progress activity and trigger details when available",
    )
    arg_parser.add_argument(
        "--stdin",
        action="store_true",
        help="Read log lines from standard input instead of live unified logging",
    )
    arg_parser.add_argument(
        "--volume-path",
        type=Path,
        default=Path.cwd(),
        help="A path on the same volume as the logged files (default: current directory)",
    )
    args = arg_parser.parse_args(argv)

    if args.logs:
        lines = read_lines(args.logs)
    elif args.stdin or not sys.stdin.isatty():
        lines = sys.stdin.read().splitlines()
    else:
        return watch_live(args.volume_path, verbose=args.verbose)

    for event in parse_lines(lines, volume_path=args.volume_path, verbose=args.verbose):
        print(event)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
