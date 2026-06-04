# iCloud Sync Watch

A native macOS menu bar app for watching live iCloud Drive sync activity.

The app listens to the macOS unified log through `/usr/bin/log stream`, parses iCloud file activity in native Swift code, persists the current timeline to JSONL, and shows the latest entries from a menu bar popover.

An older standalone Python CLI prototype is also preserved under `scripts/`. It is independent from the GUI app and usually does not need to be used unless you specifically want the original terminal prototype for debugging or parser research.

## What It Shows

- Uploads
- Downloads
- File deletions
- Directory creations
- Directory deletions
- File renames and moves
- Directory renames and moves

Each row shows:

- action icon
- file or folder name
- spinner while the activity is still running
- green check when the activity is complete

The popover shows the latest 10 entries by default and can expand to show more.

## Current Scope

- Native macOS app only
- Live monitoring only
- No historical log playback
- State is stored in `~/Library/Application Support/labs.mindive.iCloudSyncWatch/state.jsonl`

If "Keep monitoring while hidden" is turned off, closing the popover pauses monitoring. When the popover is opened again, the timeline inserts a divider that shows how long monitoring was paused.

## Requirements

- macOS 13 or later
- Xcode command line tools or Xcode

## Development

```bash
swift build
swift test
```

## Package An Ad-Hoc Signed Universal App

```bash
make package VERSION=0.1.0
```

This produces:

- `dist/iCloud Sync Watch.app`
- `dist/iCloud Sync Watch-0.1.0.zip`

The `.app` bundle is ad-hoc signed with `codesign --sign -`.

## CI And Release

- `.github/workflows/ci.yml` runs `swift test` on pull requests and pushes to `main`
- `.github/workflows/release.yml` builds a universal ad-hoc signed app on tag pushes like `v0.1.0` and uploads the zip to the GitHub release

No extra GitHub secrets are required for the current ad-hoc signing flow. `GITHUB_TOKEN` is enough for the release upload step.

If you later want notarization, you will need Apple credentials such as:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
