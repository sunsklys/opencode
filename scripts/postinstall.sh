#!/bin/bash
# ============================================================
# npm postinstall 钩子：patch-package + 全局 MCP 依赖
# 任一步失败立即中断（set -euo pipefail），不再 || echo 兜底
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== 1/4 patch-package（hephaestus GLM 补丁）==="
patch-package
echo "  ✓ patch-package 完成"

echo ""
echo "=== 2/4 全局安装 claude-mermaid ==="
npm i -g claude-mermaid
echo "  ✓ claude-mermaid 完成"

echo ""
echo "=== 3/4 全局安装 codegraph ==="
npm i -g @colbymchenry/codegraph
echo "  ✓ codegraph 完成"

echo ""
echo "=== 4/4 清理 opencode plugin 缓存（防 @latest 漂移：oh-my-openagent + opencode-mem）==="
node -e "const fs=require('fs'),path=require('path'),os=require('os');const pkgDir=path.join(os.homedir(),'.cache','opencode','packages');const targets=['oh-my-openagent@latest','opencode-mem@latest'];let cleaned=0;for(const t of targets){const p=path.join(pkgDir,t);if(fs.existsSync(p)){fs.rmSync(p,{recursive:true,force:true});console.log('  ✓ 已清理 '+p);cleaned++}}if(cleaned===0)console.log('  ✓ 缓存不存在，跳过')" || echo "  ⚠ 清理失败（不阻断）"
echo ""
echo "✓ postinstall 全部完成（4/4 步）"
