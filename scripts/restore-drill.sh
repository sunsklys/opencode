#!/bin/bash
# ============================================================
# restore-drill.sh - 恢复演练：验证最新备份包真的可恢复
#
# 设计原则（未演练的备份 ≈ 没有备份）：
#   - 只读源包 + mktemp 临时目录，零副作用（不动仓库与运行时状态）
#   - 三类断言：关键文件在 / auth.json 不在（HEADLESS 三硬约束恢复侧闭环）/
#     skills.lock 哈希抽查匹配（skills 打进包时）
#   - 任何断言失败即 exit 1 — 演练失败 = 备份不可信，需立即排查导出链路
# ============================================================
set -euo pipefail

# 最新包：Backups 优先（launchd 周产物），Desktop 兜底（交互产物）
LATEST_PKG=$(ls -t "$HOME/Backups/opencode"/opencode-config-*.tar.gz \
                  "$HOME/Desktop"/opencode-config-*.tar.gz 2>/dev/null | head -1 || true)
if [ -z "$LATEST_PKG" ]; then
  echo "❌ 未找到任何备份包（~/Backups/opencode/ 与 ~/Desktop）— 先跑 make export" >&2
  exit 1
fi
echo "📦 演练对象: $LATEST_PKG ($(du -sh "$LATEST_PKG" | cut -f1))"
echo ""

DRILL_DIR=$(mktemp -d /tmp/restore-drill.XXXXXX)
trap 'rm -rf "$DRILL_DIR"' EXIT INT TERM
tar -xzf "$LATEST_PKG" -C "$DRILL_DIR"

FAIL=0

# ── 断言 1：关键文件在（恢复三步的最小集合）──────────────────
for f in opencode.json tui.json Makefile skills.lock package.json omo.jsonc.template; do
  if [ -f "$DRILL_DIR/config/opencode/$f" ]; then
    echo "  ✓ 关键文件在: config/opencode/$f"
  else
    echo "  ❌ 关键文件缺失: config/opencode/$f" >&2
    FAIL=1
  fi
done

# ── 断言 2：auth.json 不在（key 泄露面零容忍）────────────────
if tar -tzf "$LATEST_PKG" | grep -q 'auth\.json'; then
  echo "  ❌ 包内含 auth.json（key 泄露面）" >&2
  FAIL=1
else
  echo "  ✓ auth.json 零存在"
fi

# ── 断言 3：skills.lock 哈希抽查（首条；skills 未打包时跳过）──
if [ -d "$DRILL_DIR/agents/skills" ]; then
  SAMPLE=$(head -1 "$DRILL_DIR/config/opencode/skills.lock" 2>/dev/null || true)
  if [ -n "$SAMPLE" ]; then
    EXPECTED_HASH=$(echo "$SAMPLE" | awk '{print $1}')
    REL_PATH=$(echo "$SAMPLE" | awk '{print $2}')
    ACTUAL_HASH=$(shasum -a 256 "$DRILL_DIR/agents/skills/$REL_PATH" 2>/dev/null | awk '{print $1}' || echo "N/A")
    if [ "$EXPECTED_HASH" = "$ACTUAL_HASH" ]; then
      echo "  ✓ 哈希抽查匹配: agents/skills/$REL_PATH"
    else
      echo "  ❌ 哈希不匹配: $REL_PATH（期望 ${EXPECTED_HASH:0:12}… 实际 ${ACTUAL_HASH:0:12}…）" >&2
      FAIL=1
    fi
  fi
else
  echo "  ℹ️  本包未含 skills（交互导出未选）— 跳过哈希抽查"
fi

echo ""
if [ "$FAIL" = "0" ]; then
  echo "✅ 恢复演练 PASS — 备份可信（对象: $(basename "$LATEST_PKG")）"
else
  echo "❌ 恢复演练 FAIL — 备份不可信，立即排查导出链路" >&2
  exit 1
fi
