#!/bin/bash
# ============================================================
# opencode 数据库维护脚本
#
# 背景：opencode 内嵌 Bun v1.3.14 的 NAPI 实现存在 panic bug，
#   在 opencode.db 膨胀（event 表 16 万行 / data 列 500MB+）+
#   长时间运行的压力下，bun:sqlite 的错误处理路径会触发
#   napi_create_error 致命错误，导致进程整体崩溃。
#
# 本脚本通过「清理旧 session + VACUUM 压缩」降低 DB 体积，
#   降低 bun:sqlite 触发 NAPI 错误路径的概率。
#
# 功能：
#   1. 安全检查（opencode 必须先完全退出）
#   2. 自动备份（保留最近 5 份）
#   3. 清理旧 session（foreign_keys=ON，CASCADE 联动 message/part/event）
#   4. WAL checkpoint + VACUUM 压缩回收空间
#
# 用法：
#   make db-maintain                          # 安全模式：备份 + VACUUM（不删数据）
#   make db-maintain CLEAN=1                  # 清理 30 天前 session + VACUUM
#   make db-maintain CLEAN=1 KEEP_DAYS=7      # 保留 7 天
#   ./scripts/opencode-db-maintain.sh --dry-run --clean   # 预览将删除的内容
#   make db-maintain INCREMENTAL=1             # 一次性切换 auto_vacuum 到 INCREMENTAL（未来自动增量回收）
# ============================================================

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

set -euo pipefail

DB_PATH="${OPENCODE_DB_PATH:-$HOME/.local/share/opencode/opencode.db}"
BACKUP_DIR="$HOME/.local/share/opencode/backup"
KEEP_DAYS=30
DO_CLEAN=false
DRY_RUN=false
SET_INCREMENTAL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) DO_CLEAN=true; shift ;;
    --keep-days)
      KEEP_DAYS="${2:?--keep-days 需要参数}"
      [[ "${KEEP_DAYS}" =~ ^[0-9]+$ ]] || { echo "  ❌ --keep-days 必须为正整数（得到 ${KEEP_DAYS}）" >&2; exit 1; }
      shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --incremental) SET_INCREMENTAL=true; shift ;;
    --db) DB_PATH="${2:?--db 需要参数}"; shift 2 ;;
    -h|--help)
      sed -n '3,25p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "未知参数: $1（用 --help 查看用法）" >&2; exit 1 ;;
  esac
done

ok()   { echo "  ✅ $1"; }
info() { echo "  ℹ️  $1"; }
warn() { echo "  ⚠️  $1"; }
die()  { echo "  ❌ $1" >&2; exit 1; }

echo "╔══════════════════════════════════════════╗"
echo "║     opencode 数据库维护                   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ---------- 1. 前置检查 ----------
[[ -f "$DB_PATH" ]] || die "数据库不存在: $DB_PATH"
command -v sqlite3 >/dev/null || die "需要 sqlite3（macOS 自带，Linux 需 apt install sqlite3）"

# 安全门：opencode 不能在运行（持有 DB 锁，VACUUM 会失败甚至触发同样的 NAPI 崩溃）
# 用 pgrep -x 精确匹配 opencode 主进程名(comm)，排除 bash/node 子进程和本脚本
if pgrep -x opencode >/dev/null 2>&1; then
  die "检测到 opencode 进程正在运行。请先完全退出 opencode（Ctrl+C 或 :q）再执行维护。"
fi
ok "opencode 未运行，DB 锁已释放"

# 磁盘空间检查（VACUUM 需约 2x DB 空间）
DB_SIZE_KB=$(du -k "$DB_PATH" | cut -f1)
AVAIL_KB=$(df -k "$(dirname "$DB_PATH")" | tail -1 | awk '{print $4}')
NEEDED_KB=$((DB_SIZE_KB * 2))
if [[ "$AVAIL_KB" -lt "$NEEDED_KB" ]]; then
  die "磁盘空间不足：VACUUM 需 ~$((NEEDED_KB/1024))MB，当前可用仅 $((AVAIL_KB/1024))MB"
fi

SIZE_BEFORE=$(du -h "$DB_PATH" | cut -f1)
info "数据库路径: $DB_PATH"
info "当前大小: $SIZE_BEFORE"
$DRY_RUN && warn "DRY-RUN 模式：仅预览，不实际修改"
echo ""

# ---------- 2. 备份 ----------
echo "── 备份 ──"
if $DRY_RUN; then
  warn "DRY-RUN：跳过备份"
else
  mkdir -p "$BACKUP_DIR"
  BACKUP="$BACKUP_DIR/opencode.db.backup.$(date +%Y%m%d%H%M%S)"
  cp "$DB_PATH" "$BACKUP"
  [[ -f "$DB_PATH-wal" ]] && cp "$DB_PATH-wal" "$BACKUP-wal"
  ok "已备份到: $BACKUP"
  # 保留最近 5 份备份
  ( cd "$BACKUP_DIR" && ls -t opencode.db.backup.* 2>/dev/null | tail -n +6 | while read -r old; do
      rm -f "$old" "$old-wal"
    done )
fi
echo ""

# ---------- 3. 清理旧 session（可选）----------
if $DO_CLEAN; then
  echo "── 清理旧 session（保留 ${KEEP_DAYS} 天）──"
  # session.time_updated 是毫秒时间戳
  CUTOFF=$(( $(date +%s) * 1000 - KEEP_DAYS * 86400000 ))

  TO_DELETE=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session WHERE time_updated < $CUTOFF;")
  TOTAL=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session;")
  info "总 session: ${TOTAL}，待删除（> ${KEEP_DAYS} 天未更新）: ${TO_DELETE}"

  if [[ "$TO_DELETE" -eq 0 ]]; then
    ok "没有需要清理的旧 session"
  elif $DRY_RUN; then
    warn "DRY-RUN：将删除 $TO_DELETE 个 session（CASCADE 联动 message/part/event）："
    sqlite3 -separator '  |  ' "$DB_PATH" \
      "SELECT substr(id,1,28), substr(title,1,32), datetime(time_updated/1000,'unixepoch','localtime')
       FROM session WHERE time_updated < $CUTOFF ORDER BY time_updated LIMIT 15;" 2>/dev/null || true
    [[ $TO_DELETE -gt 15 ]] && info "... 及其余 $((TO_DELETE-15)) 个"
  else
    # 关键：SQLite 默认 foreign_keys=0，CASCADE 不生效！
    # 必须在同一连接内 PRAGMA foreign_keys=ON 再 DELETE，让
    # session→message→part 和 event_sequence→event 的 ON DELETE CASCADE 触发
    sqlite3 "$DB_PATH" <<SQL
PRAGMA foreign_keys = ON;
BEGIN;
DELETE FROM session WHERE time_updated < $CUTOFF;
COMMIT;
SQL
    AFTER=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session;")
    ok "已删除 $((TOTAL - AFTER)) 个旧 session，剩余 ${AFTER}（CASCADE 联动 message/part/event）"
  fi
else
  info "未启用清理（用 --clean 或 make db-maintain CLEAN=1 清理旧 session）"
fi
echo ""

# ---------- 4. WAL checkpoint + VACUUM ----------
echo "── 压缩 ──"
if $DRY_RUN; then
  warn "DRY-RUN：跳过 WAL checkpoint 和 VACUUM"
else
  # 先把 WAL 合并进主库，避免 VACUUM 时丢 WAL 数据
  sqlite3 "$DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null
  ok "WAL 已合并"
  # 可选：切换到 INCREMENTAL auto_vacuum（一次性；未来 session 删除时自动增量回收，免再全量 VACUUM）
  if $SET_INCREMENTAL; then
    sqlite3 "$DB_PATH" "PRAGMA auto_vacuum = 2;"
    ok "auto_vacuum 设为 INCREMENTAL（将在下方 VACUUM 中生效）"
  fi
  # VACUUM 重建数据库文件，回收空闲页（并应用新 auto_vacuum 模式）
  sqlite3 "$DB_PATH" "VACUUM;"
  ok "VACUUM 完成"
fi

SIZE_AFTER=$(du -h "$DB_PATH" | cut -f1)
echo ""
echo "── 结果 ──"
info "压缩前: $SIZE_BEFORE"
info "压缩后: $SIZE_AFTER"
echo ""
echo "── 表行数 ──"
for t in session message part event; do
  cnt=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM $t;" 2>/dev/null || echo "N/A")
  printf "  %-10s %s\n" "$t" "$cnt"
done

echo ""
if [[ "$SIZE_BEFORE" != "$SIZE_AFTER" ]] && ! $DRY_RUN; then
  ok "维护完成，DB 已压缩"
else
  ok "维护完成"
fi
echo ""
echo "下一步：重新启动 opencode 即可。"
