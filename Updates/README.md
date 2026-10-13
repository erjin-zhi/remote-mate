# 检查更新与发布

使用 [Sparkle](https://sparkle-project.org) 2.10.0，方案与「窗见」一致：

- 更新清单 `appcast.xml` 位于本仓库 `updates` 分支根目录，App 通过 `raw.githubusercontent.com` 读取；
- 安装包为对应版本 GitHub Release（标签 `v<版本号>`）中的 DMG；
- 每个安装包用 EdDSA 签名，App 内只含公钥。

运行期间默认每天检查一次，发现新版本后弹窗由用户选择安装（不静默下载/安装，不上传系统信息）。偏好设置中可关闭自动检查，或点「检查更新…」手动检查。v1.0.1 及更早版本不含 Sparkle，需要手动安装一次新版。

`config.json` 是版本号、构建号、公钥和更新地址的唯一来源，`build.sh` 会写入 Info.plist。未配置公钥时仍可构建，只是不带更新功能。

## 首次配置签名密钥

私钥保存在本机钥匙串（account：`com.remotemate.app.sparkle`），不要提交到仓库：

```bash
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.remotemate.app.sparkle
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.remotemate.app.sparkle -p
```

把最后一条输出的公钥写入 `config.json` 的 `publicKey`。有用户之后不要更换密钥；换电脑时用 `generate_keys -x/-f` 导出导入。

## 每次发版

1. 修改 `config.json` 的 `version` 和 `build`（构建号必须严格递增），编写 `Updates/<version>.md` 更新说明（会显示在更新弹窗中）。
2. 提交并推送到 `main`。
3. 执行：

```bash
python3 scripts/release.py --publish
```

脚本依次：运行测试 → 构建 App 与 DMG → 生成并校验 EdDSA 签名与 appcast → 创建草稿 Release 和标签 → 上传 DMG 与 `SHA256SUMS.txt` 并核对摘要 → 公开 Release → 最后才推送 appcast。中途失败不会推送更新提示；已存在且内容不同的资产不会被覆盖。

只准备可审核的产物（不访问发布接口）：`python3 scripts/release.py`，输出在 `build/releases/<版本号>/sparkle/`。上传阶段中断时，在同一干净提交上执行 `python3 scripts/release.py --publish --resume` 继续。

需要：Xcode 命令行工具、已登录的 `gh`、钥匙串中的 Sparkle 私钥。App 为 ad-hoc 签名、未经 Apple 公证；更新的完整性由 EdDSA 签名保证。
