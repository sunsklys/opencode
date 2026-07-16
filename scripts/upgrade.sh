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

# ---------- 5. 同步 skills.lock + 文档版本号 ----------
echo ""
echo "=== 5/5 同步 skills.lock + 文档版本号 ==="

# 5a. skills.lock：OMO 升级或 feishu 重装会让 skill 内容变化，必须重算哈希
if command -v make >/dev/null 2>&1; then
  make -s skills-lock
else
  echo "  ⚠ make 不可用，请手动运行：make skills-lock"
fi

# 5b. 文档里的硬编码版本号（README / reference / instructions）
# 把旧版本号字符串替换成新版本号，用 node 做精确字面替换（避免 sed 在 macOS/BSD 的转义差异）
node -e "
const fs = require('fs');
const files = ['README.md', 'docs/reference.md', '.opencode/instructions.md'];
const replacements = [
  ['$OMO_CURRENT', '$OMO_LATEST'],
  ['$PLG_CURRENT', '$PLG_LATEST'],
];
let touched = 0;
for (const f of files) {
  if (!fs.existsSync(f)) continue;
  let s = fs.readFileSync(f, 'utf8');
  let orig = s;
  for (const [from, to] of replacements) {
    if (from === to) continue;
    s = s.split(from).join(to);
  }
  if (s !== orig) {
    fs.writeFileSync(f, s);
    console.log('  ✓ 文档版本号已同步: ' + f);
    touched++;
  }
}
if (touched === 0) console.log('  ✓ 文档无旧版本号需更新（可能已同步或未硬编码）');
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
echo "  2. 提交改动（skills.lock + 文档版本号已自动同步）："
echo "     git add package.json oh-my-openagent.json package-lock.json skills.lock README.md docs/reference.md .opencode/instructions.md"
echo "     git commit -m \"upgrade: oh-my-openagent → $OMO_LATEST, plugin → $PLG_LATEST\""
