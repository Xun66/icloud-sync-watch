# Python Prototype

这个目录保存了最初的 Python CLI 原型，独立于当前的原生 macOS GUI 应用。

如果你只是使用当前的菜单栏图形版本，通常不需要这个目录里的脚本。

这里保留它的原因：

- 作为 GUI 版本的原型参考
- 方便直接在终端里验证 unified log 解析行为

## 文件

- `icloud_activity.py`
- `activity_parser.py`
- `reset_state.py`

## 运行要求

- macOS
- `python3`
- `/usr/bin/log`
- `GetFileInfo`

## 简单用法

实时监听：

```bash
python3 scripts/icloud_activity.py \
  --volume-path ~/Library/Mobile\ Documents/com~apple~CloudDocs
```

从标准输入解析：

```bash
log show --style compact --last 10m \
  --predicate 'process == "fileproviderd" OR process == "com.apple.CloudDocs.iCloudDriveFileProvider"' \
  | python3 scripts/icloud_activity.py --stdin --volume-path ~/Documents
```

这个脚本项目是独立保存的；除非你有调试或研究 parser 的特殊需求，否则无需使用。

## 重置 GUI 状态文件

如果 GUI 应用因为状态文件 schema 变化而无法启动，可以先把旧状态文件备份移走：

```bash
python3 scripts/reset_state.py
```

它会把 `~/Library/Application Support/io.github.xun66.iCloudSyncWatch/state.jsonl` 移动为带时间戳的 `.bak` 文件。
