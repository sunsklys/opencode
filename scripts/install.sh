#!/bin/bash
# ============================================================
# 依赖安装脚本
# npm install + opencode-mem 全局装 + 软链（绕过 linux binary bug）
# ============================================================
# 注意：set -e 保留（出错即停），去掉 -u（避免复杂变量展开误报）
set -eo pipefail

cd "$(dirname "$0")/.."

# ---------- 镜像延迟预检 ----------
# npmmirror 对 @opencode-ai/* 同步滞后会导致 plugin 已发但 sdk 未同步 → ETARGET。
# 检测到延迟时全程使用官方源（install.sh + postinstall.sh 内所有 npm 调用）。
REGISTRY="${NPM_REGISTRY:-}"
if [ -z "$REGISTRY" ]; then
  OFFICIAL_VER=$(npm view @opencode-ai/sdk version --registry=https://registry.npmjs.org 2>/dev/null || echo "")
  MIRROR_VER=$(npm view @opencode-ai/sdk version 2>/dev/null || echo "")
  if [ -n "$OFFICIAL_VER" ] && [ "$OFFICIAL_VER" != "$MIRROR_VER" ]; then
    REGISTRY="https://registry.npmjs.org"
    echo "⚠️ 镜像源 @opencode-ai/sdk 同步延迟（镜像 $MIRROR_VER / 官方 $OFFICIAL_VER），本次全程使用官方源"
  fi
fi
[ -n "$REGISTRY" ] && export NPM_REGISTRY  # 传递给 postinstall.sh

# npm wrapper：REGISTRY 非空时自动加 --registry
_npm() {
  if [ -n "$REGISTRY" ]; then
    npm "$@" --registry="$REGISTRY"
  else
    npm "$@"
  fi
}

echo "=== 1/3 npm install（含 postinstall: 全局 MCP 依赖）==="
_npm install
# ⚠ npm install 会清理 node_modules 里的 extraneous 包（含 opencode-mem 软链），
# 所以软链必须在 npm install 之后重建（见第 3 步）。

echo ""
echo "=== 2/3 全局依赖安装（opencode-mem）==="
# npm i -g 本身幂等：已安装最新版时自动跳过，无需手动判断版本
# - opencode-mem: 绕过 linux platform binary bug 需全局装 + 软链
_npm i -g opencode-mem

echo ""
echo "=== 3/3 建立软链 + 验证 ==="
# 软链必须在 npm install 之后建（npm 会清理 extraneous 软链）
ln -sf "$(npm root -g)/opencode-mem" node_modules/opencode-mem

# opencode-mem 软链 + 版本验证（防御性赋值：node -p 失败时 fallback 到"未知"）
MEM_VER=$(node -p "require('./node_modules/opencode-mem/package.json').version" 2>/dev/null) || MEM_VER="未知"
echo "✓ opencode-mem@${MEM_VER}（软链 → $(readlink node_modules/opencode-mem)）"

# 清 opencode-mem @latest 缓存（下次启动 opencode 重拉，与全局版本同步）
rm -rf "$HOME/.cache/opencode/packages/opencode-mem@latest" 2>/dev/null || true

echo ""
echo "✅ 依赖安装完成"
