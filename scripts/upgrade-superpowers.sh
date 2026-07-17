#!/bin/bash
# ============================================================
# superpowers plugin 升级脚本
# 查询远端最新 tag → 改 opencode.json → 清缓存 → 提示重启
# ============================================================
set -e

cd "$(dirname "$0")/.."

OPENCODE_JSON="opencode.json"
REMOTE_URL="https://github.com/obra/superpowers.git"

# --- 1. 读当前锁定版本 ---
CURRENT=$(grep -oE 'superpowers@git\+https://github\.com/obra/superpowers\.git#v[0-9]+\.[0-9]+\.[0-9]+' "$OPENCODE_JSON" | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')

if [ -z "$CURRENT" ]; then
  echo "❌ opencode.json 中未找到 superpowers 版本锁定（#vX.Y.Z）"
  echo "   请先手动锁定，例如：superpowers@git+https://github.com/obra/superpowers.git#v6.1.1"
  exit 1
fi

echo "当前锁定版本：$CURRENT"

# --- 2. 查远端最新 tag ---
echo "查询远端最新 tag..."
REMOTE_TAGS=$(git ls-remote --tags "$REMOTE_URL" 2>/dev/null | grep -v '\^{}$' | awk '{print $2}' | sed 's|refs/tags/||' || true)

if [ -z "$REMOTE_TAGS" ]; then
  echo "❌ 无法获取远端 tag（网络问题或仓库异常）"
  exit 1
fi

LATEST=$(echo "$REMOTE_TAGS" | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | sed 's/^/v/')

echo "远端最新 tag：$LATEST"

# --- 3. 比对 ---
if [ "$CURRENT" = "$LATEST" ]; then
  echo "✓ 已是最新，无需升级"
  exit 0
fi

# --- 4. 替换 opencode.json ---
echo "更新 opencode.json：$CURRENT → $LATEST ..."
sed -i '' "s|superpowers@git+https://github.com/obra/superpowers.git#v[0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}|superpowers@git+https://github.com/obra/superpowers.git#$LATEST|" "$OPENCODE_JSON"

# JSON 合法性校验
# JSON 合法性校验（用 jq 避免 node -e 被 permission 拒）
jq empty "$OPENCODE_JSON" 2>/dev/null || {
  echo "❌ opencode.json JSON 解析失败，请手动检查"
  exit 1
}

# --- 5. 清缓存 ---
CLEANED=0
if [ -d "$HOME/.cache/opencode/packages" ]; then
  echo "清理旧版本缓存..."
  # 用 find 避免 glob 在 bash 下的歧义
  find "$HOME/.cache/opencode/packages" -maxdepth 1 -name "superpowers@git+https:*" -exec rm -rf {} + 2>/dev/null && CLEANED=1 || true
fi
if [ "$CLEANED" -eq 1 ]; then
  echo "  ✓ 缓存已清"
else
  echo "  ℹ️ 无旧缓存可清（首次安装）"
fi

# --- 6. 重装依赖（让 opencode 下次启动时拉新版本）---
echo "重装依赖..."
bash scripts/install.sh > /dev/null 2>&1 || echo "  ⚠ scripts/install.sh 失败（可手动 npm install）"

echo ""
echo "✓ superpowers 升级完成：$CURRENT → $LATEST"
echo "  请重启 opencode 以加载新版本"
