#!/usr/bin/env bash
# 安装 pre-commit hook 到 .git/hooks/
# 用法：bash scripts/install-hooks.sh
set -euo pipefail

HOOK_SRC="$(cd "$(dirname "$0")/.." && pwd)/.githooks/pre-commit"
HOOK_DST="$(cd "$(dirname "$0")/.." && pwd)/.git/hooks/pre-commit"

if [ ! -f "$HOOK_SRC" ]; then
  echo "❌ 找不到源 hook: $HOOK_SRC"
  exit 1
fi

cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"

echo "✅ Pre-commit hook 已安装: $HOOK_DST"
echo "   每次 commit 前自动运行: make check (critical) + make tui-sync"
