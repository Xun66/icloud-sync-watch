# iCloud Sync Watch

一个原生 macOS 菜单栏应用，用来实时观察 iCloud Drive 的同步活动。

应用通过 `/usr/bin/log stream` 读取 macOS unified log，用原生 Swift 代码解析 iCloud 文件活动，把当前时间线持久化为 JSONL，再在菜单栏弹层里展示最近的条目。

仓库里还保留了 `scripts/` 目录中的独立 Python CLI 原型。它和当前 GUI app 是分开的；除非你有调试 parser 或研究早期原型的特殊需求，否则一般不需要使用。

## 当前支持

- 上传
- 下载
- 文件删除
- 目录创建
- 目录删除
- 文件重命名与移动
- 目录重命名与移动

每条记录会显示：

- 动作图标
- 文件或目录名
- 进行中时显示 spinner
- 完成后显示绿色对勾

默认只显示最近 10 条，可以展开查看更多。

## 当前范围

- 仅支持原生 macOS app
- 仅支持 live 监控
- 不支持历史日志回放
- 状态文件保存在 `~/Library/Application Support/labs.mindive.iCloudSyncWatch/state.jsonl`

如果关闭“隐藏后保持监控”，弹层隐藏时会暂停监控；再次展开时，时间线会插入一条分割线，显示暂停了多久。

## 运行要求

- macOS 13+
- Xcode 或 Xcode Command Line Tools

## 开发

```bash
swift build
swift test
```

## 一键打包 Ad-Hoc Universal App

```bash
make package VERSION=0.1.0
```

产物：

- `dist/iCloud Sync Watch.app`
- `dist/iCloud Sync Watch-0.1.0.zip`

`.app` 会使用 `codesign --sign -` 做 ad-hoc 签名。

## CI 与 Release

- `.github/workflows/ci.yml` 会在 PR 和 push 到 `main` 时执行 `swift test`
- `.github/workflows/release.yml` 会在推送 `v0.1.0` 这类 tag 时构建 universal ad-hoc 签名 app，并把 zip 上传到 GitHub Release

当前这套 ad-hoc 签名发布流程不需要额外 GitHub secrets，使用默认的 `GITHUB_TOKEN` 就够了。

如果后面你要接 notarization，再额外准备这些 GitHub secrets：

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
