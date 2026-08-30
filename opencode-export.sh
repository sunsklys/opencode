#!/usr/bin/env bash
# opencode-export.sh - 导出 opencode 配置（不含敏感凭证）
# Usage: ./opencode-export.sh [输出目录，默认 ~/Desktop]
#
# 覆盖矩阵（2026-08-29 增强）：
#   git 内文件          → 走 git clone 恢复，本包兜底（无 git 场景）
#   .opencode/          → 含 dbx.md（生产 host，不入 git）+ glm-max.ts + instructions/lang-zh
#   ~/.agents/skills/   → 54 个用户 skill 本体（skills.lock 哈希可校验）
#   user-profiles.db    → 可选（交互询问），opencode-mem 用户画像
#   auth.json           → 可选（交互询问）
#   仍需手动：环境变量值（make config 交互输入）、opencode auth login、DBX app 连接、gh auth login

set -euo pipefail

# HEADLESS=1 无人值守模式（launchd 定时用）三硬约束：
#   ① auth.json 强制排除（不可参数开启——无人值守目录泄 key 是此防线要防的最坏情形）
#   ② 输出固定 ~/Backups/opencode/（非 iCloud 同步目录，防 API key/生产 host 上云；忽略位置参数）
#   ③ retention：仅保留最近 5 份，旧包自动清理
# 画像默认包含（非敏感小文件）；交互模式行为完全不变（含 DEST 支持）
HEADLESS="${HEADLESS:-0}"
if [ "$HEADLESS" = "1" ]; then
  OUT_DIR="$HOME/Backups/opencode"
else
  OUT_DIR="${1:-$HOME/Desktop}"
fi
# DEST 绝对化：打包前 cd "$TMP" 后，相对路径 FULL_PATH 会解析到 TMP 下不存在目录（tar 必败）
case "$OUT_DIR" in
  /*) ;;  # 已绝对路径（HEADLESS 默认与显式绝对 DEST）
  *)
    if [ -d "$OUT_DIR" ]; then
      OUT_DIR="$(cd -- "$OUT_DIR" && pwd)"
    else
      OUT_DIR="$PWD/$OUT_DIR"
    fi
    ;;
esac
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE="opencode-config-${TIMESTAMP}.tar.gz"
# 守卫：以 - 开头的目录名会被 tar 解析为选项（GNU tar 理论可注入），强制 ./ 前缀
case "$OUT_DIR" in
  -*) OUT_DIR="./$OUT_DIR" ;;
esac
# 输出目录无条件兜底创建（tar -f 不建目录；HEADLESS 与交互 DEST=新路径 场景同护）
mkdir -p "$OUT_DIR"
FULL_PATH="${OUT_DIR}/${ARCHIVE}"

CONFIG_DIR="$HOME/.config/opencode"
DATA_DIR="$HOME/.local/share/opencode"
SKILLS_DIR="$HOME/.agents/skills"
MEM_DATA_DIR="$HOME/.opencode-mem/data"

if [[ ! -d "$CONFIG_DIR" ]]; then
  echo "❌ $CONFIG_DIR not found" >&2
  exit 1
fi

# 创建临时工作目录
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# ============ 1. 配置仓库文件（git 内文件的无 git 兜底快照） ============
mkdir -p "$TMP/config/opencode"
cp "$CONFIG_DIR"/*.json "$TMP/config/opencode/" 2>/dev/null || true
cp "$CONFIG_DIR"/*.jsonc "$TMP/config/opencode/" 2>/dev/null || true
cp "$CONFIG_DIR"/*.sh "$TMP/config/opencode/" 2>/dev/null || true
cp "$CONFIG_DIR"/.gitignore "$TMP/config/opencode/" 2>/dev/null || true
# package-lock.json 一起带上保证依赖一致
[[ -f "$CONFIG_DIR/package-lock.json" ]] && cp "$CONFIG_DIR/package-lock.json" "$TMP/config/opencode/"
# 完整目录结构（Makefile / scripts / 模板 / 文档）一起带上，让 make install 可用
cp "$CONFIG_DIR/Makefile" "$TMP/config/opencode/" 2>/dev/null || true
cp "$CONFIG_DIR"/*.template "$TMP/config/opencode/" 2>/dev/null || true
[[ -f "$CONFIG_DIR/skills.lock" ]] && cp "$CONFIG_DIR/skills.lock" "$TMP/config/opencode/"
[[ -d "$CONFIG_DIR/scripts" ]] && cp -r "$CONFIG_DIR/scripts" "$TMP/config/opencode/" 2>/dev/null || true
[[ -d "$CONFIG_DIR/docs" ]] && cp -r "$CONFIG_DIR/docs" "$TMP/config/opencode/" 2>/dev/null || true

# ============ 2. .opencode/ 目录（含不入 git 的 dbx.md + 自定义 plugin） ============
# dbx.md（生产 host）、plugin/glm-max.ts、instructions.md、lang-zh.md
# 排除 node_modules / package.json（本仓库 install 时生成）
if [[ -d "$CONFIG_DIR/.opencode" ]]; then
  rsync -a --exclude 'node_modules' --exclude 'package.json' --exclude 'package-lock.json' \
    "$CONFIG_DIR/.opencode/" "$TMP/config/opencode/.opencode/" 2>/dev/null || \
    cp -r "$CONFIG_DIR/.opencode" "$TMP/config/opencode/" 2>/dev/null || true
fi

# ============ 3. 用户 skills 本体（~/.agents/skills，54 个，含自定义 skill） ============
# lark 系列可由 setup-feishu-cli.sh 重装，但 ast-grep/frontend/debugging/hooloo 等自定义
# skill 唯一副本在此目录；skills.lock（已随 config 打包）可校验哈希完整性
if [[ -d "$SKILLS_DIR" ]]; then
  mkdir -p "$TMP/agents"
  rsync -a --exclude='.git' --exclude='.DS_Store' --exclude='*.log' \
    "$SKILLS_DIR/" "$TMP/agents/skills/" 2>/dev/null || \
    cp -r "$SKILLS_DIR" "$TMP/agents/skills"
  echo "ℹ️  已包含 ~/.agents/skills（$(find "$TMP/agents/skills" -name SKILL.md | wc -l | tr -d ' ') 个 SKILL.md）"
fi

# ============ 4. 可选项：auth.json（HEADLESS 强制排除——不可参数开启的红线） ============
if [ "$HEADLESS" = "1" ]; then
  echo "ℹ️  HEADLESS 模式：auth.json 强制排除（无人值守目录不落 API key）"
else
  echo ""
  read -p "是否包含 auth.json (含 API key，可在新机器免登录)? [y/N] " include_auth
  if [[ "$include_auth" =~ ^[yY]$ ]]; then
    mkdir -p "$TMP/data/opencode"
    cp "$DATA_DIR/auth.json" "$TMP/data/opencode/" 2>/dev/null || true
    echo "⚠️  已包含 auth.json - 注意保护此压缩包"
  else
    echo "ℹ️  未包含 auth.json - 新机器需重新 'opencode auth login'"
  fi
fi

# ============ 5. 可选项：opencode-mem 用户画像 ============
# user-profiles.db 三件套约 6MB；向量库 1.5GB 过大不入包（记忆条目可重新积累）
if [[ -f "$MEM_DATA_DIR/user-profiles.db" ]]; then
  if [ "$HEADLESS" = "1" ]; then
    include_profile=""
  else
  read -p "是否包含 opencode-mem 用户画像 user-profiles.db (~6MB，跳过则新机从零学习)? [Y/n] " include_profile
  if [[ ! "$include_profile" =~ ^[nN]$ ]]; then
    mkdir -p "$TMP/opencode-mem/data"
    cp "$MEM_DATA_DIR"/user-profiles.db "$TMP/opencode-mem/data/" 2>/dev/null || true
    [[ -f "$MEM_DATA_DIR/user-profiles.db-wal" ]] && cp "$MEM_DATA_DIR"/user-profiles.db-wal "$TMP/opencode-mem/data/" || true
    [[ -f "$MEM_DATA_DIR/user-profiles.db-shm" ]] && cp "$MEM_DATA_DIR"/user-profiles.db-shm "$TMP/opencode-mem/data/" || true
    echo "ℹ️  已包含用户画像（含 wal/shm）"
  else
    echo "ℹ️  未包含用户画像 - 新机 profile 从零积累"
  fi
  fi
fi

# ============ 6. 恢复说明 ============
cat > "$TMP/README.md" <<'EOF'
# opencode 配置恢复指南

## 前置依赖（在新机器）

```bash
# 1. 安装 Node.js (推荐 fnm 管理)
curl -fsSL https://fnm.vercel.app/install | bash
fnm install 22

# 2. 安装 opencode
curl -fsSL https://opencode.ai/install | bash
# 或: npm i -g opencode-ai
```

## 恢复配置

```bash
# 1. 解压到正确位置
tar -xzf opencode-config-*.tar.gz
mkdir -p ~/.config/opencode ~/.local/share/opencode ~/.agents
cp -r config/opencode/* ~/.config/opencode/
[[ -d data/opencode ]] && cp -r data/opencode/* ~/.local/share/opencode/

# 2. 恢复用户 skills（54 个，含自定义 skill 唯一副本）
[[ -d agents/skills ]] && cp -r agents/skills ~/.agents/

# 3. 恢复 opencode-mem 用户画像（若包含）
if [[ -d opencode-mem/data ]]; then
  mkdir -p ~/.opencode-mem/data
  cp opencode-mem/data/user-profiles.db* ~/.opencode-mem/data/
fi

# 4. 一键安装（npm 依赖 + opencode-mem 软链 + OMO skill 软链 + 记忆/OMO 配置生成）
cd ~/.config/opencode
make install

# 5. 交互式补环境变量（Z_AI_API_KEY / FEISHU_APP_SECRET 等，值需自行准备）
make config

# 6. 若未带 auth.json，重新登录
opencode auth login zhipuai-coding-plan

# 7. 体检（应全绿）
make check
```

## 仍需手动恢复（不在包内）

| 项 | 操作 |
| --- | --- |
| 环境变量值 | `make config` 交互输入（key 值从密码管理器/旧机 shell 历史取） |
| opencode 登录 | `opencode auth login zhipuai-coding-plan`（或用包内 auth.json 免登录） |
| DBX 桌面 app 连接 | 在 DBX app 内重建 8 条连接（字典见 `~/.config/opencode/.opencode/dbx.md`） |
| gh CLI | `gh auth login`（GitHub 自动化用） |
| 记忆向量库 | 不迁移（1.5GB），新机自动重新积累；历史会话 opencode.db 不迁移 |

## 包含文件

核心文件：
- opencode.json / tui.json / Makefile / scripts/ / docs/ - 配置与编排
- package.json + package-lock.json - 依赖锁
- *.template - mem / OMO 配置模板（make install 自动生成生成物）
- .opencode/ - dbx.md（生产 host，勿外传）+ glm-max.ts + instructions/lang-zh
- agents/skills/ - 54 个用户 skill（skills.lock 哈希校验）
- opencode-mem/data/user-profiles.db* - 用户画像（可选）
EOF

# ============ 7. 打包 ============
cd "$TMP"
tar -cz -f "$FULL_PATH" .

# 体积骤降告警：新包比前一份骤降超 40% 几乎必然意味着打包内容悄悄缺失（skills 没打进/内容丢失）
PREV_PKG=$(ls "$OUT_DIR"/opencode-config-*.tar.gz 2>/dev/null | sort | grep -v "$(basename "$FULL_PATH")" | tail -1 || true)   # || true：目录仅有新包时 grep -v 空输出 exit 1，pipefail 下会杀脚本（首次导出/新目录必经）
if [ -n "$PREV_PKG" ]; then
  NEW_BYTES=$(stat -f%z "$FULL_PATH" 2>/dev/null || echo 0)
  PREV_BYTES=$(stat -f%z "$PREV_PKG" 2>/dev/null || echo 0)
  if [ "$PREV_BYTES" -gt 0 ] && [ "$NEW_BYTES" -lt $((PREV_BYTES * 60 / 100)) ]; then
    echo "⚠️  包体积骤降 $(( (PREV_BYTES - NEW_BYTES) * 100 / PREV_BYTES ))%（前 $((PREV_BYTES/1024/1024))MB → 现 $((NEW_BYTES/1024/1024))MB）— 检查打包内容是否缺失"
  fi
fi

echo ""
echo "✅ 导出成功"
echo "📦 $FULL_PATH"
echo "📏 $(du -sh "$FULL_PATH" | cut -f1)"
if [ "$HEADLESS" = "1" ]; then
  # [硬断言] HEADLESS 包内 auth.json 必须零存在（三硬约束的机器自验证；违者删包退出）
  if tar -tzf "$FULL_PATH" | grep -q 'auth\.json'; then
    echo "❌ auth.json 泄入包内（三硬约束被破坏）— 已删除本包" >&2
    rm -f "$FULL_PATH"
    exit 1
  fi
  # retention：仅保留最近 5 份（launchd 周跑防无限堆积）
  # 按文件名排序（自带 %Y%m%d-%H%M%S 时间戳，字典序=时间序；mtime 会被 cp/touch 扰动不可靠）
  ls "$OUT_DIR"/opencode-config-*.tar.gz 2>/dev/null | sort -r | tail -n +6 | while IFS= read -r old_pkg; do
    rm -f "$old_pkg" && echo "🗑️  retention 清理: $(basename "$old_pkg")"
  done
  echo "ℹ️  HEADLESS 完成于 $OUT_DIR（保留最近 5 份）"
fi
echo "⚠️  包内含 dbx.md（生产 host）— 勿上传公开位置"
echo ""
echo "📋 包含文件:"
tar -tzf "$FULL_PATH" | sort
