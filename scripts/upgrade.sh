#!/bin/bash
# ============================================================
# upgrade.sh - 一键升级 oh-my-openagent + @opencode-ai/plugin 到 npm 最新版
#
# 与 `make update` 的区别：
#   - update: 按 package.json 精确版本重装
#   - upgrade: 查 npm 最新版 → 改 package.json → 重装 → 同步 skills.lock + 文档版本号
#
# 设计原则：
#   - ~/.omo/omo.jsonc 用 /dev/ 分支 schema（永远最新），无需同步版本号
#   - 不自动跑 check：重装后直接 make check 验证
#   - install.sh 自动检测镜像延迟，滞后时全程用官方源（无需手动切源）
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

# Pre-flight: 工作区必须干净，否则升级失败后无法 git 回滚
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "❌ 工作区有未提交改动，请先 commit 或 stash" >&2
  git status --short >&2
  exit 1
fi

# ---------- 1. 查询 npm 最新版（并行查官方源，避免 npmmirror 同步延迟）----------
echo "=== 1/4 查询 npm 最新版 ==="
OMO_CURRENT=$(node -p "require('./package.json').dependencies['oh-my-openagent']")
PLG_CURRENT=$(node -p "require('./package.json').dependencies['@opencode-ai/plugin']")

# 并行查官方源（两个包同时查，总耗时 = max 而非 sum）
_omo=$(mktemp); _plg=$(mktemp)
npm view oh-my-openagent version --registry=https://registry.npmjs.org > "$_omo" 2>/dev/null &
npm view @opencode-ai/plugin version --registry=https://registry.npmjs.org > "$_plg" 2>/dev/null &
wait || true
OMO_LATEST=$(cat "$_omo"); PLG_LATEST=$(cat "$_plg")
rm -f "$_omo" "$_plg"

if [ -z "$OMO_LATEST" ] || [ -z "$PLG_LATEST" ]; then
  echo "❌ 查询 npm 最新版失败（网络问题？）" >&2
  exit 1
fi

echo "  oh-my-openagent:   $OMO_CURRENT → $OMO_LATEST"
echo "  @opencode-ai/plugin: $PLG_CURRENT → $PLG_LATEST"

if [ "$OMO_CURRENT" = "$OMO_LATEST" ] && [ "$PLG_CURRENT" = "$PLG_LATEST" ]; then
  echo ""
  echo "✓ 已是最新版本，无需升级"
  exit 0
fi

# 备份关键状态（在 step 2 修改 package.json 之前），失败可回滚
# 不备份 node_modules（515M/18k 文件，cp 耗时 ~15s）：失败后恢复 package.json + lock，跑 make update 重建
BACKUP_DIR=".upgrade-backup-$(date +%s)"
mkdir -p "$BACKUP_DIR"
cp package.json package-lock.json "$BACKUP_DIR/" 2>/dev/null || true

_restore_upgrade() {
  if [ -d "$BACKUP_DIR" ]; then
    echo "↩ 升级失败，恢复 package.json + lock..." >&2
    cp "$BACKUP_DIR"/package.json "$BACKUP_DIR"/package-lock.json . 2>/dev/null || true
    rm -rf "$BACKUP_DIR"
    echo "  → node_modules 需手动重建：make update" >&2
  fi
}
trap _restore_upgrade ERR INT TERM

# ---------- 2. 更新 package.json ----------
echo ""
echo "=== 2/4 更新 package.json ==="
node -e '
const fs = require("fs");
const [omoLatest, plgLatest] = process.argv.slice(2);
const pkg = JSON.parse(fs.readFileSync("./package.json", "utf8"));
const changed = [];
if (pkg.dependencies["oh-my-openagent"] !== omoLatest) {
  pkg.dependencies["oh-my-openagent"] = omoLatest;
  changed.push("oh-my-openagent");
}
if (pkg.dependencies["@opencode-ai/plugin"] !== plgLatest) {
  pkg.dependencies["@opencode-ai/plugin"] = plgLatest;
  changed.push("@opencode-ai/plugin");
}
fs.writeFileSync("./package.json", JSON.stringify(pkg, null, 2) + "\n");
console.log("  ✓ 已更新: " + changed.join(", "));
' "$OMO_LATEST" "$PLG_LATEST"


# ---------- 3. 清 node_modules + npm install（触发 postinstall: claude-mermaid + codegraph）----------
echo ""
echo "=== 3/4 清理 node_modules 并重装 ==="
node -e "require('fs').rmSync('node_modules',{recursive:true,force:true}); console.log('  ✓ node_modules 已清除')"
rm -f package-lock.json
bash scripts/install.sh
bash scripts/sync-omo-skills.sh

# ---------- 4. 同步 skills.lock + 文档版本号 ----------
echo ""
echo "=== 4/4 同步 skills.lock + 文档版本号 ==="

# 4a. skills.lock：OMO 升级或 feishu 重装会让 skill 内容变化，必须重算哈希
if command -v make >/dev/null 2>&1; then
  make -s skills-lock
else
  echo "  ⚠ make 不可用，请手动运行：make skills-lock"
fi

# 4b. 文档里的硬编码版本号（README / reference / instructions）
# 用 argv 传参（避免 shell 插值注入），node 做精确字面替换
node -e '
const fs = require("fs");
const [omoCurrent, omoLatest, plgCurrent, plgLatest] = process.argv.slice(2);
const files = ["README.md", "docs/reference.md", ".opencode/instructions.md"];
const replacements = [
  [omoCurrent, omoLatest],
  [plgCurrent, plgLatest],
].filter(([from]) => from);
let touched = 0;
for (const f of files) {
  if (!fs.existsSync(f)) continue;
  let s = fs.readFileSync(f, "utf8");
  const orig = s;
  for (const [from, to] of replacements) {
    if (from === to) continue;
    s = s.split(from).join(to);
  }
  if (s !== orig) {
    fs.writeFileSync(f, s);
    console.log("  ✓ 文档版本号已同步: " + f);
    touched++;
  }
}
if (touched === 0) console.log("  ✓ 文档无旧版本号需更新（可能已同步或未硬编码）");
' "$OMO_CURRENT" "$OMO_LATEST" "$PLG_CURRENT" "$PLG_LATEST"

# 清理备份，解除 trap
trap - ERR
rm -rf "$BACKUP_DIR"

# ---------- 完成 ----------
echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ 升级完成"
echo "═══════════════════════════════════════════"
echo ""
echo "下一步（按顺序执行）："
echo ""
echo "  1. 体检："
echo "     make check"
echo ""
echo "  2. 提交改动（skills.lock + 文档版本号已自动同步；OMO 配置在 ~/.omo/omo.jsonc，不在 git 内，无需提交）："
echo "     git add package.json package-lock.json skills.lock README.md docs/reference.md .opencode/instructions.md"
echo "     git commit -m \"upgrade: oh-my-openagent → $OMO_LATEST, plugin → $PLG_LATEST\""
