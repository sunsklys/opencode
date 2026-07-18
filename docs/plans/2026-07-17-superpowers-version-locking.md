# superpowers 版本锁定 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 opencode.json 的 superpowers plugin 加 tag 版本锁定（`#v6.1.1`），并集成进 make check 体检（section 13，软失败）和一键升级命令（`make upgrade-superpowers`）。

**Architecture:** 不新增独立检测脚本，而是把检测逻辑作为 section 13 集成进现有 `scripts/check.sh`（和 plugin @latest 漂移检测的 section 7 保持同一模式）。升级逻辑放独立脚本 `scripts/upgrade-superpowers.sh`，由 Makefile target 调用。

**Tech Stack:** Bash（macOS 兼容：`sed -i ''`、`set -e`）、Make、JSON（grep 解析，避免 jq 依赖）。

**Spec:** `docs/specs/2026-07-17-superpowers-version-locking.md`

## Global Constraints

- **macOS 兼容**：`sed -i ''`（不是 GNU sed 的 `sed -i`）；`shasum`（不是 `sha256sum`）；`bash` 而非 `sh`
- **软失败原则**：检测脚本任何失败路径都 `exit 0`，只用 `warn()` 提示，不阻断 make check
- **风格对齐**：复用 `scripts/check.sh` 顶部的 `ok()/warn()/fail()/wfail()` 函数；不重新定义
- **不引入新依赖**：不用 jq、不用 Python；只用 grep/sed/awk/bash 内置
- **版本号格式**：`#vX.Y.Z`（X/Y/Z 都是数字，semver）；解析时正则 `#v([0-9]+)\.([0-9]+)\.([0-9]+)`
- **远端 URL 固定**：`https://github.com/obra/superpowers.git`
- **缓存路径 glob**：`~/.cache/opencode/packages/superpowers@git+https:*`（注意 `+` 和 `:` 是路径合法字符）

---

## Task 1: 锁定 opencode.json 的 superpowers 版本

**Files:**
- Modify: `opencode.json:3`

**Interfaces:**
- Produces: `opencode.json` 的 plugin 字段中 superpowers 字符串以 `#v6.1.1` 结尾，后续 task 的检测脚本依赖此格式

- [ ] **Step 1: 确认当前 L3 内容**

Run: `sed -n '3p' /Users/edy/.config/opencode/opencode.json`
Expected output:
```
  "plugin": ["oh-my-openagent@latest", "opencode-mem@latest", "superpowers@git+https://github.com/obra/superpowers.git"],
```

- [ ] **Step 2: 用 sed 替换 superpowers 字符串，加 #v6.1.1**

Run:
```bash
sed -i '' 's|superpowers@git+https://github.com/obra/superpowers.git"|superpowers@git+https://github.com/obra/superpowers.git#v6.1.1"|' /Users/edy/.config/opencode/opencode.json
```

- [ ] **Step 3: 验证替换成功**

Run: `sed -n '3p' /Users/edy/.config/opencode/opencode.json`
Expected output:
```
  "plugin": ["oh-my-openagent@latest", "opencode-mem@latest", "superpowers@git+https://github.com/obra/superpowers.git#v6.1.1"],
```

- [ ] **Step 4: JSON 合法性校验**

Run: `node -e "JSON.parse(require('fs').readFileSync('/Users/edy/.config/opencode/opencode.json','utf8')); console.log('✓ JSON 合法')"`
Expected: `✓ JSON 合法`

- [ ] **Step 5: 跑 make check 确认未破坏现有 12 项**

Run: `cd /Users/edy/.config/opencode && make check`
Expected: 12 个 section 全跑完，critical 全绿（section 13 尚未加）

- [ ] **Step 6: Commit**

```bash
cd /Users/edy/.config/opencode
git add opencode.json
git commit -m "feat(plugin): superpowers 锁定到 #v6.1.1（tag 版本管理）"
```

---

## Task 2: 写升级脚本 scripts/upgrade-superpowers.sh

**Files:**
- Create: `scripts/upgrade-superpowers.sh`

**Interfaces:**
- Consumes: `opencode.json` L3 的 `#vX.Y.Z` 格式（Task 1 产物）
- Produces: 可执行的 `scripts/upgrade-superpowers.sh`，被 Task 4 的 Makefile target 调用

- [ ] **Step 1: 创建脚本文件**

写入 `/Users/edy/.config/opencode/scripts/upgrade-superpowers.sh`：

```bash
#!/bin/bash
# ============================================================
# superpowers plugin 升级脚本
# 查询远端最新 tag → 改 opencode.json → 清缓存 → 提示重启
# ============================================================
set -e

cd "$(dirname "$0")/.."

OPENCODE_JSON="opencode.json"
REMOTE_URL="https://github.com/obra/superpowers.git"
CACHE_GLOB="$HOME/.cache/opencode/packages/superpowers@git+https:*"

# --- 1. 读当前锁定版本 ---
CURRENT=$(grep -oE 'superpowers@git\+https://github\.com/obra/superpowers\.git#v[0-9]+\.[0-9]+\.[0-9]+' "$OPENCODE_JSON" | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')

if [ -z "$CURRENT" ]; then
  echo "❌ opencode.json 中未找到 superpowers 版本锁定（#vX.Y.Z）"
  echo "   请先手动锁定，例如：superpowers@git+https://github.com/obra/superpowers.git#v6.1.1"
  exit 1
fi

echo "当前锁定版本：$CURRENT"

# --- 2. 查远端最新 tag ---
echo "查询远端最新 tag..."
REMOTE_TAGS=$(git ls-remote --tags "$REMOTE_URL" 2>/dev/null | grep -v '\^{}$' | awk '{print $2}' | sed 's|refs/tags/||' || true)

if [ -z "$REMOTE_TAGS" ]; then
  echo "❌ 无法获取远端 tag（网络问题或仓库异常）"
  exit 1
fi

LATEST=$(echo "$REMOTE_TAGS" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)

echo "远端最新 tag：$LATEST"

# --- 3. 比对 ---
if [ "$CURRENT" = "$LATEST" ]; then
  echo "✓ 已是最新，无需升级"
  exit 0
fi

# --- 4. 替换 opencode.json ---
echo "更新 opencode.json：$CURRENT → $LATEST ..."
sed -i '' "s|superpowers@git+https://github.com/obra/superpowers.git#v[0-9]\+\.[0-9]\+\.[0-9]\+|superpowers@git+https://github.com/obra/superpowers.git#$LATEST|" "$OPENCODE_JSON"

# JSON 合法性校验
node -e "JSON.parse(require('fs').readFileSync('$OPENCODE_JSON','utf8'))" || {
  echo "❌ opencode.json JSON 解析失败，请手动检查"
  exit 1
}

# --- 5. 清缓存 ---
echo "清理旧版本缓存..."
if [ -d "$HOME/.cache/opencode/packages" ]; then
  # 用 find 避免 glob 在 bash 下的歧义
  find "$HOME/.cache/opencode/packages" -maxdepth 1 -name "superpowers@git+https:*" -exec rm -rf {} + 2>/dev/null || true
fi
echo "  ✓ 缓存已清"

# --- 6. 重装依赖（让 opencode 下次启动时拉新版本）---
echo "重装依赖..."
bash scripts/install.sh > /dev/null 2>&1 || echo "  ⚠ scripts/install.sh 失败（可手动 npm install）"

echo ""
echo "✓ superpowers 升级完成：$CURRENT → $LATEST"
echo "  请重启 opencode 以加载新版本"
```

- [ ] **Step 2: 加可执行权限**

Run: `chmod +x /Users/edy/.config/opencode/scripts/upgrade-superpowers.sh`
Expected: 无输出（成功）

- [ ] **Step 3: 干跑验证（当前已是最新）**

Run: `bash /Users/edy/.config/opencode/scripts/upgrade-superpowers.sh`
Expected output（关键行）:
```
当前锁定版本：v6.1.1
查询远端最新 tag...
远端最新 tag：v6.1.1
✓ 已是最新，无需升级
```

- [ ] **Step 4: 模拟落后场景（手动改 opencode.json 为旧版）**

Run:
```bash
# 临时改成 v6.0.0 模拟落后
sed -i '' 's|superpowers.git#v6.1.1|superpowers.git#v6.0.0|' /Users/edy/.config/opencode/opencode.json
bash /Users/edy/.config/opencode/scripts/upgrade-superpowers.sh
```

Expected: 脚本检测到 v6.0.0 → v6.1.1，改回 opencode.json，清缓存，重装。

- [ ] **Step 5: 验证 opencode.json 已被脚本改回 v6.1.1**

Run: `grep superpowers /Users/edy/.config/opencode/opencode.json`
Expected: 包含 `superpowers.git#v6.1.1`

- [ ] **Step 6: 模拟无网场景**

Run:
```bash
# 临时改远端 URL 为不存在的地址，模拟 ls-remote 失败
sed -i '' 's|https://github.com/obra/superpowers.git|https://invalid.invalid/x.git|' /Users/edy/.config/opencode/scripts/upgrade-superpowers.sh.bak 2>/dev/null
# 实际：临时断网或用 nonexistent URL
# 简化：直接看脚本逻辑（REMOTE_TAGS 为空时 exit 1 提示网络问题）
```

简化验证：审阅脚本逻辑——`git ls-remote` 失败时 `REMOTE_TAGS` 为空，触发 `exit 1` 输出 "无法获取远端 tag"。逻辑正确即可。

- [ ] **Step 7: Commit**

```bash
cd /Users/edy/.config/opencode
git add scripts/upgrade-superpowers.sh
git commit -m "feat(scripts): 新增 upgrade-superpowers.sh 一键升级脚本"
```

---

## Task 3: 在 scripts/check.sh 集成 section 13（superpowers 版本检测）

**Files:**
- Modify: `scripts/check.sh`（在文件末尾、最终汇总之前加 section 13）

**Interfaces:**
- Consumes: `opencode.json` 的 `#vX.Y.Z`（Task 1）、`scripts/check.sh` 顶部的 `ok()/warn()` 函数
- Produces: `make check` 输出新增 section 13，所有 section 编号从 `N/12` 变为 `N/13`

- [ ] **Step 1: 先读 check.sh 末尾（找汇总位置）**

Run: `tail -50 /Users/edy/.config/opencode/scripts/check.sh`
找出最终汇总（"总计"/"FAIL"/"exit"）的起始行号。

- [ ] **Step 2: 全文把 N/12 改成 N/13**

Run:
```bash
cd /Users/edy/.config/opencode
sed -i '' 's|【1/12|【1/13|; s|【2/12|【2/13|; s|【3/12|【3/13|; s|【4/12|【4/13|; s|【5/12|【5/13|; s|【6/12|【6/13|; s|【7/12|【7/13|; s|【8/12|【8/13|; s|【9/12|【9/13|; s|【10/12|【10/13|; s|【11/12|【11/13|; s|【12/12|【12/13|' scripts/check.sh
```

- [ ] **Step 3: 验证编号已更新**

Run: `grep -E "【[0-9]+/" /Users/edy/.config/opencode/scripts/check.sh`
Expected: 12 行，全部 `/13`。

- [ ] **Step 4: 在汇总之前插入 section 13**

找到最终汇总段（通常是 `echo "==="` 或 `echo "总计"` 之类）。在它之前插入：

```bash
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
  # 查远端最新 tag（设超时避免卡死）
  SP_REMOTE=$(timeout 8 git ls-remote --tags https://github.com/obra/superpowers.git 2>/dev/null | grep -v '\^{}$' | awk '{print $2}' | sed 's|refs/tags/||' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
 
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
```

- [ ] **Step 5: 跑 make check 验证 section 13 正常**

Run: `cd /Users/edy/.config/opencode && make check`
Expected:
- 13 个 section 全跑完
- Section 13 输出 `当前锁定：v6.1.1` + `✓ superpowers v6.1.1 = 远端最新 v6.1.1`
- 总计 PASS 数 +1

- [ ] **Step 6: 模拟未锁定场景**

Run:
```bash
# 临时去掉 #v6.1.1
sed -i '' 's|superpowers.git#v6.1.1|superpowers.git|' /Users/edy/.config/opencode/opencode.json
make check 2>&1 | grep -A 2 "13/13"
# 应输出 "未锁定版本" 警告
# 改回
sed -i '' 's|superpowers.git"|superpowers.git#v6.1.1"|' /Users/edy/.config/opencode/opencode.json
```

- [ ] **Step 7: 模拟落后场景**

Run:
```bash
sed -i '' 's|superpowers.git#v6.1.1|superpowers.git#v6.0.0|' /Users/edy/.config/opencode/opencode.json
make check 2>&1 | grep -A 2 "13/13"
# 应输出 "有新版 v6.0.0 → v6.1.1" 警告
# 改回
sed -i '' 's|superpowers.git#v6.0.0|superpowers.git#v6.1.1|' /Users/edy/.config/opencode/opencode.json
```

- [ ] **Step 8: Commit**

```bash
cd /Users/edy/.config/opencode
git add scripts/check.sh
git commit -m "feat(check): 集成 section 13 - superpowers 版本检测（软失败）"
```

---

## Task 4: Makefile 加 upgrade-superpowers target

**Files:**
- Modify: `Makefile`（在 `upgrade:` target 之后插入）

**Interfaces:**
- Consumes: `scripts/upgrade-superpowers.sh`（Task 2 产物）

- [ ] **Step 1: 读 Makefile 当前 upgrade target**

Run: `grep -n "^upgrade\|^update" /Users/edy/.config/opencode/Makefile`
找到 `upgrade:` target 的行号。

- [ ] **Step 2: 在 upgrade target 之后插入新 target**

定位到 `upgrade:` target 块结束（通常是空行或下一个 target）。插入：

```makefile
upgrade-superpowers: ## 升级 superpowers plugin 到远端最新 tag（查远端 → 改 opencode.json → 清缓存）
	@bash scripts/upgrade-superpowers.sh
```

- [ ] **Step 3: 验证 help 列表里出现新 target**

Run: `cd /Users/edy/.config/opencode && make help 2>&1 | grep superpowers`
Expected: 出现 `upgrade-superpowers  升级 superpowers plugin...`

- [ ] **Step 4: 跑一次确认能执行（当前已是最新，应输出"已是最新"）**

Run: `cd /Users/edy/.config/opencode && make upgrade-superpowers`
Expected: 输出 `✓ 已是最新，无需升级`

- [ ] **Step 5: Commit**

```bash
cd /Users/edy/.config/opencode
git add Makefile
git commit -m "feat(make): 新增 upgrade-superpowers target"
```

---

## Task 5: 集成验证

**Files:** 无修改，仅跑命令

- [ ] **Step 1: 完整跑一次 make check**

Run: `cd /Users/edy/.config/opencode && make check`
Expected: 13/13 全跑，critical 全绿，section 13 显示 `✓ superpowers v6.1.1 = 远端最新 v6.1.1`。

- [ ] **Step 2: 跑 make upgrade-superpowers（应是最新）**

Run: `cd /Users/edy/.config/opencode && make upgrade-superpowers`
Expected: `✓ 已是最新，无需升级`，不改任何文件。

- [ ] **Step 3: 模拟断网（关闭 wifi 或断网络）**

物理断网或：`sudo ifconfig en0 down`（谨慎，影响其他应用）
跑 `make check`：
Expected: section 13 输出 `⚠️  superpowers 远端检测跳过（无网络或仓库不可达）`，**不阻断**（前 12 section 仍全绿，最终 exit 0）。

恢复网络：`sudo ifconfig en0 up`

- [ ] **Step 4: JSON 合法性最终校验**

Run: `node -e "JSON.parse(require('fs').readFileSync('/Users/edy/.config/opencode/opencode.json','utf8')); console.log('✓ JSON 合法')"`
Expected: `✓ JSON 合法`

- [ ] **Step 5: tui.json 同步检查（确认 plugin 字段一致）**

Run: `cd /Users/edy/.config/opencode && make tui-sync`
Expected: `✓ opencode.json 与 tui.json plugin 字段一致`

如果 tui.json 也有 superpowers 字符串且不一致，需要同步：
```bash
sed -i '' 's|superpowers.git"|superpowers.git#v6.1.1"|' /Users/edy/.config/opencode/tui.json
```

- [ ] **Step 6: 无 commit（验证 task 不产生改动）**

Run: `git status`
Expected: nothing to commit（如果 Step 5 改了 tui.json，需要单独 commit tui.json）

---

## Task 6: 更新文档

**Files:**
- Modify: `docs/reference.md`
- Modify: `README.md`

- [ ] **Step 1: 在 docs/reference.md 适当位置加新小节**

定位：在 "## plugin `@latest` 漂移检测（`make check` 第 7 项）" 小节之后插入：

```markdown
## plugin git 源版本锁定（superpowers）

`opencode.json` 第 3 行的 superpowers plugin 用 git 源（`superpowers@git+https://...`），不像 `@latest` 的 npm 包有 npm registry 做 semver 网关。为保证可复现性，**显式锁定到 git tag**：

```json
"superpowers@git+https://github.com/obra/superpowers.git#v6.1.1"
```

**为什么锁 tag 而非 commit SHA**：obra 维护规范的 semver tag（v3.1.0 → v6.1.1），可读性远好于 SHA；升级时一眼能看出当前锁的版本。

**`make check` 第 13 项** 会检测：
- opencode.json 是否锁定版本（无 `#vX.Y.Z` 时警告「未锁定」）
- 远端是否有比本地新的 tag（有时警告「有新版 → 运行 make upgrade-superpowers」）
- 无网络时软失败（仅警告「跳过」，不阻断）

**升级流程**：
```bash
make upgrade-superpowers   # 查远端最新 → 改 opencode.json → 清缓存 → 提示重启
```

升级后必须**重启 opencode**，因为 plugin 在启动时加载到内存，运行时不会重读。
```

- [ ] **Step 2: 在 README.md 的 plugin 表格里更新说明**

定位 plugin 表格（通常在 README 顶部"包含什么"段）：

修改前（如有类似行）：
```
| `opencode.json` | provider 定义（火山引擎 8 模型）+ 8 MCP 条目 + 3 plugin + LSP + permission |
```

修改后（明确提到 superpowers 锁定）：
```
| `opencode.json` | provider 定义（火山引擎 8 模型）+ 8 MCP 条目（7 启用 + chrome-mcp 默认禁用）+ 3 plugin（superpowers 锁 #v6.1.1）+ LSP + permission |
```

（如该行已经描述了 plugin 数量，只需追加"superpowers 锁 #v6.1.1"即可。）

- [ ] **Step 3: 跑 make check 最终验证（13/13 全绿）**

Run: `cd /Users/edy/.config/opencode && make check`
Expected: 13/13 全绿，无 warning 新增。

- [ ] **Step 4: Commit**

```bash
cd /Users/edy/.config/opencode
git add docs/reference.md README.md
git commit -m "docs: superpowers 版本锁定机制说明（reference + README）"
```

---

## Task 7: 最终验证

**Files:** 无修改，仅最终确认

- [ ] **Step 1: git log 查看 commit 序列**

Run: `cd /Users/edy/.config/opencode && git log --oneline -6`
Expected 4 个新 commit（按 Task 1/2/3+4/6 顺序，Task 5 无 commit）：
```
xxxxxxx docs: superpowers 版本锁定机制说明（reference + README）
xxxxxxx feat(make): 新增 upgrade-superpowers target + section 13 集成
xxxxxxx feat(scripts): 新增 upgrade-superpowers.sh 一键升级脚本
xxxxxxx feat(plugin): superpowers 锁定到 #v6.1.1（tag 版本管理）
```

- [ ] **Step 2: 完整体检最终确认**

Run: `cd /Users/edy/.config/opencode && make check`
Expected: 13/13 全绿，所有 critical 项 PASS，section 13 显示最新版本一致。

- [ ] **Step 3: 跑 make help 确认 upgrade-superpowers 出现**

Run: `cd /Users/edy/.config/opencode && make help | grep -i superpowers`
Expected: 出现 `upgrade-superpowers` 行。

- [ ] **Step 4: 准备 push（仅告知用户，不自动 push）**

告知用户：「4 个 commit 已就绪，是否 push 到远程？」

---

## Self-Review

### 1. Spec 覆盖

| Spec 要求 | 实现 Task |
|---|---|
| opencode.json 加 `#v6.1.1` | Task 1 |
| 写升级脚本 | Task 2 |
| make check 加检测（spec 说独立脚本，调整为 section 13 集成）| Task 3 |
| Makefile 加 upgrade-superpowers target | Task 4 |
| 错误处理矩阵（无锁定 / 无网 / 落后 / 异常）| Task 3 step 5/6/7 |
| 4 种测试场景（落后 / 未锁定 / 断网 / 干跑）| Task 3 + Task 5 |
| docs/reference.md 新增小节 | Task 6 |
| README.md 同步 | Task 6 |

**调整说明**：spec 写的是独立 `scripts/check-superpowers.sh`，plan 改为集成进 `scripts/check.sh` section 13——更符合现有 plugin 漂移检测（section 7）的模式，避免新增冗余脚本。

### 2. Placeholder 扫描

- ✅ 无 TBD/TODO/«implement later»
- ✅ 所有代码块是完整可执行代码，不是「类似 Task N」
- ✅ 所有命令有 expected output

### 3. 类型一致性

- 函数名 `ok()` / `warn()` / `fail()` / `wfail()` 全程一致（复用 check.sh 顶部定义）
- 变量命名一致：`SP_LOCKED` / `SP_REMOTE`（section 13）、`CURRENT` / `LATEST`（upgrade 脚本）
- 路径写法一致：脚本里用相对 `opencode.json`（依赖 `cd "$(dirname "$0")/.."`）

### 4. 风险检查

- ✅ macOS 兼容：`sed -i ''`、`awk`、`grep -oE`、`sort -t.`
- ✅ 不引入新依赖（无 jq、无 Python）
- ✅ 软失败：所有检测路径都 `warn()` + 继续执行，无 exit 1 阻断 make check
- ✅ upgrade 脚本用 `set -e`：升级失败会立即停止（这是 upgrade 命令该有的行为，不是 check）
