# TimeChange

macOS 菜单栏多时区时钟。全部代码在 `Sources/main.swift`（AppKit + SwiftUI，无依赖）。

## 构建
- `./build.sh`：本机构建并安装到 `~/Applications/TimeChange.app`
- `./release.sh <版本>`：通用二进制（arm64 + x86_64）+ DMG，输出 `build/TimeChange-<版本>.dmg`
- `TimeChange --snapshot docs`：重新渲染 README 截图（panel / settings-*）；`docs/menubar.png` 是实拍，需截屏更新

## 发布规则（重要）
用户说「提交 / 发布 / 发新版本」时，不要只 commit，也不要把命令交给用户去跑——直接完成整个发布：
1. 根据改动定版本号（修复 → 补丁号 +1，新功能 → 次版本号 +1），以 `gh release view --json tagName` 的最新版为基准。
2. 运行 `./publish.sh <版本> "<中文更新要点，每行一条 - 开头>"`：它会改版本号、打包 DMG、提交、打标签、推送，并创建带 DMG 和「无法验证开发者」警告说明的 GitHub Release。
3. 界面有变化时先用 `--snapshot docs` 更新截图，一起发布。
4. 发布后已安装用户会通过 App 内更新收到新版本（Updater 读取 GitHub `releases/latest` 的 `.dmg` 资产，资产名必须以 `.dmg` 结尾）。

## 约束
- 只改显示，绝不修改系统时区 / 系统时间。
- 只允许单实例运行；测试时不要直接运行旧二进制（会多开），用 `--snapshot` / `--self-update` 这类会自行退出的参数。
