#!/usr/bin/env python3

from __future__ import annotations

import shutil
import sys
from datetime import datetime
from pathlib import Path


BUNDLE_IDENTIFIER = "io.github.xun66.iCloudSyncWatch"


def state_file_path() -> Path:
    app_support = Path.home() / "Library" / "Application Support"
    return app_support / BUNDLE_IDENTIFIER / "state.jsonl"


def main() -> int:
    target = state_file_path()
    if not target.exists():
        print(f"state file not found: {target}")
        return 0

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = target.with_name(f"{target.name}.bak.{timestamp}")
    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(target, backup)
    print(f"moved state file to backup: {backup}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
