#!/bin/bash
# ============================================================
# upgrade.sh - 一键升级 oh-my-openagent + @opencode-ai/plugin 到 npm 最新版
#
# 与 `make update` 的区别：
#   - update: 按 package.json 精确版本重装
#   - upgrade: 查 npm 最新版 → 改 package.json → 重装 → 同步 $schema URL
#
# 设计原则：
#   - $schema URL 同步到新版本（oh-my-openagent.json 顶部）
#   - 不自动跑 check：重装后直接 make check 验证
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

# Pre-flight: 工作区必须干净，否则升级失败后无法 git 回滚
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "❌ 工作区有未提交改动，请先 commit 或 stash" >&2
  git status --short >&2
  exit 1
fi

# ---------- 1. 查询 npm 最新版（用官方源避免 npmmirror 同步延迟）----------
echo "=== 1/4 查询 npm 最新版 ==="
OMO_CURRENT=$(node -p "require('./package.json').dependencies['oh-my-openagent']")
PLG_CURRENT=$(node -p "require('./package.json').dependencies['@opencode-ai/plugin']")
OMO_LATEST=$(npm view oh-my-openagent version --registry=https://registry.npmjs.org)
PLG_LATEST=$(npm view @opencode-ai/plugin version --registry=https://registry.npmjs.org)

echo "  oh-my-openagent:   $OMO_CURRENT → $OMO_LATEST"
echo "  @opencode-ai/plugin: $PLG_CURRENT → $PLG_LATEST"

if [ "$OMO_CURRENT" = "$OMO_LATEST" ] && [ "$PLG_CURRENT" = "$PLG_LATEST" ]; then
  echo ""
  echo "✓ 已是最新版本，无需升级"
  exit 0
fi

# 备份关键状态（在 step 2 修改 package.json 之前），失败可回滚
BACKUP_DIR=".upgrade-backup-$(date +%s)"
mkdir -p "$BACKUP_DIR"
cp -r package.json package-lock.json "$BACKUP_DIR/" 2>/dev/null || true
[ -d node_modules ] && cp -r node_modules "$BACKUP_DIR/" 2>/dev/null || true

_restore_upgrade() {
  if [ -d "$BACKUP_DIR" ]; then
    echo "↩ 升级失败，恢复备份..." >&2
    cp -r "$BACKUP_DIR"/* . 2>/dev/null || true
    rm -rf "$BACKUP_DIR"
  fi
}
trap _restore_upgrade ERR INT TERM

# ---------- 2. 更新 package.json ----------
echo ""
echo "=== 2/4 更新 package.json ==="
node -e "
const fs = require('fs');
const p = './package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
let changed = [];
if (pkg.dependencies['oh-my-openagent'] !== '$OMO_LATEST') {
  pkg.dependencies['oh-my-openagent'] = '$OMO_LATEST';
  changed.push('oh-my-openagent');
}
if (pkg.dependencies['@opencode-ai/plugin'] !== '$PLG_LATEST') {
  pkg.dependencies['@opencode-ai/plugin'] = '$PLG_LATEST';
  changed.push('@opencode-ai/plugin');
}
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
console.log('  ✓ 已更新: ' + changed.join(', '));
"


# ---------- 3. 清 node_modules + npm install（触发 postinstall: claude-mermaid + codegraph）----------
echo ""
echo "=== 3/4 清理 node_modules 并重装 ==="
node -e "require('fs').rmSync('node_modules',{recursive:true,force:true}); console.log('  ✓ node_modules 已清除')"
rm -f package-lock.json
bash scripts/install.sh
bash scripts/sync-omo-skills.sh

# ---------- 4. 更新 oh-my-openagent.json 的 $schema URL ----------
echo ""
echo "=== 4/4 更新 oh-my-openagent.json 的 \$schema URL ==="
node -e "
const fs = require('fs');
const p = './oh-my-openagent.json';
let s = fs.readFileSync(p, 'utf8');
const re = /oh-my-openagent\/v[0-9]+\.[0-9]+\.[0-9]+\/assets/;
const replacement = 'oh-my-openagent/v$OMO_LATEST/assets';
if (re.test(s)) {
  s = s.replace(re, replacement);
  fs.writeFileSync(p, s);
  console.log('  ✓ \$schema URL 已更新到 v$OMO_LATEST');
} else {
  console.log('  ⚠ 未找到现有 \$schema URL 模式，跳过（请手动检查）');
}
"

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
echo "  2. 如果 skills.lock 哈希不匹配（lark skills 被升级时更新过）："
echo "     make skills-lock    # 重新生成"
echo ""
echo "  3. 提交改动："
echo "     git add package.json oh-my-openagent.json README.md skills.lock"
echo "     git commit -m \"upgrade: oh-my-openagent → $OMO_LATEST, plugin → $PLG_LATEST\""
