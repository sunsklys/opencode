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
echo "【1/12】基础环境"
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
echo "【2/12】环境变量"
[ -n "${VOLC_API_KEY:-}" ]     && ok "VOLC_API_KEY 已设置"      || fail "VOLC_API_KEY 未设置（make config）"
[ -n "${Z_AI_API_KEY:-}" ]     && ok "Z_AI_API_KEY 已设置"      || fail "Z_AI_API_KEY 未设置（make config）"
[ -n "${FEISHU_APP_SECRET:-}" ] && ok "FEISHU_APP_SECRET 已设置" || warn "FEISHU_APP_SECRET 未设置（飞书 CLI 需要）"
echo ""

# ---------- 3. npm 依赖 ----------
echo "【3/12】npm 依赖版本"
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
echo "【4/12】hephaestus GLM 补丁（opencode 缓存版本）"
# opencode 可能加载两处缓存：(1) 内置装的 node_modules/oh-my-opencode (2) plugin 字段装的 oh-my-openagent@latest/
# 两处都必须有补丁，因为 opencode 加载顺序不固定
# 但 opencode 新版不再创建 builtin 兼容名 node_modules，故 builtin 父目录不存在时 skip
# skip 用目录级判断（非单文件级），避免 opencode 重建 builtin 但缺补丁时假绿
CACHE_BUILTIN="$HOME/.cache/opencode/packages/node_modules/oh-my-opencode/dist/index.js"
CACHE_PLUGIN="$HOME/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js"
BUILTIN_DIR="$HOME/.cache/opencode/packages/node_modules"
BUILTIN_SKIPPED=false
PATCHED_BUILTIN=false
PATCHED_PLUGIN=false
if [ ! -d "$BUILTIN_DIR" ]; then
  BUILTIN_SKIPPED=true
elif [ -f "$CACHE_BUILTIN" ]; then
  grep -q "/glm/i" "$CACHE_BUILTIN" 2>/dev/null && PATCHED_BUILTIN=true
fi
if [ -f "$CACHE_PLUGIN" ]; then
  grep -q "/glm/i" "$CACHE_PLUGIN" 2>/dev/null && PATCHED_PLUGIN=true
fi
if $BUILTIN_SKIPPED; then
  if [ ! -f "$CACHE_PLUGIN" ]; then
    warn "opencode 缓存未创建 — 首次启动 opencode 后再检查"
  elif $PATCHED_PLUGIN; then
    ok "plugin 缓存含 hephaestus GLM 补丁（builtin 路径未创建，已 skip）"
  else
    fail "plugin 缓存缺 GLM 补丁 — 运行 make patch-sync 同步"
  fi
else
  if [ ! -f "$CACHE_BUILTIN" ]; then
    fail "builtin 父目录存在但 oh-my-opencode/dist/index.js 缺失 — 运行 make update + make patch-sync"
  elif ! $PATCHED_BUILTIN && ! $PATCHED_PLUGIN; then
    fail "两处缓存均缺 GLM 补丁 — 运行 make patch-sync 同步"
  elif ! $PATCHED_BUILTIN; then
    fail "builtin 缓存缺 GLM 补丁 — 运行 make patch-sync 同步"
  elif ! $PATCHED_PLUGIN; then
    warn "仅 builtin 缓存有补丁（builtin=true plugin=false）— 运行 make patch-sync 同步两处"
  else
    ok "两处 opencode 缓存均含 hephaestus GLM 补丁（builtin + plugin）"
  fi
fi
echo ""

# ---------- 5. opencode-mem ----------
echo "【5/12】opencode-mem 记忆插件"
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
echo "【6/12】全局 MCP 依赖"
command -v claude-mermaid >/dev/null 2>&1 && ok "claude-mermaid $(claude-mermaid --version 2>/dev/null || echo '已安装')" || fail "claude-mermaid 未安装（npm i -g claude-mermaid）"
command -v codegraph >/dev/null 2>&1 && ok "codegraph 已安装" || fail "codegraph 未安装（npm i -g @colbymchenry/codegraph）"
command -v mcp-remote >/dev/null 2>&1 && ok "mcp-remote 已安装（notion MCP 直调）" || fail "mcp-remote 未安装（npm i -g mcp-remote，notion MCP 依赖）"
echo ""

# ---------- 7. 飞书 CLI ----------
echo "【7/12】飞书 CLI"
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
echo "【8/12】opencode-mem Web UI"
STATS=$(curl -s --max-time 3 http://127.0.0.1:4747/api/stats 2>/dev/null || echo "")
if echo "$STATS" | grep -q '"success":true'; then
  TOTAL=$(echo "$STATS" | node -pe "JSON.parse(require('fs').readFileSync(0)).data.total" 2>/dev/null || echo "?")
  ok "Web UI 运行中（http://127.0.0.1:4747，已记录 $TOTAL 条记忆）"
else
  warn "Web UI 未响应（启动 opencode 后自动运行）"
fi
echo ""
# ---------- 9. plugin @latest 漂移检测（opencode 缓存 vs 项目软链） ----------
echo "【9/12】plugin @latest 漂移检测（opencode 缓存 vs 项目软链）"
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
echo "【10/12】lark skills SHA256 校验（供应链完整性）"
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
echo "【11/12】oh-my-openagent 内置 skill 软链健康（含自愈）"
# 检测 17 个 OMO skill 软链是否齐全有效，缺失/断链时自动重建
# 软链作用：plugin 加载失败时作为 user-scope fallback（详见第 12 项根因检查）
SKILLS_DIR="$HOME/.agents/skills"
EXPECTED_OMO_SKILLS="ast-grep debugging frontend git-master init-deep lcx-contribute-bug-fix lcx-doctor lcx-report-bug lsp-setup programming refactor remove-ai-slops review-work start-work ultraresearch ulw-plan visual-qa"

omo_present=0
omo_missing=0
omo_broken=0
if [ -d "$SKILLS_DIR" ]; then
  for skill in $EXPECTED_OMO_SKILLS; do
    link="$SKILLS_DIR/$skill"
    if [ ! -L "$link" ]; then
      omo_missing=$((omo_missing+1))
    elif [ ! -e "$link" ]; then
      omo_broken=$((omo_broken+1))
    else
      omo_present=$((omo_present+1))
    fi
  done
else
  omo_missing=17
fi

if [ "$omo_missing" -eq 0 ] && [ "$omo_broken" -eq 0 ]; then
  ok "17 个 OMO skill 软链全部有效（ulw-plan/git-master/frontend 等）"
  # 版本漂移检测：软链指向 node_modules vs @latest 缓存
  ulw_link_target=$(readlink "$SKILLS_DIR/ulw-plan" 2>/dev/null || echo "")
  if echo "$ulw_link_target" | grep -q "/oh-my-openagent@latest/"; then
    warn "软链指向 @latest 缓存（版本会随上游漂移）— 运行 make sync-skills 重新绑定到锁定版本"
  fi
else
  # 自愈：缺失或断链时直接重建
  reason=""
  [ "$omo_missing" -gt 0 ] && reason="缺失 $omo_missing"
  [ "$omo_broken" -gt 0 ] && reason="$reason 断链 $omo_broken"
  warn "OMO skill 软链不完整（$reason）— 尝试自愈（sync-omo-skills.sh）"
  SYNC_OUTPUT=$(bash scripts/sync-omo-skills.sh 2>&1)
  SYNC_FAIL=$(echo "$SYNC_OUTPUT" | grep -E '^  失败: [1-9]' | head -1)
  if [ -n "$SYNC_FAIL" ]; then
    fail "自愈失败：sync-omo-skills.sh 报错"
  else
    # 复检
    omo_present_after=0
    omo_broken_after=0
    for skill in $EXPECTED_OMO_SKILLS; do
      link="$SKILLS_DIR/$skill"
      if [ -L "$link" ] && [ -e "$link" ]; then
        omo_present_after=$((omo_present_after+1))
      elif [ -L "$link" ] && [ ! -e "$link" ]; then
        omo_broken_after=$((omo_broken_after+1))
      fi
    done
    if [ "$omo_broken_after" -gt 0 ] || [ "$omo_present_after" -lt 17 ]; then
      fail "自愈后仍不完整（$omo_present_after/17 有效，$omo_broken_after 断链）— 项目 node_modules 可能损坏，运行 make update"
    else
      ok "已自愈：重建 $((17 - omo_present)) 个 OMO skill 软链（17/17 有效）"
    fi
  fi
fi
echo ""
# ---------- 12. opencode plugin 缓存健康（dist/skills 完整性，根因检查） ----------
echo "【12/12】opencode plugin 缓存健康（dist/skills 完整性）"
# 这是 ulw-plan/git-master 等 shared scope skill 的真实加载源
# OMO plugin 启动时通过 discoverSharedSkills() 扫描自己的 dist/skills
# 缓存缺失或不完整 → plugin 加载失败 → shared scope skill 整批消失（即使软链在）
EXPECTED_SKILLS="ast-grep debugging frontend git-master init-deep lcx-contribute-bug-fix lcx-doctor lcx-report-bug lsp-setup programming refactor remove-ai-slops review-work start-work ultraresearch ulw-plan visual-qa"

count_complete_skills() {
  local dir="$1"
  [ -d "$dir" ] || { echo 0; return; }
  local count=0
  for skill in $EXPECTED_SKILLS; do
    [ -f "$dir/$skill/SKILL.md" ] && count=$((count+1))
  done
  echo "$count"
}

PROJECT_SKILLS_DIR="node_modules/oh-my-openagent/dist/skills"
CACHE_BUILTIN_SKILLS="$HOME/.cache/opencode/packages/node_modules/oh-my-opencode/dist/skills"
CACHE_PLUGIN_SKILLS="$HOME/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/skills"

PROJECT_COUNT=$(count_complete_skills "$PROJECT_SKILLS_DIR")
BUILTIN_COUNT=$(count_complete_skills "$CACHE_BUILTIN_SKILLS")
PLUGIN_COUNT=$(count_complete_skills "$CACHE_PLUGIN_SKILLS")

if [ "$PROJECT_COUNT" -ne 17 ]; then
  fail "项目锁定 dist/skills 仅 $PROJECT_COUNT/17 skill 完整 — 运行 make update 重装"
elif [ ! -d "$BUILTIN_DIR" ]; then
  # builtin 父目录不存在 → skip builtin 检查（目录级判断，避免 opencode 重建时假绿）
  if [ "$PLUGIN_COUNT" -eq 17 ]; then
    ok "项目锁定 + plugin 缓存完整（17/17，builtin 路径未创建，已 skip）— plugin 加载链健康"
  elif [ "$PLUGIN_COUNT" -eq 0 ]; then
    warn "opencode 缓存未创建（项目锁定 OK，17/17）— 首次启动 opencode 后自动缓存"
  else
    fail "plugin 缓存不完整（$PLUGIN_COUNT/17）— 运行 make update + make patch-sync"
  fi
elif [ "$BUILTIN_COUNT" -eq 17 ] && [ "$PLUGIN_COUNT" -eq 17 ]; then
  ok "三处 dist/skills 完整（项目锁定 + builtin 缓存 + plugin 缓存，17×3）— plugin 加载链健康"
elif [ "$BUILTIN_COUNT" -ne 17 ]; then
  fail "builtin 缓存不完整（$BUILTIN_COUNT/17）— 运行 make update + make patch-sync"
else
  fail "plugin 缓存不完整（$PLUGIN_COUNT/17）— 运行 make update + make patch-sync"
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
