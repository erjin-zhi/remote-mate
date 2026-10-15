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
- `remote.launchUU` 保持原有的一次性自动启动语义；新增 `remote.keepUUAlive` 独立控制保活，默认关闭，升级不自动启用。保活需远程模式、自动启动和保活选项同时开启，且已安装 UU。独立定时器每 10 秒检查主程序，不依赖面板是否展开；后台拉起不抢焦点，失败后下一轮重试，并对启动请求去重。停止保活取消尚未执行的保活请求，不退出已运行或已由系统开始启动的 UU。后台启动期间的手动前台请求会在当前请求结束后执行。
- 虚拟屏幕基于 CoreGraphics 私有 API `CGVirtualDisplay`。
- 菜单栏图标与面板顶部共用一键远程模式状态：关闭时空心，部分开启或暂停等待供电恢复时半实心，全部开启时实心。单独开启防休眠或虚拟屏幕不会点亮图标；悬停提示区分模式状态与单项功能状态，它不表示远程会话已连接。
- 所有纳入项目均关闭后自动退出远程模式。只启用 UU 自动启动而未启用保活时，退出最后一个运行中的 UU 也会退出模式；启用保活时则保持模式，等待后台重新启动 UU。

## 图标

应用图标源图为 `Branding/RemoteMate/app-icon-light.png`。修改后执行：

```bash
./scripts/build-icon.sh
./build.sh
```

生成的 `Resources/AppIcon.icns` 包含 macOS 所需尺寸，构建时自动写入 App Bundle。

## README 截图

`docs/images/` 于 2026-10-15 按当前源码更新。`preferences.png` 和 `general.png` 截自当前构建的独立设置窗口；菜单栏弹窗截图接口超时，因此 `main-panel.png` 使用同一份 `PanelView` 源码在临时窗口中展示并截图，`overview.png` 和 `virtual-display.png` 从中裁切。临时预览使用独立偏好域，关闭防休眠、合盖和自动开启，仅展开显示选项；网络与 UU 状态由实际检测取得。截图裁去窗口标题栏与捕获指示，不改绘界面内容。

更新截图时使用同一版本界面，避免把实时状态当作连接成功的证明；不为取图改变用户的供电、合盖或显示器设置。
