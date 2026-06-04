# icloud-sync-watch

当 Finder 左侧的 iCloud 一直转圈时，这个脚本可以直接告诉你：到底是哪个文件在上传或下载。

## 解决的问题

macOS 明明知道 iCloud 正在同步，但 Finder 往往只给你一个转圈图标，最多再给个大小和进度条，还是不知道具体是哪一个文件。

这个脚本会读取系统日志，把它整理成更容易读的事件，比如：

- `uploaded`
- `downloaded`
- `deleted`
- `created-dir`
- `deleted-dir`
- `renamed`
- `moved`
- `renamed-dir`
- `moved-dir`

加上 `--verbose` 后，还会显示 `uploading`、`downloading` 这类进行中的状态。

## 运行要求

- macOS
- `python3`
- `/usr/bin/log`
- `GetFileInfo`

没有任何外部依赖。
不需要虚拟环境。
只支持 Python 3。

## 用法

直接看整个 iCloud Drive 的实时活动：

```bash
python3 icloud_activity.py \
  --volume-path ~/Library/Mobile\ Documents/com~apple~CloudDocs
```

看更详细的输出：

```bash
python3 icloud_activity.py \
  --volume-path ~/Library/Mobile\ Documents/com~apple~CloudDocs \
  --verbose
```

解析保存好的日志：

```bash
python3 icloud_activity.py /path/to/log.txt
```

从标准输入解析：

```bash
log show --style compact --last 10m \
  --predicate 'process == "fileproviderd" OR process == "com.apple.CloudDocs.iCloudDriveFileProvider"' \
  | python3 icloud_activity.py --stdin --volume-path ~/Documents
```

## 输出示例

```text
uploaded /Users/you/Documents/demo.txt (fsize: 12)
downloaded /Users/you/Library/Mobile Documents/com~apple~CloudDocs/ebooks/book.epub (fsize: 424318)
deleted /Users/you/Documents/old.txt (fsize: 128)
created-dir /Users/you/Documents/temp
renamed-dir /Users/you/Documents/temp -> /Users/you/Documents/temp-2
```

如果路径没法完全还原，`--verbose` 会尽量说明原因：

```text
downloading /Users/you/Downloads/p{30}m.apk (fsize: 2388025; decode: dir-list-denied; why: materialization|itemChangedRemotely)
downloaded /Users/you/Downloads/p{30}m.apk (fsize: 2388025; decode: dir-list-denied)
```

## 说明

- `--volume-path` 最好指向和目标文件在同一个 volume 的路径。
- live 模式通常比回放旧日志更可靠。
- 如果脱敏路径没法还原，`--verbose` 里可能会看到 `dir-list-denied`、`ambiguous-match`、`no-match` 等原因。
- `{30}` 这种写法按 Unicode code point 计数，接近 Go 里的 `rune`。

## English README

英文说明见 [README.md](README.md)。
