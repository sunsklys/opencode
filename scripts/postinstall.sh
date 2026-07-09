#!/bin/bash
# ============================================================
# npm postinstall 钩子：全局 MCP 依赖
# 任一步失败立即中断（set -euo pipefail）
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== 1/2 全局安装 claude-mermaid ==="
npm i -g claude-mermaid
echo "  ✓ claude-mermaid 完成"

echo ""
echo "=== 2/2 全局安装 codegraph ==="
npm i -g @colbymchenry/codegraph
echo "  ✓ codegraph 完成"

echo ""
echo "✓ postinstall 全部完成（2/2 步）"
