# 开发说明

## 构建与本地安装

需要 macOS 14+ 和 Xcode 命令行工具。在仓库根目录执行：

```bash
./build.sh
```

产物为 `build/RemoteMate.app`。替换本机安装时，先退出旧应用，再执行：

```bash
osascript -e 'quit app id "com.remotemate.app"'
rm -rf /Applications/RemoteMate.app
ditto --norsrc --noextattr "build/RemoteMate.app" /Applications/RemoteMate.app
open "/Applications/RemoteMate.app"
```

使用 `ditto --norsrc --noextattr` 安装。项目位于 iCloud 等同步目录时，`cp -R` 会带上扩展属性，可能导致安装后的 App 签名失效。

## 打包与发布

```bash
./build.sh
scripts/build-dmg.sh "$(python3 -c 'import json; print(json.load(open("Updates/config.json"))["version"])')"
```

DMG 和 `SHA256SUMS.txt` 输出到 `build/releases/<版本号>/`。打包时会短暂挂载并打开 DMG 窗口，以写入 Finder 安装引导布局。

GitHub Release 与 Sparkle 应用内更新的发布步骤见 [更新与发布说明](../Updates/README.md)。

## 实现要点

- 空闲防休眠通过 `IOPMAssertion` 实现，无需管理员权限。
- 合盖不休眠使用 `pmset -a disablesleep 0/1`，按当前供电和防休眠开关决定是否生效。免密码授权写入 `/etc/sudoers.d/remote-mate`，仅允许这两条命令，可在面板撤销。
- 网络检测包括网关、外网和 UU 服务器；UU 相关项目仅在安装客户端后显示。仅后台服务运行时，主程序仍标为未启动。
- 虚拟屏幕基于 CoreGraphics 私有 API `CGVirtualDisplay`。
- 菜单栏图标空心表示防休眠与虚拟屏幕均未生效，实心表示至少一项生效；它不表示远程会话已连接。

## 图标

应用图标源图为 `Branding/RemoteMate/app-icon-light.png`。修改后执行：

```bash
./scripts/build-icon.sh
./build.sh
```

生成的 `Resources/AppIcon.icns` 包含 macOS 所需尺寸，构建时自动写入 App Bundle。

## README 截图

`docs/images/` 来自 v1.2.0 的真实菜单栏面板，保留完整主面板，并按功能区域裁切展示。更新截图时使用同一版本界面，避免把实时状态当作连接成功的证明；不为取图改变用户的供电、合盖或显示器设置。
