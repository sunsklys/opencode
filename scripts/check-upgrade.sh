#!/bin/bash
# ============================================================
# opencode 升级监控
#
# 检测 opencode 是否有新版，以及本地内嵌 Bun 是否已脱离
# v1.3.14 NAPI panic 崩溃区间。stable 渠道当前仍内嵌 1.3.14，
# 本命令用于在新版发布、内嵌 Bun 升级时第一时间预警根治时机。
#
# 用法：make check-upgrade
# ============================================================

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

set -euo pipefail

BAD_BUN="1.3.14"   # 已知会触发 napi_create_error panic 的版本

echo "╔══════════════════════════════════════════╗"
echo "║     opencode 升级监控                     ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 本地版本
LOCAL_VER=$(opencode --version 2>/dev/null || echo "未安装")
echo "  本地版本:  $LOCAL_VER"

# 解析 opencode 真实二进制路径（macOS symlink 多层，用 perl abs_path）
BIN_PATH="$(which opencode 2>/dev/null || echo "")"
if command -v perl >/dev/null 2>&1 && [ -n "$BIN_PATH" ]; then
  BIN_PATH=$(perl -MCwd=abs_path -e 'print abs_path($ARGV[0])' "$BIN_PATH" 2>/dev/null || echo "$BIN_PATH")
fi

# 本地内嵌 Bun 版本
LOCAL_BUN="未知"
[ -n "$BIN_PATH" ] && [ -f "$BIN_PATH" ] && LOCAL_BUN=$(strings "$BIN_PATH" 2>/dev/null | grep -oE 'Bun v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
LOCAL_BUN_VER=$(echo "$LOCAL_BUN" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "")
echo "  内嵌 Bun:  $LOCAL_BUN"

# npm latest
printf "  查询 npm latest..."
LATEST_VER=$(npm view opencode-ai version 2>/dev/null || echo "查询失败")
echo " $LATEST_VER"
echo ""

echo "── 结论 ──"
if [[ "$LOCAL_VER" != "$LATEST_VER" && "$LATEST_VER" != "查询失败" ]]; then
  echo "  ℹ️  有新版: ${LATEST_VER}（当前 ${LOCAL_VER}）"
  echo ""
  echo "  升级步骤："
  echo "    1. make upgrade"
  echo "    2. 重跑 make check-upgrade 验证 Bun 版本"
else
  echo "  ✅ 已是最新 stable（${LOCAL_VER}）"
  if [[ "$LOCAL_BUN_VER" == "$BAD_BUN" ]]; then
    echo "  ⚠️  内嵌 Bun 仍为 ${BAD_BUN}（NAPI panic 根因未消除）"
    echo "     缓解：make db-check / make db-maintain"
    echo "     根治：等待 opencode 内嵌 Bun 升级，定期跑本命令监控"
  else
    echo "  ✅ 内嵌 Bun 已非 ${BAD_BUN}，NAPI 崩溃根因大概率已消除"
  fi
fi
