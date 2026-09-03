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
info()  { echo "  ⏭️  $1"; }                              # SKIP / informational，不计入任何计数
# 守卫：仅无符号整数才返回 0。避免 node -pe 在字段缺失时返回字面 "undefined"
# 触发 bash `[ X -ge N ]` 的 `integer expression expected` stderr 噪音。
is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }

echo "╔══════════════════════════════════════════╗"
echo "║     opencode 配置体检                    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

if [ -z "$CHECK_FAST" ]; then
  # ---------- 1. [Critical] 基础环境 + 环境变量 ----------
  echo "【1/16·Critical】基础环境 + 环境变量"
  # --- Node.js 与 opencode 安装 ---
  NODE_VER=$(node --version 2>/dev/null || echo "")
  if [ -n "$NODE_VER" ]; then
    NODE_MAJOR=$(echo "$NODE_VER" | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_MAJOR" -ge 22 ]; then
      ok "Node.js $NODE_VER"
    else
      fail "Node.js ${NODE_VER}（需要 ≥22，运行 fnm install 22）"
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
  [ -n "${Z_AI_API_KEY:-}" ]     && ok "Z_AI_API_KEY 已设置"      || fail "Z_AI_API_KEY 未设置（make config）"
  [ -n "${FEISHU_APP_SECRET:-}" ] && ok "FEISHU_APP_SECRET 已设置" || warn "FEISHU_APP_SECRET 未设置（飞书 CLI 需要）"
  echo ""
fi

# ---------- 2. [Critical] npm 依赖 ----------
echo "【2/16·Critical】npm 依赖版本"
 
if npm ls --depth=0 2>&1 | grep -q "invalid"; then
  fail "node_modules 版本不一致（运行 make update 重装）"
else
  OMO_VER=$(node -p "require('./node_modules/oh-my-openagent/package.json').version" 2>/dev/null || echo "")
  PLG_VER=$(node -p "require('./node_modules/@opencode-ai/plugin/package.json').version" 2>/dev/null || echo "")
  [ -n "$OMO_VER" ] && ok "oh-my-openagent@$OMO_VER" || fail "oh-my-openagent 未安装"
  [ -n "$PLG_VER" ] && ok "@opencode-ai/plugin@$PLG_VER" || fail "@opencode-ai/plugin 未安装"
fi
echo ""

if [ -z "$CHECK_FAST" ]; then
  # ---------- 3. [Warning] opencode-mem 记忆插件 ----------
  echo "【3/16·Warning】opencode-mem 记忆插件"
 
  if [ -L "node_modules/opencode-mem" ] && [ -d "node_modules/opencode-mem" ]; then
    MEM_VER=$(node -p "require('./node_modules/opencode-mem/package.json').version" 2>/dev/null || echo "?")
    ok "opencode-mem@$MEM_VER 软链就绪"
  else
    wfail "opencode-mem 软链未建立（make deps）"
  fi

  # pin 缓存目录 + tags 兑底 patch 存活检查（opencode.json spec 为事实源；patch 详见 scripts/patch-mem-tags.mjs）
  MEM_SPEC=$(node -p "require('./opencode.json').plugin.find(p=>String(p).startsWith('opencode-mem@')) ?? ''" 2>/dev/null || echo '')
  if [ -n "$MEM_SPEC" ] && [ "$MEM_SPEC" != "opencode-mem@latest" ]; then
    MEM_CACHE_DIR="$HOME/.cache/opencode/packages/$MEM_SPEC/node_modules/opencode-mem"
    if [ -d "$MEM_CACHE_DIR" ]; then
      if grep -q "PATCH(tags-fallback)" "$MEM_CACHE_DIR/dist/services/client.js" 2>/dev/null; then
        ok "$MEM_SPEC pin 缓存就绪，tags 兑底 patch 存活"
      else
        wfail "$MEM_SPEC 缺 tags 兑底 patch（node scripts/patch-mem-tags.mjs 重打）"
      fi
    else
      wfail "pin 缓存目录不存在: $MEM_SPEC（重启 opencode 拉取）"
    fi
  fi

  # 检查 opencode-mem 配置文件就绪状态（provider-agnostic，不强制特定厂商）
  # 该文件必需（插件加载需要），但用哪个 provider 是用户选择，不应当伪体检项。
  if [ ! -f "opencode-mem.jsonc" ]; then
    warn "opencode-mem.jsonc 不存在（make mem 生成）"
  elif grep -q '"memoryApiKey":\s*"env://' opencode-mem.jsonc && grep -q '"memoryProvider"' opencode-mem.jsonc; then
    # 提取实际使用的 model 和 host 展示（awk 精确匹配 JSON key，避免被注释行干扰）
    MEM_MODEL=$(awk -F'"' '/^[[:space:]]*"memoryModel"[[:space:]]*:/{print $4; exit}' opencode-mem.jsonc)
    MEM_HOST=$(awk -F'"' '/^[[:space:]]*"memoryApiUrl"[[:space:]]*:/{print $4; exit}' opencode-mem.jsonc | awk -F/ '{print $3}' | awk -F@ '{print $NF}')  # 按 @ 分隔后取末段，去掉 userinfo 避免凭证泄露（https://key@host 场景）
    ok "opencode-mem.jsonc 已配置（model=${MEM_MODEL:-?}, host=${MEM_HOST:-?}）"
  else
    warn "opencode-mem.jsonc 未配置有效 provider（检查 memoryProvider / memoryApiKey 字段）"
  fi
  echo ""
fi

if [ -z "$CHECK_FAST" ]; then
  # ---------- 4. [Warning] 全局 MCP 依赖 ----------
  echo "【4/16·Warning】全局 MCP 依赖"
 
  # 预期版本常量：全局 bin 通道（npm i -g）的版本锁定比对——升级全局包后同步此处（B2 通道 2）
  EXPECTED_MERMAID="1.6.5"
  EXPECTED_CODEGRAPH="1.6.0"
  if command -v claude-mermaid >/dev/null 2>&1; then
    MERMAID_VER=$(claude-mermaid --version 2>/dev/null | head -1)
    if [ "$MERMAID_VER" = "$EXPECTED_MERMAID" ]; then
      ok "claude-mermaid $MERMAID_VER（= 锁定版本）"
    else
      wfail "claude-mermaid $MERMAID_VER ≠ 锁定 $EXPECTED_MERMAID（重装：npm i -g claude-mermaid@$EXPECTED_MERMAID，或升级后同步 check.sh 常量）"
    fi
  else
    wfail "claude-mermaid 未安装（npm i -g claude-mermaid@$EXPECTED_MERMAID）"
  fi
  if command -v codegraph >/dev/null 2>&1; then
    CODEGRAPH_VER=$(codegraph --version 2>/dev/null | head -1)
    if [ "$CODEGRAPH_VER" = "$EXPECTED_CODEGRAPH" ]; then
      ok "codegraph $CODEGRAPH_VER（= 锁定版本）"
    else
      wfail "codegraph $CODEGRAPH_VER ≠ 锁定 $EXPECTED_CODEGRAPH（重装：npm i -g @colbymchenry/codegraph@$EXPECTED_CODEGRAPH，或升级后同步 check.sh 常量）"
    fi
  else
    wfail "codegraph 未安装（npm i -g @colbymchenry/codegraph@$EXPECTED_CODEGRAPH）"
  fi
  echo ""
fi

if [ -z "$CHECK_FAST" ]; then
  # ---------- 5. [Warning] 飞书 CLI ----------
  echo "【5/16·Warning】飞书 CLI"
 
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
fi

if [ -z "$CHECK_FAST" ]; then
  # ---------- 6. [Warning] Web UI ----------
  echo "【6/16·Warning】opencode-mem Web UI"
 
  # opencode-mem Web UI 只在 opencode 主进程启动时才拉起；check 脚本通常在 opencode 外部运行，
  # 直接 curl 端口会把"opencode 没开"误报为配置警告。先探测进程状态再决定怎么报。
  # 注意端点选择：/api/stats 需要 auth token（返回 Unauthorized），用公开的 /api/health 才能探活性。
  if ! pgrep -x opencode >/dev/null 2>&1 && ! pgrep -f "node.*opencode" >/dev/null 2>&1; then
    info "opencode 进程未运行 → 跳过 Web UI 探测（启动 opencode 后 Web UI 自动拉起，:4747）"
  else
    HEALTH=$(curl -s --max-time 3 http://127.0.0.1:4747/api/health 2>/dev/null || echo "")
    if echo "$HEALTH" | grep -q '"success":true'; then
      AUTH=$(echo "$HEALTH" | node -pe "JSON.parse(require('fs').readFileSync(0)).authEnabled ? '（已开认证，详情需 token）' : ''" 2>/dev/null || echo "")
      ok "Web UI 运行中（http://127.0.0.1:4747/api/health ✓ ${AUTH})"
    else
      warn "opencode 进程在跑但 Web UI :4747/api/health 未响应（可能未加载 opencode-mem 插件）"
    fi
  fi
  echo ""
fi
if [ -z "$CHECK_FAST" ]; then
  # ---------- 7. [Warning] plugin @latest 漂移检测（opencode 缓存 vs 项目软链） ----------
  echo "【7/16·Warning】plugin @latest 漂移检测（opencode 缓存 vs 项目软链）"
 
  # opencode-mem 走 @latest 缓存路径加载（~/.cache/opencode/packages/）
  # 项目软链 node_modules/opencode-mem -> 全局装版本
  # 两者不一致时，opencode 启动会加载缓存版本（@latest 拉到的），而非软链版本
  LINKED_VER=$(node -p "require('./node_modules/opencode-mem/package.json').version" 2>/dev/null || echo "?")
  # mem spec 从 opencode.json 动态解析（Wave4：消除 @latest 硬编码；mem 走全局安装+@latest 模型，钉版需另行决策）
  MEM_SPEC=$(node -pe "JSON.parse(require('fs').readFileSync('opencode.json','utf8')).plugin.find(p=>p.startsWith('opencode-mem')) ?? ''" 2>/dev/null || echo "opencode-mem@latest")
  CACHE_DIR="$HOME/.cache/opencode/packages/$MEM_SPEC"
  if [ -d "$CACHE_DIR" ]; then
    CACHED_VER=$(node -p "require('$CACHE_DIR/node_modules/opencode-mem/package.json').version" 2>/dev/null || echo "?")
    if [ "$LINKED_VER" = "$CACHED_VER" ]; then
      ok "opencode-mem 软链 ${LINKED_VER} = opencode 缓存 ${CACHED_VER}（@latest 一致）"
    else
      warn "opencode-mem 软链 ${LINKED_VER} ≠ opencode 缓存 ${CACHED_VER}（@latest 已漂移，opencode 启动会加载缓存版本而非软链版本——运行 make update 后会自动清缓存重拉）"
    fi
  else
    warn "opencode-mem 未在 opencode 缓存中（首次启动 opencode 后才会缓存）"
  fi
  echo ""
fi
if [ -z "$CHECK_FAST" ]; then
  # ---------- 8. [Warning] lark skills SHA256 校验 ----------
  echo "【8/16·Warning】skills SHA256 校验（供应链完整性，lark + OMO）"
 
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
            wfail "SKILL 哈希不匹配：${REL_PATH}（可能被篡改）"
            MISMATCH=$((MISMATCH+1))
          fi
        fi
      done < skills.lock
      if [ "$MISMATCH" -eq 0 ] && [ "$MISSING" -eq 0 ]; then
        ok "skills.lock $TOTAL 条全部匹配"
      fi
      if [ "$MISSING" -gt 0 ]; then
        wfail "skills.lock $MISSING 条实机缺失（供应链防消失）— 对账 make skills-lock 或自备份恢复"
      fi
    fi
  fi
  echo ""
fi
if [ -z "$CHECK_FAST" ]; then
  # ---------- 9. [Warning] oh-my-openagent 内置 skill 软链健康 ----------
  echo "【9/16·Warning】oh-my-openagent 内置 skill 软链健康（含自愈）"
 
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
fi
if [ -z "$CHECK_FAST" ]; then
  # ---------- 10. [Critical] opencode plugin 缓存健康（dist/skills 完整性，根因检查） ----------
  echo "【10/16·Critical】opencode plugin 缓存健康（dist/skills 完整性）"
 
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
  # plugin 缓存路径从 opencode.json 动态解析（spec 即缓存目录名），升级版本不再需要改本脚本
  OMO_PLUGIN_SPEC=$(node -p "require('./opencode.json').plugin.find(p=>p.startsWith('oh-my-openagent@')) ?? ''" 2>/dev/null || echo '')
  if [ -z "$OMO_PLUGIN_SPEC" ]; then
    fail "opencode.json 未找到 oh-my-openagent@<version> plugin 条目 — 检查配置"
  fi
  CACHE_PLUGIN_SKILLS="$HOME/.cache/opencode/packages/$OMO_PLUGIN_SPEC/node_modules/oh-my-openagent/dist/skills"

  PROJECT_COUNT=$(count_complete_skills "$PROJECT_SKILLS_DIR")
  BUILTIN_COUNT=$(count_complete_skills "$CACHE_BUILTIN_SKILLS")
  PLUGIN_COUNT=$(count_complete_skills "$CACHE_PLUGIN_SKILLS")

  if [ "$PROJECT_TOTAL" -eq 0 ]; then
    fail "无法读取项目锁定 dist/skills（node_modules/oh-my-openagent 缺失或损坏）— 运行 make install / make update"
  elif [ "$PROJECT_COUNT" -ne "$PROJECT_TOTAL" ]; then
    fail "项目锁定 dist/skills 损坏（${PROJECT_COUNT}/${PROJECT_TOTAL} 有 SKILL.md）— 运行 make update 重装"
  elif [ ! -d "$CACHE_BUILTIN_SKILLS" ]; then
    # opencode 1.17.11+ 不再 builtin 装 oh-my-opencode 主包（只装 platform binary），路径不存在是正常状态
    if [ "$PLUGIN_COUNT" -eq "$PROJECT_TOTAL" ]; then
      ok "项目锁定 + plugin 缓存完整（${PROJECT_TOTAL}/${PROJECT_TOTAL}，builtin 未装载，已 skip）— plugin 加载链健康"
    elif [ "$PLUGIN_COUNT" -eq 0 ]; then
      warn "opencode 缓存未创建（项目锁定 OK，${PROJECT_TOTAL}/${PROJECT_TOTAL}）— 首次启动 opencode 后自动缓存"
    else
      fail "plugin 缓存不完整（${PLUGIN_COUNT}/${PROJECT_TOTAL}）— 运行 make update"
    fi
  elif [ "$BUILTIN_COUNT" -eq "$PROJECT_TOTAL" ] && [ "$PLUGIN_COUNT" -eq "$PROJECT_TOTAL" ]; then
    ok "三处 dist/skills 完整（项目锁定 + builtin 缓存 + plugin 缓存，${PROJECT_TOTAL}×3）— plugin 加载链健康"
  elif [ "$BUILTIN_COUNT" -ne "$PROJECT_TOTAL" ]; then
    fail "builtin 缓存不完整（${BUILTIN_COUNT}/${PROJECT_TOTAL}）— 运行 make update"
  else
    fail "plugin 缓存不完整（${PLUGIN_COUNT}/${PROJECT_TOTAL}）— 运行 make update"
  fi
fi

if [ -z "$CHECK_FAST" ]; then
  # ---------- 11. [Critical] OMO + opencode 关键字段验证 ----------
  echo "【11/16·Critical】OMO + opencode 关键字段配置验证"
 
  # 用 node 提取字段避免 jq 依赖
  OMO_FIELDS=$(node scripts/read-omo-config.mjs 2>/dev/null || echo "{}")
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

  [ "$M_ON" = "true" ]                 && ok "OMO monitor.enabled=true（后台监控 idle 模式）" || fail "OMO monitor.enabled 未启用（~/.omo/omo.jsonc）"
  is_uint "$M_MAX" && [ "$M_MAX" -le 1000 ]  && ok "OMO goal.default_max_iterations=${M_MAX}（Goal 替代 Ralph Loop，已配防失控）" || fail "OMO goal.default_max_iterations 未设或 >1000（防失控）"
  # babysitting.timeout_ms 是模型/负载特定调优（GLM-5.3 + max reasoning 需要 ≥180s，简单任务默认 120s 够用）。
  # 配了就展示当前值；没配就是默认 120s，info 提示即可，不应当成异常。
  if is_uint "$M_BABY" && [ "$M_BABY" -ge 180000 ]; then
    ok "OMO babysitting.timeout_ms=${M_BABY}（适配 GLM-5.3 + max reasoning）"
  elif is_uint "$M_BABY"; then
    info "OMO babysitting.timeout_ms=${M_BABY}（默认值；max reasoning 下如遇误杀可调到 ≥180000）"
  else
    info "OMO babysitting.timeout_ms 未显式设置（使用默认 120000；max reasoning 下如遇误杀可调到 ≥180000）"
  fi
  [ -z "$M_NOTI" ] || [ "$M_NOTI" = "undefined" ]  && ok "OMO notification 块已删除（dead config 清理）" || ok "OMO notification.force_enable=${M_NOTI}"
  # comment_checker 是可选的注释质检特性。启用 → 展示；未启用 → info（默认状态，不是错）。
  if [ "$M_COMMENT" = "true" ]; then
    ok "OMO comment_checker.custom_prompt 已配"
  else
    info "OMO comment_checker 未启用（默认）"
  fi
  # disabled_skills 是用户偏好（决定哪些 skill 不被加载），和 disabled_commands 一样没有“应该配什么”的通用答案。
  if is_uint "$M_DSK" && [ "$M_DSK" -ge 1 ]; then
    ok "OMO disabled_skills: ${M_DSK} 条（手动配置，拦截指定 skill 加载）"
  else
    info "OMO disabled_skills 未配（默认，所有 skill 均可加载）"
  fi
  # disabled_commands 是高度个性化的配置（决定哪些 slash 命令完全不注册），没有“应该配什么”的通用答案。
  # 体检不应该把“未配”当异常报。仅在用户配了的情况下展示条数，未配则 SKIP。
  if is_uint "$M_DCMD" && [ "$M_DCMD" -ge 1 ]; then
    ok "OMO disabled_commands: ${M_DCMD} 条（手动配置，会影响用户自身调用）"
  else
    info "OMO disabled_commands 未配（默认，所有 / 命令均可用）"
  fi
  [ "$O_EDIT" = "deny" ]                && ok "opencode permission.edit 加了 .ssh/** deny（纵深防御）" || fail "opencode permission.edit 缺 .ssh/** deny（写文件层无防护）"
  # experimental.batch_tool 是性能优化项（批量工具调用），未启用是合理默认（与 policies/prune/formatter 同类）。
  if [ "$O_BATCH" = "true" ]; then
    ok "opencode experimental.batch_tool=true（启用，批量工具调用）"
  else
    info "opencode experimental.batch_tool 未启用（默认，逐个调用工具）"
  fi
  # experimental.policies 是策略选择（如 deny 海外 provider），不是硬性要求。
  if is_uint "$O_POL" && [ "$O_POL" -ge 1 ]; then
    ok "opencode experimental.policies: ${O_POL} 条（手动配置路由策略）"
  else
    info "opencode experimental.policies 未配（默认，未限制任何 provider）"
  fi
  # compaction.prune 是 token 优化 vs 完整历史的权衡，默认 false 是合理选择。
  if [ "$O_PRUNE" = "true" ]; then
    ok "opencode compaction.prune=true（启用，自动修剪旧工具输出节省 token）"
  else
    info "opencode compaction.prune 未启用（默认，保留全部历史）"
  fi
  # formatter 是可选特性，无 prettier 时 no-op。开不开都不应当报 warn。
  if [ "$O_FMT" = "true" ]; then
    ok "opencode formatter=true（已启用，无 prettier 时 no-op）"
  else
    info "opencode formatter 未启用（默认）"
  fi
  # instructions 是可选的上下文增强机制。用户可以选择不用。
  if is_uint "$O_INST" && [ "$O_INST" -ge 1 ]; then
    ok "opencode instructions: ${O_INST} 条引用（.opencode/instructions.md）"
  else
    info "opencode instructions 未配（默认，无额外上下文注入）"
  fi
  echo ""
fi

if [ -z "$CHECK_FAST" ]; then
  # ---------- 12. [Warning] tui.json plugin 同步 ----------
  echo "【12/16·Warning】tui.json plugin 字段与 opencode.json 同步"
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
fi
if [ -z "$CHECK_FAST" ]; then
  # ---------- 13. [Warning] superpowers 版本锁定检测 ----------
  echo "【13/16·Warning】superpowers 版本锁定检测"
 
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
      SP_REMOTE=$(timeout 8 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 ls-remote --tags https://github.com/obra/superpowers.git 2>/dev/null | grep -v '\^{}$' | awk '{print $2}' | sed 's|refs/tags/||' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | sed 's/^/v/')
    elif command -v gtimeout >/dev/null 2>&1; then
      SP_REMOTE=$(gtimeout 8 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 ls-remote --tags https://github.com/obra/superpowers.git 2>/dev/null | grep -v '\^{}$' | awk '{print $2}' | sed 's|refs/tags/||' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | sed 's/^/v/')
    else
      # 无 timeout 可用时，用 git http.lowSpeed 兜底（传输 <1KB/s 持续 10s 即断，避免网络抖动时无限挂起）
      SP_REMOTE=$(git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 ls-remote --tags https://github.com/obra/superpowers.git 2>/dev/null | grep -v '\^{}$' | awk '{print $2}' | sed 's|refs/tags/||' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | sed 's/^/v/')
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
        warn "superpowers 有新版：$SP_LOCKED → ${SP_REMOTE}（运行 make upgrade-superpowers）"
      else
        warn "superpowers 本地 $SP_LOCKED 比远端 $SP_REMOTE 还新（异常，请检查）"
      fi
    fi
  fi
  echo ""
fi

# ---------- 14. [Critical] template ↔ 生成物零漂移 ----------
echo "【14/16·Critical】template ↔ 生成物零漂移（omo / opencode-mem）"
 
# instructions.md 工作约束 5 的自动化 enforcement：template 改了生成物没同步（或反之）= 配置不一致。
# 规范化比较（剥注释/尾逗号、omo 排除运行时写入的 _migrations），漂移即 critical fail 阻断提交。
DRIFT_JSON=$(node scripts/check-drift.mjs 2>/dev/null || echo '{}')
for pair in omo mem pluginSpec docRefs; do
  D_EXIST=$(echo "$DRIFT_JSON" | node -pe "JSON.parse(require('fs').readFileSync(0))['$pair'].exists" 2>/dev/null || echo "")
  D_DRIFT=$(echo "$DRIFT_JSON" | node -pe "JSON.parse(require('fs').readFileSync(0))['$pair'].drift" 2>/dev/null || echo "")
  D_DETAIL=$(echo "$DRIFT_JSON" | node -pe "JSON.parse(require('fs').readFileSync(0))['$pair'].detail" 2>/dev/null || echo "检测脚本异常")
  # 注意：macOS bash 3.2 在双引号内「含多字节值的变量 + 多字节字面量」拼接时会损坏字节，
  # 故 detail 变量独立传参，修复提示写纯字面量（pair 为 ASCII 可安全拼接）。
  if [ "$D_EXIST" != "true" ]; then
    info "$D_DETAIL"
  elif [ "$D_DRIFT" = "true" ]; then
    fail "$pair 配置漂移: $D_DETAIL — omo/mem 两处同步（约束 5）或 rm 生成物后重建；pluginSpec 跑 make upgrade 自动同步或手动对齐 spec"
  elif [ "$D_DRIFT" != "false" ]; then
    fail "$pair 漂移检测异常（drift:$D_DRIFT — 解析失败或脚本异常）— 手动跑 node scripts/check-drift.mjs 看原始输出"
  else
    ok "$D_DETAIL"
  fi
done
echo ""
# ---------- 15. [Critical] instructions 引用完整性 ----------
echo "【15/16·Critical】instructions 引用完整性（{file:...} 目标存在）"
 
# opencode.json instructions 数组引用的文件若丢失，系统提示注入会静默失效；检测引用目标存在性。
INST_TOTAL=$(echo "$DRIFT_JSON" | node -pe "JSON.parse(require('fs').readFileSync(0)).instructions.total" 2>/dev/null || echo "0")
INST_MISSING=$(echo "$DRIFT_JSON" | node -pe "JSON.parse(require('fs').readFileSync(0)).instructions.missing.length" 2>/dev/null || echo "0")
if ! is_uint "$INST_TOTAL" || [ "$INST_TOTAL" -eq 0 ]; then
  fail "instructions 引用总数为 0（check-drift.mjs 输出异常或 opencode.json 解析失败）"
elif [ "$INST_MISSING" -eq 0 ]; then
  ok "instructions $INST_TOTAL 条 {file:...} 引用全部存在"
else
  for f in $(echo "$DRIFT_JSON" | node -pe "JSON.parse(require('fs').readFileSync(0)).instructions.missing.join(' ')" 2>/dev/null); do
    fail "instructions 引用缺失：$f"
  done
fi
echo ""
if [ -z "$CHECK_FAST" ]; then
  # ---------- 16. [Warning] export 备份新鲜度 ----------
  echo "【16/16·Warning】export 备份新鲜度（dbx.md / skills 唯一备份通道）"
 
  # dbx.md、54 个用户 skill 不在 git 内，唯一备份通道是 make export 导出包；
  # 包比关键源文件旧 = 单点丢失风险。纯本地 mtime 比较，无网络依赖。
  # 双位置取最新（Wave5：HEADLESS 落 ~/Backups/opencode/，交互默认 ~/Desktop）
    LATEST_EXPORT=$(ls -t "$HOME/Desktop"/opencode-config-*.tar.gz "$HOME/Backups/opencode"/opencode-config-*.tar.gz 2>/dev/null | head -1)
  if [ -z "$LATEST_EXPORT" ]; then
    warn "未在 ~/Desktop 找到导出包（dbx.md / skills 唯一备份通道）— 运行 make export（若已导出到其他位置可忽略）"
  else
    EXPORT_MTIME=$(stat -f %m "$LATEST_EXPORT")
    STALE_FILES=""
    for src in .opencode/dbx.md skills.lock; do
      [ -f "$src" ] || continue
      SRC_MTIME=$(stat -f %m "$src")
      [ "$SRC_MTIME" -gt "$EXPORT_MTIME" ] && STALE_FILES="$STALE_FILES $src"
    done
    # 用户自有 skill 直改检测（Wave4：覆盖不重跑 skills-lock 的路径）
    # 双排除硬需求：-not -type l 排软链（node_modules mtime 抖动）、-not -path '*/.git/*' 排嵌套 git 仓库（hooloo 等，曾是 20% 误报源）
    STALE_SKILLS=$(find "$HOME/.agents/skills" -type f -not -type l -not -path '*/.git/*' -newer "$LATEST_EXPORT" 2>/dev/null | head -5 | wc -l | tr -d ' ')
    [ "$STALE_SKILLS" -gt 0 ] && STALE_FILES="$STALE_FILES +${STALE_SKILLS}个skill文件"
    if [ -n "$STALE_FILES" ]; then
      warn "导出包 $(basename "$LATEST_EXPORT") 比最近改动的 $STALE_FILES 旧 - 重跑 make export 保持备份新鲜"
    else
      ok "导出包新鲜（$(basename "$LATEST_EXPORT")）"
    fi
  fi
  echo ""

  echo ""
fi


# ---------- 汇总 ----------
TOTAL_FAIL=$((FAIL + WFAIL))
echo "═══════════════════════════════════════════"
echo "  通过 ${PASS} ｜ 失败 ${TOTAL_FAIL}（critical ${FAIL} / warning ${WFAIL}）｜ 警告 ${WARN}"
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
