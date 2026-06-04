# icloud-sync-watch

See which file iCloud is uploading or downloading when Finder only shows a spinner.

## Why

On macOS, Finder can show iCloud syncing in the sidebar, but often does not tell you clearly which file is moving.

This script watches the system log and prints readable events such as:

- `uploaded`
- `downloaded`
- `deleted`
- `created-dir`
- `deleted-dir`
- `renamed`
- `moved`
- `renamed-dir`
- `moved-dir`

With `--verbose`, it also prints in-progress events like `uploading` and `downloading`.

## Requirements

- macOS
- `python3`
- `/usr/bin/log`
- `GetFileInfo`

No external dependencies.
No virtualenv.
Python 3 only.

## Usage

Watch live activity:

```bash
python3 icloud_activity.py \
  --volume-path ~/Library/Mobile\ Documents/com~apple~CloudDocs
```

Verbose mode:

```bash
python3 icloud_activity.py \
  --volume-path ~/Library/Mobile\ Documents/com~apple~CloudDocs \
  --verbose
```

Parse saved logs:

```bash
python3 icloud_activity.py /path/to/log.txt
```

Parse from stdin:

```bash
log show --style compact --last 10m \
  --predicate 'process == "fileproviderd" OR process == "com.apple.CloudDocs.iCloudDriveFileProvider"' \
  | python3 icloud_activity.py --stdin --volume-path ~/Documents
```

## Sample Output

```text
uploaded /Users/you/Documents/demo.txt (fsize: 12)
downloaded /Users/you/Library/Mobile Documents/com~apple~CloudDocs/ebooks/book.epub (fsize: 424318)
deleted /Users/you/Documents/old.txt (fsize: 128)
created-dir /Users/you/Documents/temp
renamed-dir /Users/you/Documents/temp -> /Users/you/Documents/temp-2
```

Verbose mode can also explain why a masked path could not be decoded:

```text
downloading /Users/you/Downloads/p{30}m.apk (fsize: 2388025; decode: dir-list-denied; why: materialization|itemChangedRemotely)
downloaded /Users/you/Downloads/p{30}m.apk (fsize: 2388025; decode: dir-list-denied)
```

## Notes

- `--volume-path` should be on the same volume as the files you want to resolve.
- Live mode is usually more reliable than replaying old logs.
- If a masked filename cannot be resolved, `--verbose` may show reasons like `dir-list-denied`, `ambiguous-match`, or `no-match`.
- `{30}` style masks are matched by Unicode code point count, close to Go `rune` behavior.

## Chinese README

See [README.zh-CN.md](README.zh-CN.md).
