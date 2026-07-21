#!/bin/bash
# ============================================================
# opencode 配置体检脚本
# 一键验证所有组件是否就绪
# ============================================================

# 确保 UTF-8 locale（make 透传调用时 LANG=C.UTF-8 会导致中文输出乱码，
# 强制设为 en_US.UTF-8；系统不支持时 locale 命令会告警，不影响逻辑）
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

cd "$(dirname "$0")/.."

# 分层计数器：Critical 项 fail → FAIL（阻断 exit code）；Warning 项 fail → WFAIL（不阻断，仅提示）
PASS=0
FAIL=0       # critical-tier fail（必须修复才能使用 opencode）
WFAIL=0      # warning-tier fail（可选功能未就绪，不影响核心使用）
WARN=0       # warn 提示（不阻断）

ok()    { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }         # critical fail
wfail() { echo "  ❌ $1"; WFAIL=$((WFAIL+1)); }       # warning fail
warn()  { echo "  ⚠️  $1"; WARN=$((WARN+1)); }

echo "╔══════════════════════════════════════════╗"
echo "║     opencode 配置体检                    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ---------- 1. [Critical] 基础环境 + 环境变量 ----------
echo "【1/13·Critical】基础环境 + 环境变量"
# --- Node.js 与 opencode 安装 ---
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
# --- 环境变量 ---
[ -n "${VOLC_API_KEY:-}" ]     && ok "VOLC_API_KEY 已设置"      || fail "VOLC_API_KEY 未设置（make config）"
[ -n "${Z_AI_API_KEY:-}" ]     && ok "Z_AI_API_KEY 已设置"      || fail "Z_AI_API_KEY 未设置（make config）"
[ -n "${FEISHU_APP_SECRET:-}" ] && ok "FEISHU_APP_SECRET 已设置" || warn "FEISHU_APP_SECRET 未设置（飞书 CLI 需要）"
echo ""

# ---------- 2. [Critical] npm 依赖 ----------
echo "【2/13·Critical】npm 依赖版本"
 
if npm ls --depth=0 2>&1 | grep -q "invalid"; then
  fail "node_modules 版本不一致（运行 make update 重装）"
else
  OMO_VER=$(node -p "require('./node_modules/oh-my-openagent/package.json').version" 2>/dev/null || echo "")
  PLG_VER=$(node -p "require('./node_modules/@opencode-ai/plugin/package.json').version" 2>/dev/null || echo "")
  [ -n "$OMO_VER" ] && ok "oh-my-openagent@$OMO_VER" || fail "oh-my-openagent 未安装"
  [ -n "$PLG_VER" ] && ok "@opencode-ai/plugin@$PLG_VER" || fail "@opencode-ai/plugin 未安装"
fi
echo ""

# ---------- 3. [Warning] opencode-mem 记忆插件 ----------
echo "【3/13·Warning】opencode-mem 记忆插件"
 
if [ -L "node_modules/opencode-mem" ] && [ -d "node_modules/opencode-mem" ]; then
  MEM_VER=$(node -p "require('./node_modules/opencode-mem/package.json').version" 2>/dev/null || echo "?")
  ok "opencode-mem@$MEM_VER 软链就绪"
else
  wfail "opencode-mem 软链未建立（make deps）"
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

# ---------- 4. [Warning] 全局 MCP 依赖 ----------
echo "【4/13·Warning】全局 MCP 依赖"
 
command -v claude-mermaid >/dev/null 2>&1 && ok "claude-mermaid $(claude-mermaid --version 2>/dev/null || echo '已安装')" || wfail "claude-mermaid 未安装（npm i -g claude-mermaid）"
command -v codegraph >/dev/null 2>&1 && ok "codegraph 已安装" || wfail "codegraph 未安装（npm i -g @colbymchenry/codegraph）"
command -v mcp-remote >/dev/null 2>&1 && ok "mcp-remote 已安装（notion MCP 直调）" || wfail "mcp-remote 未安装（npm i -g mcp-remote，notion MCP 依赖）"
echo ""

# ---------- 5. [Warning] 飞书 CLI ----------
echo "【5/13·Warning】飞书 CLI"
 
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

# ---------- 6. [Warning] Web UI ----------
echo "【6/13·Warning】opencode-mem Web UI"
 
STATS=$(curl -s --max-time 3 http://127.0.0.1:4747/api/stats 2>/dev/null || echo "")
if echo "$STATS" | grep -q '"success":true'; then
  TOTAL=$(echo "$STATS" | node -pe "JSON.parse(require('fs').readFileSync(0)).data.total" 2>/dev/null || echo "?")
  ok "Web UI 运行中（http://127.0.0.1:4747，已记录 $TOTAL 条记忆）"
else
  warn "Web UI 未响应（启动 opencode 后自动运行）"
fi
echo ""
# ---------- 7. [Warning] plugin @latest 漂移检测（opencode 缓存 vs 项目软链） ----------
echo "【7/13·Warning】plugin @latest 漂移检测（opencode 缓存 vs 项目软链）"
 
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
    warn "opencode-mem 软链 $LINKED_VER ≠ opencode 缓存 $CACHED_VER（@latest 已漂移，opencode 启动会加载缓存版本而非软链版本——运行 make update 后会自动清缓存重拉）"
  fi
else
  warn "opencode-mem 未在 opencode 缓存中（首次启动 opencode 后才会缓存）"
fi
echo ""
# ---------- 8. [Warning] lark skills SHA256 校验 ----------
echo "【8/13·Warning】skills SHA256 校验（供应链完整性，lark + OMO）"
 
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
        ACTUAL=$(shasum -a 256 "$FULL_PATH" | awk '{print $1}')
        if [ "$ACTUAL" != "$HASH" ]; then
          wfail "SKILL 哈希不匹配：$REL_PATH（可能被篡改）"
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
# ---------- 9. [Warning] oh-my-openagent 内置 skill 软链健康 ----------
echo "【9/13·Warning】oh-my-openagent 内置 skill 软链健康（含自愈）"
 
# 动态检测 OMO skill 软链是否齐全有效（数量随 OMO 版本变化），缺失/断链时自动重建
# 软链作用：plugin 加载失败时作为 user-scope fallback（详见 plugin 缓存健康检查项）
SKILLS_DIR="$HOME/.agents/skills"
# 动态从项目锁定 dist/skills 读取（与 §10 同策略，自适配 OMO 任意版本 skill 集合）
PROJECT_SKILLS_DIR="node_modules/oh-my-openagent/dist/skills"
EXPECTED_OMO_SKILLS=$(ls -1 "$PROJECT_SKILLS_DIR" 2>/dev/null | sort -u)
OMO_TOTAL=$(echo "$EXPECTED_OMO_SKILLS" | grep -c .)

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
  omo_missing=$OMO_TOTAL
fi

if [ "$OMO_TOTAL" -eq 0 ]; then
  wfail "无法读取项目锁定 dist/skills（node_modules/oh-my-openagent 缺失或损坏）— 运行 make install / make update"
elif [ "$omo_missing" -eq 0 ] && [ "$omo_broken" -eq 0 ]; then
  ok "$OMO_TOTAL 个 OMO skill 软链全部有效（ulw-plan/git-master/frontend 等）"
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
    wfail "自愈失败：sync-omo-skills.sh 报错"
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
    if [ "$omo_broken_after" -gt 0 ] || [ "$omo_present_after" -lt "$OMO_TOTAL" ]; then
      wfail "自愈后仍不完整（$omo_present_after/$OMO_TOTAL 有效，$omo_broken_after 断链）— 项目 node_modules 可能损坏，运行 make update"
    else
      ok "已自愈：重建 $(($OMO_TOTAL - omo_present)) 个 OMO skill 软链（$OMO_TOTAL/$OMO_TOTAL 有效）"
    fi
  fi
fi
echo ""
# ---------- 10. [Critical] opencode plugin 缓存健康（dist/skills 完整性，根因检查） ----------
echo "【10/13·Critical】opencode plugin 缓存健康（dist/skills 完整性）"
 
# 这是 ulw-plan/git-master 等 shared scope skill 的真实加载源
# OMO plugin 启动时通过 discoverSharedSkills() 扫描自己的 dist/skills
# 缓存缺失或不完整 → plugin 加载失败 → shared scope skill 整批消失（即使软链在）
# 动态策略：以项目锁定 dist/skills 为基准（OMO 当前版本实际发布的 skill 集合），
# 校验“项目锁 = 缓存 = 软链 user-scope”三方一致，自适配 OMO 任意版本。
# 例：4.18.2 = 20 skills，4.19.0 = 16 skills（上游 v4.19.0 breaking change：ultraresearch→ulw-research 重命名，lcx-* 移到 codex edition）。
PROJECT_SKILLS_DIR="node_modules/oh-my-openagent/dist/skills"
EXPECTED_SKILLS=$(ls -1 "$PROJECT_SKILLS_DIR" 2>/dev/null | sort -u)
PROJECT_TOTAL=$(echo "$EXPECTED_SKILLS" | grep -c .)

count_complete_skills() {
  local dir="$1"
  [ -d "$dir" ] || { echo 0; return; }
  local count=0
  for skill in $EXPECTED_SKILLS; do
    [ -f "$dir/$skill/SKILL.md" ] && count=$((count+1))
  done
  echo "$count"
}

# 独立定义 builtin 根目录，避免跨项复用变量导致的调试 silent skip 假绿
BUILTIN_ROOT_DIR_12="$HOME/.cache/opencode/packages/node_modules"
CACHE_BUILTIN_SKILLS="$BUILTIN_ROOT_DIR_12/oh-my-opencode/dist/skills"
CACHE_PLUGIN_SKILLS="$HOME/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/skills"

PROJECT_COUNT=$(count_complete_skills "$PROJECT_SKILLS_DIR")
BUILTIN_COUNT=$(count_complete_skills "$CACHE_BUILTIN_SKILLS")
PLUGIN_COUNT=$(count_complete_skills "$CACHE_PLUGIN_SKILLS")

if [ "$PROJECT_TOTAL" -eq 0 ]; then
  fail "无法读取项目锁定 dist/skills（node_modules/oh-my-openagent 缺失或损坏）— 运行 make install / make update"
elif [ "$PROJECT_COUNT" -ne "$PROJECT_TOTAL" ]; then
  fail "项目锁定 dist/skills 损坏（$PROJECT_COUNT/$PROJECT_TOTAL 有 SKILL.md）— 运行 make update 重装"
elif [ ! -d "$CACHE_BUILTIN_SKILLS" ]; then
  # opencode 1.17.11+ 不再 builtin 装 oh-my-opencode 主包（只装 platform binary），路径不存在是正常状态
  if [ "$PLUGIN_COUNT" -eq "$PROJECT_TOTAL" ]; then
    ok "项目锁定 + plugin 缓存完整（$PROJECT_TOTAL/$PROJECT_TOTAL，builtin 未装载，已 skip）— plugin 加载链健康"
  elif [ "$PLUGIN_COUNT" -eq 0 ]; then
    warn "opencode 缓存未创建（项目锁定 OK，$PROJECT_TOTAL/$PROJECT_TOTAL）— 首次启动 opencode 后自动缓存"
  else
    fail "plugin 缓存不完整（$PLUGIN_COUNT/$PROJECT_TOTAL）— 运行 make update"
  fi
elif [ "$BUILTIN_COUNT" -eq "$PROJECT_TOTAL" ] && [ "$PLUGIN_COUNT" -eq "$PROJECT_TOTAL" ]; then
  ok "三处 dist/skills 完整（项目锁定 + builtin 缓存 + plugin 缓存，${PROJECT_TOTAL}×3）— plugin 加载链健康"
elif [ "$BUILTIN_COUNT" -ne "$PROJECT_TOTAL" ]; then
  fail "builtin 缓存不完整（$BUILTIN_COUNT/$PROJECT_TOTAL）— 运行 make update"
else
  fail "plugin 缓存不完整（$PLUGIN_COUNT/$PROJECT_TOTAL）— 运行 make update"
fi

# ---------- 11. [Critical] OMO + opencode 关键字段验证 ----------
echo "【11/13·Critical】OMO + opencode 关键字段配置验证"
 
# 用 node 提取字段避免 jq 依赖
OMO_FIELDS=$(node -e "const c=require('./oh-my-openagent.json');console.log(JSON.stringify({monitor:c.monitor?.enabled,goal_max:c.goal?.default_max_iterations,goal_enabled:c.goal?.enabled,babysitting:c.babysitting?.timeout_ms,notification:c.notification?.force_enable,comment_checker:!!c.comment_checker?.custom_prompt,disabled_skills:(c.disabled_skills||[]).length,disabled_commands:(c.disabled_commands||[]).length}))" 2>/dev/null || echo "{}")
OC_FIELDS=$(node -e "const c=require('./opencode.json');console.log(JSON.stringify({edit_ssh:c.permission?.edit?.['**/.ssh/**'],batch_tool:c.experimental?.batch_tool,continue_loop:c.experimental?.continue_loop_on_deny,policies:(c.experimental?.policies||[]).length,mcp_timeout:c.experimental?.mcp_timeout,prune:c.compaction?.prune,tail_turns:c.compaction?.tail_turns,formatter:c.formatter,instructions:(c.instructions||[]).length}))" 2>/dev/null || echo "{}")

M_ON=$(echo "$OMO_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).monitor" 2>/dev/null)
M_MAX=$(echo "$OMO_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).goal_max" 2>/dev/null)
M_BABY=$(echo "$OMO_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).babysitting" 2>/dev/null)
M_NOTI=$(echo "$OMO_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).notification" 2>/dev/null)
M_COMMENT=$(echo "$OMO_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).comment_checker" 2>/dev/null)
M_DSK=$(echo "$OMO_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).disabled_skills" 2>/dev/null)
M_DCMD=$(echo "$OMO_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).disabled_commands" 2>/dev/null)

O_EDIT=$(echo "$OC_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).edit_ssh" 2>/dev/null)
O_BATCH=$(echo "$OC_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).batch_tool" 2>/dev/null)
O_POL=$(echo "$OC_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).policies" 2>/dev/null)
O_PRUNE=$(echo "$OC_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).prune" 2>/dev/null)
O_FMT=$(echo "$OC_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).formatter" 2>/dev/null)
O_INST=$(echo "$OC_FIELDS" | node -pe "JSON.parse(require('fs').readFileSync(0)).instructions" 2>/dev/null)

[ "$M_ON" = "true" ]                 && ok "OMO monitor.enabled=true（后台监控 idle 模式）" || fail "OMO monitor.enabled 未启用（oh-my-openagent.json）"
[ -n "$M_MAX" ] && [ "$M_MAX" -le 1000 ]  && ok "OMO goal.default_max_iterations=$M_MAX（4.19.0 Goal 替代 Ralph Loop，已配防失控）" || fail "OMO goal.default_max_iterations 未设或 >1000（防失控）"
[ -n "$M_BABY" ] && [ "$M_BABY" -ge 180000 ] && ok "OMO babysitting.timeout_ms=$M_BABY（适配 GLM-5.2）" || warn "OMO babysitting.timeout_ms 未调高（默认 120000 在 max reasoning 下可能误杀）"
[ -z "$M_NOTI" ] || [ "$M_NOTI" = "undefined" ]  && ok "OMO notification 块已删除（dead config 清理）" || ok "OMO notification.force_enable=$M_NOTI"
[ "$M_COMMENT" = "true" ]             && ok "OMO comment_checker.custom_prompt 已配" || warn "OMO comment_checker 未配（可选）"
[ -n "$M_DSK" ] && [ "$M_DSK" -ge 1 ]  && ok "OMO disabled_skills: $M_DSK 条（playwright/dev-browser/agent-browser）" || warn "OMO disabled_skills 未配"
[ -n "$M_DCMD" ] && [ "$M_DCMD" -ge 1 ] && ok "OMO disabled_commands: $M_DCMD 条（goal/refactor/start-work 等）" || warn "OMO disabled_commands 未配（可选）"
[ "$O_EDIT" = "deny" ]                && ok "opencode permission.edit 加了 .ssh/** deny（纵深防御）" || fail "opencode permission.edit 缺 .ssh/** deny（写文件层无防护）"
[ "$O_BATCH" = "true" ]               && ok "opencode experimental.batch_tool=true（批量工具调用）" || warn "opencode experimental.batch_tool 未启用"
[ -n "$O_POL" ] && [ "$O_POL" -ge 1 ]  && ok "opencode experimental.policies: $O_POL 条（deny 海外 provider）" || warn "opencode experimental.policies 未配（可选）"
[ "$O_PRUNE" = "true" ]               && ok "opencode compaction.prune=true（自动修剪旧工具输出）" || warn "opencode compaction.prune 未启用（默认 false 浪费 token）"
[ "$O_FMT" = "true" ]                 && ok "opencode formatter=true（启用内置格式化器，无 prettier 时 no-op）" || warn "opencode formatter 未启用（可选）"
[ -n "$O_INST" ] && [ "$O_INST" -ge 1 ] && ok "opencode instructions: $O_INST 条引用（.opencode/instructions.md）" || warn "opencode instructions 未配（可选）"
echo ""

# ---------- 12. [Warning] tui.json plugin 同步 ----------
echo "【12/13·Warning】tui.json plugin 字段与 opencode.json 同步"
# tui.json 是 TUI 模式的独立配置，plugin 数组必须与 opencode.json 保持同步
# 否则 TUI 模式加载的 plugin 与 CLI 模式不一致
TU_SYNC=$(node -e "const a=require('./opencode.json').plugin||[];const b=require('./tui.json').plugin||[];process.stdout.write(JSON.stringify(a)===JSON.stringify(b)?'sync':'mismatch')" 2>/dev/null || echo "error")
if [ "$TU_SYNC" = "sync" ]; then
  ok "tui.json plugin 与 opencode.json 一致"
elif [ "$TU_SYNC" = "mismatch" ]; then
  wfail "tui.json plugin 与 opencode.json 不同步（运行 make tui-sync 验证）"
else
  wfail "tui.json 或 opencode.json 读取失败（语法错误？）"
fi
echo ""
# ---------- 13. [Warning] superpowers 版本锁定检测 ----------
echo "【13/13·Warning】superpowers 版本锁定检测"
 
# 解析 opencode.json 中 superpowers 的 #vX.Y.Z
SP_LOCKED=$(grep -oE 'superpowers@git\+https://github\.com/obra/superpowers\.git#v[0-9]+\.[0-9]+\.[0-9]+' opencode.json | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
 
if [ -z "$SP_LOCKED" ]; then
  warn "superpowers 未锁定版本（建议改为 superpowers@git+https://github.com/obra/superpowers.git#vX.Y.Z）"
  echo ""
  # 跳过后续检测
else
  echo "  当前锁定：$SP_LOCKED"
  # 查远端最新 tag（macOS 无 timeout 时降级直跑）
  if command -v timeout >/dev/null 2>&1; then
    SP_REMOTE=$(timeout 8 git ls-remote --tags https://github.com/obra/superpowers.git 2>/dev/null | grep -v '\^{}$' | awk '{print $2}' | sed 's|refs/tags/||' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | sed 's/^/v/')
  elif command -v gtimeout >/dev/null 2>&1; then
    SP_REMOTE=$(gtimeout 8 git ls-remote --tags https://github.com/obra/superpowers.git 2>/dev/null | grep -v '\^{}$' | awk '{print $2}' | sed 's|refs/tags/||' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | sed 's/^/v/')
  else
    # 无 timeout 可用时，git ls-remote 自身有 connect timeout 兜底
    SP_REMOTE=$(git ls-remote --tags https://github.com/obra/superpowers.git 2>/dev/null | grep -v '\^{}$' | awk '{print $2}' | sed 's|refs/tags/||' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | sed 's/^/v/')
  fi
  if [ -z "$SP_REMOTE" ]; then
    warn "superpowers 远端检测跳过（无网络或仓库不可达）"
  elif [ "$SP_LOCKED" = "$SP_REMOTE" ]; then
    ok "superpowers $SP_LOCKED = 远端最新 $SP_REMOTE"
  else
    # semver 比较：把 v6.1.1 拆成数字比对
    L_MAJOR=$(echo "$SP_LOCKED" | sed 's/v//' | cut -d. -f1)
    L_MINOR=$(echo "$SP_LOCKED" | sed 's/v//' | cut -d. -f2)
    L_PATCH=$(echo "$SP_LOCKED" | sed 's/v//' | cut -d. -f3)
    R_MAJOR=$(echo "$SP_REMOTE" | sed 's/v//' | cut -d. -f1)
    R_MINOR=$(echo "$SP_REMOTE" | sed 's/v//' | cut -d. -f2)
    R_PATCH=$(echo "$SP_REMOTE" | sed 's/v//' | cut -d. -f3)
 
    if [ "$R_MAJOR" -gt "$L_MAJOR" ] || \
       { [ "$R_MAJOR" -eq "$L_MAJOR" ] && [ "$R_MINOR" -gt "$L_MINOR" ]; } || \
       { [ "$R_MAJOR" -eq "$L_MAJOR" ] && [ "$R_MINOR" -eq "$L_MINOR" ] && [ "$R_PATCH" -gt "$L_PATCH" ]; }; then
      warn "superpowers 有新版：$SP_LOCKED → $SP_REMOTE（运行 make upgrade-superpowers）"
    else
      warn "superpowers 本地 $SP_LOCKED 比远端 $SP_REMOTE 还新（异常，请检查）"
    fi
  fi
fi
echo ""


# ---------- 汇总 ----------
TOTAL_FAIL=$((FAIL + WFAIL))
echo "═══════════════════════════════════════════"
echo "  通过 $PASS ｜ 失败 $TOTAL_FAIL（critical $FAIL / warning $WFAIL）｜ 警告 $WARN"
echo "═══════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "❌ 有 $FAIL 项 critical 失败，必须修复才能使用 opencode。"
  exit 1
elif [ "$WFAIL" -gt 0 ]; then
  echo ""
  echo "⚠️  有 $WFAIL 项 warning 失败（可选功能未就绪，不影响核心使用）。"
  exit 0
elif [ "$WARN" -gt 0 ]; then
  echo ""
  echo "⚠️  有 $WARN 项警告（可选）。"
  exit 0
else
  echo ""
  echo "🎉 全部就绪！"
  exit 0
fi
