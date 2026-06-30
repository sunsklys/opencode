#!/bin/bash
# ============================================================
# sync-omo-skills.sh
# 把 oh-my-openagent 的 dist/skills 软链到 ~/.agents/skills/
#
# 背景（v4.12.1 源码验证后的修正描述）：
#   OMO plugin 启动时通过 discoverSharedSkills() 扫描自己的 dist/skills，
#   把 ulw-plan/git-master 等 18 个 skill 以 shared scope 注入 <available_skills>。
#   即：plugin 加载正常时，这些 skill 不需要软链也会出现在 TUI 列表。
#
#   本脚本建立的软链是 user-scope fallback —— 当 plugin 因 #latest 缓存漂移、
#   补丁冲突、缓存损坏等原因加载失败时，让 SKILL.md 内容至少可被 opencode TUI
#   通过 discoverGlobalAgentsSkills() 扫描到（注：仅 SKILL.md 可读，plugin runtime
#   的 slash command 注册仍不可用，需修根因：make update + make patch-sync）。
#
#   make check 第 12 项会检测 plugin 缓存的 dist/skills 完整性（真正的根因指标），
#   第 11 项会自动调用本脚本自愈软链。
#
# 优先用项目锁定版本（node_modules/oh-my-openagent），fallback 到 #latest 缓存。
# 幂等：已存在的非软链目录不覆盖；断链自动清理重建。
# ============================================================

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCKED_SOURCE="$PROJECT_DIR/node_modules/oh-my-openagent/dist/skills"
CACHE_SOURCE="$HOME/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/skills"
TARGET_DIR="$HOME/.agents/skills"

# 选择源（优先锁定版本）
if [ -d "$LOCKED_SOURCE" ]; then
  SOURCE_DIR="$LOCKED_SOURCE"
  SOURCE_TAG="locked"
elif [ -d "$CACHE_SOURCE" ]; then
  SOURCE_DIR="$CACHE_SOURCE"
  SOURCE_TAG="@latest-cache"
else
  echo "❌ oh-my-openagent skills 目录都不存在："
  echo "   - $LOCKED_SOURCE"
  echo "   - $CACHE_SOURCE"
  echo "   先运行：make deps"
  exit 1
fi

mkdir -p "$TARGET_DIR"

synced=0
skipped_exists=0
skipped_broken=0
conflicts=0
failed=0

for skill_dir in "$SOURCE_DIR"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")

  # 必须有 SKILL.md 才算有效 skill
  if [ ! -f "$skill_dir/SKILL.md" ]; then
    continue
  fi

  link="$TARGET_DIR/$skill_name"

  # 已存在且是有效软链 → 跳过（含软链指向同源的快速路径）
  if [ -L "$link" ] && [ -e "$link" ]; then
    skipped_exists=$((skipped_exists+1))
    continue
  fi

  # 断链 → 清理后重建
  if [ -L "$link" ] && [ ! -e "$link" ]; then
    rm "$link"
    skipped_broken=$((skipped_broken+1))
  fi

  # 已存在真实文件/目录（非软链）→ 不覆盖，记冲突
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "⚠️  跳过 $skill_name：$link 已存在且不是软链（用户自有文件）"
    conflicts=$((conflicts+1))
    continue
  fi

  # 创建软链（绝对路径，避免相对路径漂移）
  if ln -s "$skill_dir" "$link" 2>/dev/null; then
    echo "✓ 链接 $skill_name → $skill_dir"
    synced=$((synced+1))
  else
    echo "❌ 失败 $skill_name：ln -s 错误"
    failed=$((failed+1))
  fi
done

echo ""
echo "═══════════════════════════════════════════"
echo "  源: $SOURCE_DIR ($SOURCE_TAG)"
echo "  新建软链: $synced"
echo "  跳过（已存在有效软链）: $skipped_exists"
echo "  跳过（清理断链后重建）: $skipped_broken"
echo "  冲突（用户自有文件）: $conflicts"
echo "  失败: $failed"
echo "═══════════════════════════════════════════"

# 失败则非零退出
if [ "$failed" -gt 0 ]; then
  exit 1
fi

exit 0
