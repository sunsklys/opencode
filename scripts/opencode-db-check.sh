#!/bin/bash
# ============================================================
# opencode 数据库健康检查（只读，非破坏性）
#
# 在 opencode 运行时也能安全执行。检测 DB 膨胀程度，
# 评估 Bun NAPI 崩溃风险，给出维护建议。
#
# 风险阈值（基于实际崩溃 case 标定）：
#   - DB > 1GB / event > 15 万行 → ❌ 高风险（已接近崩溃临界）
#   - DB > 500MB / event > 8 万行 → ⚠️ 建议尽快维护
#   - DB < 300MB / event < 3 万行 → ✅ 健康
#
# 用法：make db-check 或 ./scripts/opencode-db-check.sh
# ============================================================

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

set -uo pipefail
DB_PATH="${OPENCODE_DB_PATH:-$HOME/.local/share/opencode/opencode.db}"

ok()   { echo "  ✅ $1"; }
info() { echo "  ℹ️  $1"; }
warn() { echo "  ⚠️  $1"; }
bad()  { echo "  ❌ $1"; }

echo "╔══════════════════════════════════════════╗"
echo "║     opencode 数据库健康检查               ║"
echo "╚══════════════════════════════════════════╝"
echo ""

[[ -f "$DB_PATH" ]] || { bad "数据库不存在: $DB_PATH"; exit 1; }
command -v sqlite3 >/dev/null || { bad "需要 sqlite3"; exit 1; }

# DB 是否被 opencode 持有（只读查询仍可行）
if pgrep -x opencode >/dev/null 2>&1; then
  info "opencode 正在运行（只读检查，安全）"
else
  info "opencode 未运行"
fi
echo ""

# ---------- 指标采集 ----------
DB_BYTES=$(stat -f %z "$DB_PATH" 2>/dev/null || stat -c %s "$DB_PATH" 2>/dev/null)
DB_MB=$(( DB_BYTES / 1024 / 1024 ))
DB_HR=$(du -h "$DB_PATH" | cut -f1)

SESSION_CNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session;" 2>/dev/null || echo "?")
MSG_CNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM message;" 2>/dev/null || echo "?")
PART_CNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM part;" 2>/dev/null || echo "?")
EVENT_CNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM event;" 2>/dev/null || echo "?")
EVENT_DATA_MB=$(sqlite3 "$DB_PATH" "SELECT SUM(LENGTH(data))/1024/1024 FROM event;" 2>/dev/null || echo "?")
AUTO_VACUUM=$(sqlite3 "$DB_PATH" "PRAGMA auto_vacuum;" 2>/dev/null || echo "?")

WAL_BYTES=0
[[ -f "$DB_PATH-wal" ]] && WAL_BYTES=$(stat -f %z "$DB_PATH-wal" 2>/dev/null || stat -c %s "$DB_PATH-wal" 2>/dev/null)
WAL_MB=$(( WAL_BYTES / 1024 / 1024 ))

# ---------- 输出 ----------
echo "── 数据库 ──"
printf "  %-22s %s (%dMB)\n" "主库大小:" "$DB_HR" "$DB_MB"
printf "  %-22s %dMB\n" "WAL 大小:" "$WAL_MB"
case "$AUTO_VACUUM" in 0) AV_DESC="OFF（需定期 VACUUM）";; 1) AV_DESC="FULL";; 2) AV_DESC="INCREMENTAL（自动增量回收）";; *) AV_DESC="$AUTO_VACUUM";; esac
printf "  %-22s %s\n" "auto_vacuum:" "$AV_DESC"
echo ""

echo "── 表行数 ──"
printf "  %-22s %s\n" "session:" "$SESSION_CNT"
printf "  %-22s %s\n" "message:" "$MSG_CNT"
printf "  %-22s %s\n" "part:" "$PART_CNT"
printf "  %-22s %s 行\n" "event:" "$EVENT_CNT"
printf "  %-22s %s MB\n" "event.data 列总量:" "$EVENT_DATA_MB"
echo ""

# ---------- 风险评估 ----------
echo "── 风险评估 ──"
RISK="ok"

# DB 大小
if [[ "$DB_MB" -ge 1024 ]]; then
  bad "DB ≥ 1GB：高风险（已达到实际崩溃 case 的临界值）"
  RISK="high"
elif [[ "$DB_MB" -ge 500 ]]; then
  warn "DB ≥ 500MB：建议尽快维护"
  [[ "$RISK" == "ok" ]] && RISK="warn"
else
  ok "DB 大小正常（< 500MB）"
fi

# event 表行数
if [[ "$EVENT_CNT" != "?" && "$EVENT_CNT" -ge 150000 ]]; then
  bad "event 表 ≥ 15 万行：高风险（崩溃 case 实测 16 万行）"
  RISK="high"
elif [[ "$EVENT_CNT" != "?" && "$EVENT_CNT" -ge 80000 ]]; then
  warn "event 表 ≥ 8 万行：建议维护"
  [[ "$RISK" == "ok" ]] && RISK="warn"
elif [[ "$EVENT_CNT" != "?" ]]; then
  ok "event 表行数正常（< 8 万）"
fi

# WAL 堆积
if [[ "$WAL_MB" -ge 100 ]]; then
  warn "WAL ≥ 100MB：堆积过多，下次退出 opencode 后建议维护"
  [[ "$RISK" == "ok" ]] && RISK="warn"
fi

echo ""
echo "── 建议 ──"
case "$RISK" in
  high)
    echo "  ❌ 高风险，建议立即维护："
    echo "     1. 完全退出 opencode"
    echo "     2. make db-maintain CLEAN=1 KEEP_DAYS=30"
    echo "     3. 重启 opencode"
    echo ""
    echo "  详细原理见 docs/troubleshooting.md「opencode 进程崩溃 / Bun NAPI panic」"
    ;;
  warn)
    echo "  ⚠️ 建议在方便时维护（无需紧急）："
    echo "     1. 退出 opencode"
    echo "     2. make db-maintain          # 仅压缩"
    echo "        make db-maintain CLEAN=1  # 含清理旧 session（更彻底）"
    ;;
  ok)
    echo "  ✅ 数据库健康，无需维护"
    echo "     建议每月跑一次 make db-check 监控趋势"
    ;;
esac
