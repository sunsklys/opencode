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
echo "=== 4/4 清理 opencode plugin 缓存（防 @latest 漂移）==="
node -e "const fs=require('fs'),path=require('os').homedir()+'/.cache/opencode/packages/oh-my-openagent@latest';if(fs.existsSync(path)){fs.rmSync(path,{recursive:true,force:true});console.log('  ✓ 已清理 '+path)}else{console.log('  ✓ 缓存不存在，跳过')}" || echo "  ⚠ 清理失败（不阻断）"
echo ""
echo "✓ postinstall 全部完成（4/4 步）"
