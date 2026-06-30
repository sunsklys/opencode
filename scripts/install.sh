#!/bin/bash
# ============================================================
# 依赖安装脚本
# npm install + opencode-mem 全局装 + 软链（绕过 linux binary bug）
# ============================================================
# 注意：set -e 保留（出错即停），去掉 -u（避免复杂变量展开误报）
set -eo pipefail

cd "$(dirname "$0")/.."

# 从 package.json 读取 oh-my-openagent 版本（单一真相源）
OMO_VER=$(node -p "require('./package.json').dependencies['oh-my-openagent']")

echo "=== 1/3 npm install（含 postinstall: patch-package + 全局 MCP 依赖）==="
npm install
# ⚠ npm install 会清理 node_modules 里的 extraneous 包（含 opencode-mem 软链），
# 所以软链必须在 npm install 之后重建（见第 3 步）。

echo ""
echo "=== 2/3 全局依赖安装（opencode-mem + mcp-remote）==="
# npm i -g 本身幂等：已安装最新版时自动跳过，无需手动判断版本
# - opencode-mem: 绕过 linux platform binary bug 需全局装 + 软链
# - mcp-remote: notion MCP 直调避免每次 npx 冷启动 2s 延迟
npm i -g opencode-mem mcp-remote

echo ""
echo "=== 3/3 建立软链 + 验证 ==="
# 软链必须在 npm install 之后建（npm 会清理 extraneous 软链）
ln -sf "$(npm root -g)/opencode-mem" node_modules/opencode-mem

# oh-my-openagent 补丁应用检查
if grep -q "/glm/i" node_modules/oh-my-openagent/dist/index.js 2>/dev/null; then
  echo "✓ oh-my-openagent hephaestus GLM 补丁已应用"
else
  echo "⚠ oh-my-openagent 补丁未应用（hephaestus agent 可能无法使用 GLM 模型）"
  echo "  检查 patches/oh-my-openagent+${OMO_VER}.patch 是否存在"
fi

# opencode-mem 软链 + 版本验证（防御性赋值：node -p 失败时 fallback 到"未知"）
MEM_VER=$(node -p "require('./node_modules/opencode-mem/package.json').version" 2>/dev/null) || MEM_VER="未知"
echo "✓ opencode-mem@${MEM_VER}（软链 → $(readlink node_modules/opencode-mem)）"

echo ""
echo "✅ 依赖安装完成"
