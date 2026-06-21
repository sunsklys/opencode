#!/bin/bash
# ============================================================
# npm postinstall 钩子：patch-package + 全局 MCP 依赖
# 任一步失败立即中断（set -euo pipefail），不再 || echo 兜底
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== 1/3 patch-package（hephaestus GLM 补丁）==="
patch-package
echo "  ✓ patch-package 完成"

echo ""
echo "=== 2/3 全局安装 claude-mermaid ==="
npm i -g claude-mermaid
echo "  ✓ claude-mermaid 完成"

echo ""
echo "=== 3/3 全局安装 codegraph ==="
npm i -g @colbymchenry/codegraph
echo "  ✓ codegraph 完成"

echo ""
echo "✓ postinstall 全部完成"
