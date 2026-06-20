#!/bin/bash
# ============================================================
# 环境变量配置脚本（交互式）
# 配置 VOLC_API_KEY / Z_AI_API_KEY / FEISHU_APP_SECRET
# 幂等写入 ~/.zshrc + launchctl setenv 同步 GUI 应用
# ============================================================
set -euo pipefail

ZSHRC="${HOME}/.zshrc"
MARKER="# opencode 环境变量（由 scripts/setup-env.sh 自动生成）"

# --- 确保有 .zshrc ---
touch "$ZSHRC"

echo "=== 环境变量配置 ==="
echo "将为以下 3 个变量配置 ~/.zshrc + launchctl："
echo "  - VOLC_API_KEY      (火山引擎 Ark)"
echo "  - Z_AI_API_KEY      (智谱 BigModel)"
echo "  - FEISHU_APP_SECRET (飞书开放平台)"
echo ""

# --- 逐个收集 ---
collect_var() {
  local var_name="$1"
  local prompt_msg="$2"
  local current_val="${!var_name:-}"
  local input_val

  if [ -n "$current_val" ]; then
    echo "当前 $var_name 已设置（值: ${current_val:0:8}...${current_val: -4}）"
    read -rp "是否更新？[y/N] " yn </dev/tty
    case "$yn" in
      [Yy]*) ;;
      *) eval "export _NEW_${var_name}=\"\$current_val\""; return ;;
    esac
  fi

  read -rp "请输入 ${prompt_msg}：" input_val </dev/tty
  if [ -z "$input_val" ]; then
    echo "⚠ 跳过 $var_name（未输入）"
    eval "export _NEW_${var_name}=\"\""
    return
  fi
  eval "export _NEW_${var_name}=\"\$input_val\""
}

collect_var "VOLC_API_KEY"      "火山引擎 API Key（ark-...）"
collect_var "Z_AI_API_KEY"      "智谱 API Key（xxx.xxxxxxxx）"
collect_var "FEISHU_APP_SECRET" "飞书 App Secret"

VOLC_NEW="${_NEW_VOLC_API_KEY:-${VOLC_API_KEY:-}}"
ZAI_NEW="${_NEW_Z_AI_API_KEY:-${Z_AI_API_KEY:-}}"
FEISHU_NEW="${_NEW_FEISHU_APP_SECRET:-${FEISHU_APP_SECRET:-}}"

# --- 移除旧块（幂等：避免重复追加）---
if grep -qF "$MARKER" "$ZSHRC"; then
  # 用 awk 删除从 MARKER 到下一个空行+非注释行的块
  # 简单方案：删除 MARKER 行到 "EOF 标记结束行" 之间所有内容
  python3 - "$ZSHRC" "$MARKER" <<'PYEOF'
import sys, re
path, marker = sys.argv[1], sys.argv[2]
with open(path, 'r') as f:
    content = f.read()
# 删除从 marker 行开始，到 "# === end opencode env ===" 的整块
pattern = re.compile(
    re.escape(marker) + r'.*?# === end opencode env ===\n?',
    re.DOTALL
)
new_content = pattern.sub('', content)
with open(path, 'w') as f:
    f.write(new_content)
PYEOF
  echo "（已清理旧的环境变量块）"
fi

# --- 追加新块 ---
{
  echo ""
  echo "$MARKER"
  [ -n "$VOLC_NEW" ]    && echo "export VOLC_API_KEY='$VOLC_NEW'"
  [ -n "$ZAI_NEW" ]     && echo "export Z_AI_API_KEY='$ZAI_NEW'"
  [ -n "$FEISHU_NEW" ]  && echo "export FEISHU_APP_SECRET='$FEISHU_NEW'"
  # 同步给 macOS GUI 应用（IDE / Dock 启动的 opencode 也能继承）
  [ -n "$VOLC_NEW" ]    && echo "launchctl setenv VOLC_API_KEY \"\$VOLC_API_KEY\" 2>/dev/null"
  [ -n "$ZAI_NEW" ]     && echo "launchctl setenv Z_AI_API_KEY \"\$Z_AI_API_KEY\" 2>/dev/null"
  [ -n "$FEISHU_NEW" ]  && echo "launchctl setenv FEISHU_APP_SECRET \"\$FEISHU_APP_SECRET\" 2>/dev/null"
  echo "# === end opencode env ==="
} >> "$ZSHRC"

# --- 立即生效（当前进程 + launchctl）---
[ -n "$VOLC_NEW" ]   && { export VOLC_API_KEY="$VOLC_NEW";     launchctl setenv VOLC_API_KEY "$VOLC_NEW" 2>/dev/null || true; }
[ -n "$ZAI_NEW" ]    && { export Z_AI_API_KEY="$ZAI_NEW";       launchctl setenv Z_AI_API_KEY "$ZAI_NEW" 2>/dev/null || true; }
[ -n "$FEISHU_NEW" ] && { export FEISHU_APP_SECRET="$FEISHU_NEW"; launchctl setenv FEISHU_APP_SECRET "$FEISHU_NEW" 2>/dev/null || true; }

echo ""
echo "✅ 环境变量已写入 ~/.zshrc 并 launchctl setenv"
echo ""
echo "生效方式："
echo "  source ~/.zshrc   （当前终端）"
echo "  重开终端 / 重启 IDE（GUI 应用）"
echo ""
echo "获取 API key："
echo "  VOLC:      https://console.volcengine.com/ark"
echo "  Z_AI:      https://www.bigmodel.cn/usercenter/apikeys"
echo "  FEISHU:    https://open.feishu.cn/app/cli_aaa482d9dcb8dbcd"
