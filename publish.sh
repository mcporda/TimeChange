#!/bin/bash
# 一条命令发布新版本：改版本号 → 打包 DMG → 提交 → 打标签 → 推送 → 创建 GitHub Release
# 用法：./publish.sh 1.1.0 "本次更新的要点（每行一条，可选）"
# 发布后，已安装的用户会在一天内收到 App 内更新提示。
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?用法：./publish.sh <版本号> [更新说明]}"
CHANGES="${2:-}"
TAG="v$VERSION"

git rev-parse "$TAG" >/dev/null 2>&1 && { echo "标签 $TAG 已存在"; exit 1; }

# 1. 版本号
sed -i '' "s#<key>CFBundleShortVersionString</key><string>[^<]*</string>#<key>CFBundleShortVersionString</key><string>$VERSION</string>#" build.sh

# 2. 打包
./release.sh "$VERSION" >/dev/null
DMG="build/TimeChange-$VERSION.dmg"

# 3. 更新说明：没给就用上个标签以来的提交标题
PREV=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [ -z "$CHANGES" ]; then
  CHANGES=$(git log ${PREV:+$PREV..}HEAD --pretty='- %s' --no-merges | grep -v '^- Release v' || true)
fi
NOTES=$(mktemp)
cat > "$NOTES" <<EOF
## 更新内容
$CHANGES

## 下载
下载下方的 **TimeChange-$VERSION.dmg**，打开后把 TimeChange 拖进「应用程序」。支持 Apple 芯片和 Intel，需要 macOS 14 及以上。
已安装旧版本的用户：App 会自动提示更新，点「更新到 v$VERSION」即可。

> [!WARNING]
> **首次打开提示「无法验证开发者」/「已损坏」怎么办？**
> 本项目暂未经过 Apple 公证，这是正常现象，任选一种方法即可：
> 1. **终端执行一行命令（最简单）**：
>    \`\`\`bash
>    xattr -dr com.apple.quarantine /Applications/TimeChange.app
>    \`\`\`
> 2. **系统设置**：先双击打开一次 → 弹窗点「完成」→ 打开「系统设置 → 隐私与安全性」→ 拉到底部，在 TimeChange 旁点「**仍要打开**」。
>
> 只需操作一次，之后的自动更新不会再提示。
EOF

# 4. 提交、打标签、推送
git add -A
git commit -q -m "Release $TAG" || true
git tag "$TAG"
git push -q
git push -q origin "$TAG"

# 5. GitHub Release（自动更新读取的就是这里的「最新版本」）
gh release create "$TAG" "$DMG" --title "TimeChange $VERSION" --notes-file "$NOTES"
rm -f "$NOTES"
