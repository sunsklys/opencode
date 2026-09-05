#!/bin/bash
# ============================================================
# opencode 日志轮转（copytruncate 模式）
#
# 背景：~/.local/share/opencode/log/opencode.log 单文件持续增长
# （实测 99MB，年化 ~400MB），opencode 本身无轮转配置。本脚本用
# copytruncate 模式轮转：先 cp 再 `: >` 截断原文件，inode 不变，
# opencode 进程已打开的 FD 继续有效，无需重启。
#
# 已知代价（copytruncate 固有竞态）：cp 与截断之间写入的少量日志
# 会丢失。月度低频场景可接受。
#
# 行为：
#   - 仅当 opencode.log > 20MB 才轮转
#   - 轮转产物：opencode.log.<YYYYMMDD-HHMMSS>.gz（gzip 压缩）
#   - 保留最新 3 份 .gz，更旧的删除（时间戳前缀保证字典序=时间序）
#   - gzip 失败时不截断原文件（数据无损优先），仅残留未压缩副本
#   - --dry-run：只输出计划，不做任何修改
#
# 用法：bash scripts/opencode-log-rotate.sh [--dry-run]
#   可用环境变量覆盖（测试用）：LOG_DIR / LOG_FILE_NAME /
#   SIZE_THRESHOLD_MB / KEEP
# ============================================================

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

set -uo pipefail

LOG_DIR="${LOG_DIR:-$HOME/.local/share/opencode/log}"
LOG_FILE_NAME="${LOG_FILE_NAME:-opencode.log}"
SIZE_THRESHOLD_MB="${SIZE_THRESHOLD_MB:-20}"
KEEP="${KEEP:-3}"

DRY_RUN=0
case "${1:-}" in
"") ;;
--dry-run) DRY_RUN=1 ;;
*)
	echo "用法: $0 [--dry-run]"
	exit 1
	;;
esac

LOG_PATH="$LOG_DIR/$LOG_FILE_NAME"

ok() { echo "  ✅ $1"; }
info() { echo "  ℹ️  $1"; }
bad() { echo "  ❌ $1"; }

# 待删的最旧归档：升序后前 (总数 - keep) 行；keep 为旧档可保留份数
# （dry-run 预估时即将新增 1 份占名额，传 KEEP-1；真跑清理在轮转后，传 KEEP）
stale_archives() {
	ls -1 "$LOG_DIR/$LOG_FILE_NAME".*.gz 2>/dev/null | sort | \
		awk -v keep="${1:-$KEEP}" '{a[NR]=$0} END {for (i=1; i<=NR-keep; i++) print a[i]}' || true
}

size_bytes() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null; }

echo "── opencode 日志轮转 ──"
info "目标: ${LOG_PATH}（阈值 >${SIZE_THRESHOLD_MB}MB，保留 ${KEEP} 份 gz）"

[[ -f "$LOG_PATH" ]] || {
	bad "日志文件不存在: $LOG_PATH"
	exit 1
}

BYTES=$(size_bytes "$LOG_PATH")
MB=$((BYTES / 1024 / 1024))

if [[ "$BYTES" -le $((SIZE_THRESHOLD_MB * 1024 * 1024)) ]]; then
	ok "未达阈值（${MB}MB ≤ ${SIZE_THRESHOLD_MB}MB），跳过"
	exit 0
fi

STAMP=$(date +%Y%m%d-%H%M%S)
ROTATED="$LOG_DIR/$LOG_FILE_NAME.$STAMP"

if [[ "$DRY_RUN" -eq 1 ]]; then
	STALE=$(stale_archives $((KEEP - 1)))
	info "[dry-run] 达到阈值（${MB}MB > ${SIZE_THRESHOLD_MB}MB），轮转计划："
	echo "    1. cp $LOG_PATH → $ROTATED"
	echo "    2. gzip $ROTATED"
	echo "    3. 截断原文件（: > ${LOG_PATH}，保持已打开 FD 有效）"
	if [[ -n "$STALE" ]]; then
		echo "    4. 删除超出保留份数（${KEEP} 份）的旧归档："
		echo "$STALE" | sed 's/^/       - /'
	else
		echo "    4. 无超出保留份数的旧归档需删除"
	fi
	ok "[dry-run] 计划输出完毕，未做任何修改"
	exit 0
fi

if [[ -e "$ROTATED" || -e "$ROTATED.gz" ]]; then
	bad "轮转目标已存在: $ROTATED(.gz)（同一秒重复轮转？）"
	exit 1
fi

# 先 cp + gzip，全部成功后才截断原文件（失败则原文件不动，数据无损）
if ! cp "$LOG_PATH" "$ROTATED" || ! gzip "$ROTATED"; then
	bad "复制/压缩失败，原文件未截断（残留副本可人工处理后删除: $ROTATED*）"
	exit 1
fi
: >"$LOG_PATH"

AFTER_BYTES=$(size_bytes "$LOG_PATH")
GZ_KB=$(($(size_bytes "$ROTATED.gz") / 1024))
ok "已轮转 ${MB}MB → $LOG_FILE_NAME.$STAMP.gz（${GZ_KB}KB），原文件截断为 ${AFTER_BYTES}B"

# 清理基于轮转后的真实集合（含新档），保留最新 ${KEEP} 份
STALE=$(stale_archives)
if [[ -n "$STALE" ]]; then
	echo "$STALE" | while IFS= read -r f; do
		rm -f "$f"
		echo "  🗑️  已删除旧归档: $(basename "$f")"
	done
fi

TOTAL=$(ls -1 "$LOG_DIR/$LOG_FILE_NAME".*.gz 2>/dev/null | sort | wc -l | tr -d ' ')
ok "当前保留归档 ${TOTAL} 份（上限 ${KEEP} 份）"
