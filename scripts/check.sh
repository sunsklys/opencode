#!/bin/bash
# ============================================================
# opencode 配置体检脚本
# 一键验证所有组件是否就绪
# ============================================================

cd "$(dirname "$0")/.."

PASS=0
FAIL=0
WARN=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN+1)); }

echo "╔══════════════════════════════════════════╗"
echo "║     opencode 配置体检                    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ---------- 1. 基础环境 ----------
echo "【1/11】基础环境"
NODE_VER=$(node --version 2>/dev/null || echo "")
if [ -n "$NODE_VER" ]; then
  NODE_MAJOR=$(echo "$NODE_VER" | sed 's/v//' | cut -d. -f1)
  if [ "$NODE_MAJOR" -ge 22 ]; then
    ok "Node.js $NODE_VER"
  else
    fail "Node.js $NODE_VER（需要 ≥22，运行 fnm install 22）"
  fi
else
  fail "Node.js 未安装"
fi

OC_VER=$(opencode --version 2>/dev/null || echo "")
if [ -n "$OC_VER" ]; then
  ok "opencode $OC_VER"
else
  fail "opencode 未安装（curl -fsSL https://opencode.ai/install | bash）"
fi
echo ""

# ---------- 2. 环境变量 ----------
echo "【2/11】环境变量"
[ -n "${VOLC_API_KEY:-}" ]     && ok "VOLC_API_KEY 已设置"      || fail "VOLC_API_KEY 未设置（make config）"
[ -n "${Z_AI_API_KEY:-}" ]     && ok "Z_AI_API_KEY 已设置"      || fail "Z_AI_API_KEY 未设置（make config）"
[ -n "${FEISHU_APP_SECRET:-}" ] && ok "FEISHU_APP_SECRET 已设置" || warn "FEISHU_APP_SECRET 未设置（飞书 CLI 需要）"
echo ""

# ---------- 3. npm 依赖 ----------
echo "【3/11】npm 依赖版本"
if npm ls --depth=0 2>&1 | grep -q "invalid"; then
  fail "node_modules 版本不一致（运行 make update 重装）"
else
  OMO_VER=$(node -p "require('./node_modules/oh-my-openagent/package.json').version" 2>/dev/null || echo "")
  PLG_VER=$(node -p "require('./node_modules/@opencode-ai/plugin/package.json').version" 2>/dev/null || echo "")
  [ -n "$OMO_VER" ] && ok "oh-my-openagent@$OMO_VER" || fail "oh-my-openagent 未安装"
  [ -n "$PLG_VER" ] && ok "@opencode-ai/plugin@$PLG_VER" || fail "@opencode-ai/plugin 未安装"
fi
echo ""

# ---------- 4. hephaestus GLM 补丁（opencode 缓存版本）----------
echo "【4/11】hephaestus GLM 补丁（opencode 缓存版本）"
# opencode 可能加载两处缓存：(1) 内置装的 node_modules/oh-my-opencode (2) plugin 字段装的 oh-my-openagent@latest/
# 两处都必须有补丁，因为 opencode 加载顺序不固定
CACHE_BUILTIN="$HOME/.cache/opencode/packages/node_modules/oh-my-opencode/dist/index.js"
CACHE_PLUGIN="$HOME/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js"
PATCHED_BUILTIN=false
PATCHED_PLUGIN=false
if [ -f "$CACHE_BUILTIN" ]; then
  grep -q "/glm/i" "$CACHE_BUILTIN" 2>/dev/null && PATCHED_BUILTIN=true
fi
if [ -f "$CACHE_PLUGIN" ]; then
  grep -q "/glm/i" "$CACHE_PLUGIN" 2>/dev/null && PATCHED_PLUGIN=true
fi
if [ ! -f "$CACHE_BUILTIN" ] && [ ! -f "$CACHE_PLUGIN" ]; then
  warn "opencode 缓存未创建 — 首次启动 opencode 后再检查"
elif $PATCHED_BUILTIN && $PATCHED_PLUGIN; then
  ok "两处 opencode 缓存均含 hephaestus GLM 补丁（builtin + plugin）"
elif $PATCHED_BUILTIN || $PATCHED_PLUGIN; then
  warn "仅一处缓存有补丁（builtin=$PATCHED_BUILTIN plugin=$PATCHED_PLUGIN）— 运行 make patch-sync 同步两处"
else
  fail "两处缓存均缺 GLM 补丁 — 运行 make patch-sync 同步"
fi
echo ""

# ---------- 5. opencode-mem ----------
echo "【5/11】opencode-mem 记忆插件"
if [ -L "node_modules/opencode-mem" ] && [ -d "node_modules/opencode-mem" ]; then
  MEM_VER=$(node -p "require('./node_modules/opencode-mem/package.json').version" 2>/dev/null || echo "?")
  ok "opencode-mem@$MEM_VER 软链就绪"
else
  fail "opencode-mem 软链未建立（make deps）"
fi

# 检查配置文件是否为智谱直连
if [ -f "opencode-mem.jsonc" ]; then
  if grep -q "glm-5-turbo" opencode-mem.jsonc && grep -q "env://Z_AI_API_KEY" opencode-mem.jsonc; then
    ok "opencode-mem.jsonc 已配置智谱直连"
  else
    warn "opencode-mem.jsonc 仍是默认 OpenAI 配置（make mem 生成智谱直连版）"
  fi
else
  warn "opencode-mem.jsonc 不存在（make mem 生成）"
fi
echo ""

# ---------- 6. 全局 MCP 依赖 ----------
echo "【6/11】全局 MCP 依赖"
command -v claude-mermaid >/dev/null 2>&1 && ok "claude-mermaid $(claude-mermaid --version 2>/dev/null || echo '已安装')" || fail "claude-mermaid 未安装（npm i -g claude-mermaid）"
command -v codegraph >/dev/null 2>&1 && ok "codegraph 已安装" || fail "codegraph 未安装（npm i -g @colbymchenry/codegraph）"
echo ""

# ---------- 7. 飞书 CLI ----------
echo "【7/11】飞书 CLI"
if command -v lark-cli >/dev/null 2>&1; then
  ok "lark-cli 已安装"
  if lark-cli auth status >/dev/null 2>&1; then
    ok "飞书凭证已配置"
  else
    warn "飞书凭证未配置（make feishu 或 bash setup-feishu-cli.sh）"
  fi
else
  warn "lark-cli 未安装（make feishu，可选）"
fi
echo ""

# ---------- 8. Web UI ----------
echo "【8/11】opencode-mem Web UI"
STATS=$(curl -s --max-time 3 http://127.0.0.1:4747/api/stats 2>/dev/null || echo "")
if echo "$STATS" | grep -q '"success":true'; then
  TOTAL=$(echo "$STATS" | node -pe "JSON.parse(require('fs').readFileSync(0)).data.total" 2>/dev/null || echo "?")
  ok "Web UI 运行中（http://127.0.0.1:4747，已记录 $TOTAL 条记忆）"
else
  warn "Web UI 未响应（启动 opencode 后自动运行）"
fi
echo ""
# ---------- 9. plugin @latest 漂移检测（opencode 缓存 vs 项目软链） ----------
echo "【9/11】plugin @latest 漂移检测（opencode 缓存 vs 项目软链）"
# opencode-mem 走 @latest 缓存路径加载（~/.cache/opencode/packages/）
# 项目软链 node_modules/opencode-mem -> 全局装版本
# 两者不一致时，opencode 启动会加载缓存版本（@latest 拉到的），而非软链版本
LINKED_VER=$(node -p "require('./node_modules/opencode-mem/package.json').version" 2>/dev/null || echo "?")
CACHE_DIR="$HOME/.cache/opencode/packages/opencode-mem@latest"
if [ -d "$CACHE_DIR" ]; then
  CACHED_VER=$(node -p "require('$CACHE_DIR/node_modules/opencode-mem/package.json').version" 2>/dev/null || echo "?")
  if [ "$LINKED_VER" = "$CACHED_VER" ]; then
    ok "opencode-mem 软链 $LINKED_VER = opencode 缓存 $CACHED_VER（@latest 一致）"
  else
    warn "opencode-mem 软链 $LINKED_VER ≠ opencode 缓存 $CACHED_VER（@latest 已漂移，opencode 启动会加载缓存版本而非软链版本）"
  fi
else
  warn "opencode-mem 未在 opencode 缓存中（首次启动 opencode 后才会缓存）"
fi
echo ""
# ---------- 10. lark skills SHA256 校验 ----------
echo "【10/11】lark skills SHA256 校验（供应链完整性）"
if [ ! -f "skills.lock" ]; then
  warn "skills.lock 不存在（运行 make skills-lock 生成）"
else
  SKILLS_DIR="$HOME/.agents/skills"
  if [ ! -d "$SKILLS_DIR" ]; then
    warn "~/.agents/skills 不存在（运行 make feishu 安装）"
  else
    MISMATCH=0
    MISSING=0
    TOTAL=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      TOTAL=$((TOTAL+1))
      HASH=$(echo "$line" | awk '{print $1}')
      REL_PATH=$(echo "$line" | awk '{print $2}')
      FULL_PATH="$SKILLS_DIR/$REL_PATH"
      if [ ! -f "$FULL_PATH" ]; then
        warn "SKILL 缺失：$REL_PATH"
        MISSING=$((MISSING+1))
      else
        ACTUAL=$(node -e "console.log(require('crypto').createHash('sha256').update(require('fs').readFileSync('$FULL_PATH')).digest('hex'))")
        if [ "$ACTUAL" != "$HASH" ]; then
          fail "SKILL 哈希不匹配：$REL_PATH（可能被篡改）"
          MISMATCH=$((MISMATCH+1))
        fi
      fi
    done < skills.lock
    if [ "$MISMATCH" -eq 0 ] && [ "$MISSING" -eq 0 ]; then
      ok "skills.lock $TOTAL 条全部匹配"
    fi
  fi
fi
echo ""
# ---------- 11. oh-my-openagent 内置 skill 软链健康 ----------
echo "【11/11】oh-my-openagent 内置 skill 软链健康"
# 扫描 ~/.agents/skills/ 下的软链，检查目标是否存在；并检测版本漂移
SKILLS_DIR="$HOME/.agents/skills"
if [ -d "$SKILLS_DIR" ]; then
  total_links=0
  broken_links=0
  for link in "$SKILLS_DIR"/*; do
    [ -L "$link" ] || continue
    total_links=$((total_links+1))
    if [ ! -e "$link" ]; then
      broken_links=$((broken_links+1))
    fi
  done
  if [ "$broken_links" -gt 0 ]; then
    fail "$broken_links/$total_links 个软链断开（make sync-skills 重建）"
  elif [ "$total_links" -eq 0 ]; then
    warn "~/.agents/skills/ 无软链（make sync-skills 创建，让 ulw-plan/git-master 等在 TUI 可见）"
  else
    ok "$total_links 个 skill 软链全部有效"
    # 版本漂移检测：软链指向 node_modules vs @latest 缓存
    ulw_link_target=$(readlink "$SKILLS_DIR/ulw-plan" 2>/dev/null || echo "")
    if echo "$ulw_link_target" | grep -q "/oh-my-openagent@latest/"; then
      warn "软链指向 @latest 缓存（版本会随上游漂移）— 运行 make sync-skills 重新绑定到锁定版本"
    fi
  fi
else
  warn "~/.agents/skills/ 不存在（make feishu 或 make sync-skills 创建）"
fi




# ---------- 汇总 ----------
echo "═══════════════════════════════════════════"
echo "  通过 $PASS ｜ 失败 $FAIL ｜ 警告 $WARN"
echo "═══════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "❌ 有 $FAIL 项失败，请按提示修复。"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo ""
  echo "⚠️  有 $WARN 项警告（可选组件未就绪）。"
  exit 0
else
  echo ""
  echo "🎉 全部就绪！"
  exit 0
fi
