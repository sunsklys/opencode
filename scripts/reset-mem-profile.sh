#!/usr/bin/env bash
# 重置膨胀的 opencode-mem user profile
# 背景：profile_data 16.9MB（408 prefs/115 patterns），user-profiles.db 161MB。
#       膨胀根因：2.24.x 时代 embedding merge 未生效期间的 append 存量 + decay
#       只删「evidence<3 且超2天未见」的条目，历史债被锁死。
#       2.25.0 三道防线（embedding merge / decay / 每100 prompts 的 auto-cleanup）
#       在空 profile 规模下全部正常工作，重置后复发风险低（日志已验证 embedding 在工作）。
# 实现：直接删 db 三件套而非 DELETE+VACUUM——插件 initDatabase() 全部 CREATE TABLE
#       IF NOT EXISTS 幂等重建；且 VACUUM 不回收 WAL 文件，rm 更快更彻底。
# 用法：完全退出所有 opencode 进程后运行：bash scripts/reset-mem-profile.sh
set -euo pipefail

DB="$HOME/.opencode-mem/data/user-profiles.db"

# 1. 前置检查：不允许有 opencode 进程持有该库（含 wal）
if lsof "$DB" >/dev/null 2>&1 || lsof "$DB-wal" >/dev/null 2>&1; then
  echo "✗ 仍有进程占用："
  lsof "$DB" "$DB-wal" 2>/dev/null | awk 'NR>1 {print "  ", $1, "PID", $2}' | sort -u
  echo "  请先完全退出所有 opencode，再运行本脚本。"
  exit 1
fi

# 2. 备份（db + wal，带时间戳）
STAMP=$(date +%Y%m%d-%H%M%S)
for f in "$DB" "$DB-wal"; do
  [ -f "$f" ] && cp "$f" "$f.bak-reset-$STAMP" && echo "✓ 已备份 $(basename "$f")"
done

# 3. 删除三件套（db + wal + shm），插件重启时幂等重建空表
rm -f "$DB" "$DB-wal" "$DB-shm"

echo "✓ user-profiles.db 三件套已删除（161M → 0）"
echo ""
echo "下一步：启动 opencode，插件自动重建空 profile 表并从零学习。"
echo "  - interval=10 只加速新 prompt 的消化节奏；历史 4800 条 prompt 已标记为已分析，不会重放"
echo "  - 验证：日常使用几天后，库大小应稳定在 KB 级，条目数 ~20-40"
echo "  - 稳定后把 userProfileAnalysisInterval 调回 25"
