#!/bin/bash
# ============================================================
# upgrade.sh - 一键升级 oh-my-openagent + @opencode-ai/plugin 到 npm 最新版
#
# 与 `make update` 的区别：
#   - update: 按 package.json 精确版本重装（patch-package 重新应用现有 patch）
#   - upgrade: 查 npm 最新版 → 改 package.json → 删旧 patch → 重装
#              → 检测 GLM 补丁是否仍需要 → 注入并生成新 patch → 更新 $schema URL
#
# 设计原则：
#   - patch-package 按文件名锁版本（oh-my-openagent+X.Y.Z.patch），升级必须重生成
#   - 若未来上游原生支持 GLM（isHephaestusSupportedModel 含 /glm/i），自动跳过 patch
#   - $schema URL 同步到新版本（oh-my-openagent.json 顶部）
#   - 不自动跑 patch-sync/check：plugin 缓存需要先启动 opencode 才能同步
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
echo "=== 1/7 查询 npm 最新版 ==="
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
cp -r patches package.json package-lock.json "$BACKUP_DIR/" 2>/dev/null || true
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
echo "=== 2/7 更新 package.json ==="
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


echo ""
echo "=== 3/7 删除旧 GLM patch ==="
node -e "
const fs = require('fs');
const path = require('path');
const dir = 'patches';
if (!fs.existsSync(dir)) { process.exit(0); }
let removed = 0;
for (const f of fs.readdirSync(dir)) {
  if (f.startsWith('oh-my-openagent+') && f.endsWith('.patch')) {
    fs.rmSync(path.join(dir, f));
    console.log('  ✓ 删除 ' + f);
    removed++;
  }
}
if (removed === 0) console.log('  （无旧 patch）');
"

# ---------- 4. 清 node_modules + npm install（触发 postinstall: claude-mermaid + codegraph）----------
echo ""
echo "=== 4/7 清理 node_modules 并重装 ==="
node -e "require('fs').rmSync('node_modules',{recursive:true,force:true}); console.log('  ✓ node_modules 已清除')"
rm -f package-lock.json
bash scripts/install.sh
bash scripts/sync-omo-skills.sh

# ---------- 5. 检测 GLM 补丁是否仍需要 ----------
echo ""
echo "=== 5/7 检测 GLM 补丁需求 ==="
INDEX_JS="node_modules/oh-my-openagent/dist/index.js"
NEED_PATCH=false
if grep -q "/glm/i.test(modelName)" "$INDEX_JS" 2>/dev/null; then
  echo "  ✓ 上游已原生支持 GLM（isHephaestusSupportedModel 含 /glm/i），无需补丁"
  echo "  → 可以删除 patches/ 目录下任何手动 patch 引用"
else
  echo "  ⚠ 上游 isHephaestusSupportedModel 仍未含 /glm/i，需要打补丁"
  NEED_PATCH=true
fi

# ---------- 6. 注入 GLM 支持并生成新 patch ----------
if [ "$NEED_PATCH" = "true" ]; then
  echo ""
  echo "=== 6/7 注入 GLM 支持并生成新 patch ==="
  node -e "
const fs = require('fs');
const p = '$INDEX_JS';
let s = fs.readFileSync(p, 'utf8');
// 精确匹配 isHephaestusSupportedModel 的 return 语句
const oldStr = 'return GPT_5_3_CODEX_RE.test(modelName) || GPT_5_4_RE.test(modelName) || GPT_5_5_RE.test(modelName);';
const newStr = 'return GPT_5_3_CODEX_RE.test(modelName) || GPT_5_4_RE.test(modelName) || GPT_5_5_RE.test(modelName) || /glm/i.test(modelName);';
const occurrences = s.split(oldStr).length - 1;
if (occurrences === 0) {
  console.error('❌ 找不到目标 return 语句');
  console.error('   上游可能已重构 isHephaestusSupportedModel，请手动检查 dist/index.js');
  process.exit(1);
}
if (occurrences > 1) {
  console.error('❌ 期望 1 处匹配，实际 ' + occurrences + ' 处（防止误改）');
  process.exit(1);
}
s = s.replace(oldStr, newStr);
fs.writeFileSync(p, s);
console.log('  ✓ 已注入 || /glm/i.test(modelName)');
"
  npx patch-package oh-my-openagent
fi

# ---------- 7. 更新 oh-my-openagent.json 的 $schema URL ----------
echo ""
echo "=== 7/7 更新 oh-my-openagent.json 的 \$schema URL ==="
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
echo "  1. 启动 opencode 一次（创建 plugin 缓存），随即退出（Ctrl+C 或 /exit）："
echo "     opencode"
echo ""
echo "  2. 同步 GLM 补丁到 opencode 两处缓存："
echo "     make patch-sync"
echo ""
echo "  3. 体检（应该全绿或仅 @latest 漂移警告）："
echo "     make check"
echo ""
echo "  4. 如果 skills.lock 哈希不匹配（lark skills 被升级时更新过）："
echo "     make skills-lock    # 重新生成"
echo ""
echo "  5. 提交改动："
echo "     git add package.json patches/ oh-my-openagent.json README.md skills.lock"
echo "     git commit -m \"upgrade: oh-my-openagent → $OMO_LATEST, plugin → $PLG_LATEST\""
