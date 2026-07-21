# OMO 日常开发高效使用指南

> 基于 `oh-my-openagent.json` + `opencode.json` 实际配置。配置变更后请重新核对。
> 配置事实均带 `file:line` 证据，便于审计。

---

## 一、核心心智模型

你是调度官，不是执行者。默认走 sisyphus（主调度），它自动委派给对的专家。

### 模型分层（`oh-my-openagent.json` agents + categories）

| 层级 | 模型 | reasoningEffort | 并发上限 | 角色 |
|---|---|---|---|---|
| 重型推理 | GLM-5.2 (zhipu) | max | **5** | sisyphus / oracle / prometheus / momus / metis / plan / ultrabrain / deep / writing |
| 编码实现 | GLM-5.2 (zhipu) | max | **5** | atlas / sisyphus-junior / unspecified-high / artistry |
| 检索轻量 | DeepSeek V4 Flash (volc) | low | **5** | librarian / explore / unspecified-low |
| 多模态 | GLM-5v-Turbo (zhipu) | — | — | multimodal-looker / visual-engineering |
| 快通道 | DeepSeek V4 Flash (volc) | minimal | **5** | quick |
| 重型推理(fallback) | DeepSeek V4 Pro (volc) | — | **3** | atlas/sisyphus-junior 等的 fallback 首位 |

> **并发精细值**（`oh-my-openagent.json:39-50` `background_task.modelConcurrency`）：
> `deepseek-v4-pro: 3` / `deepseek-v4-flash: 5` / `glm-5.2: 5` / `glm-5-turbo: 3`。
> `providerConcurrency` 各 provider 5（L36-37）。`defaultConcurrency: 5`（L34）。
> **含义**：pro/turbo 模型并发被压到 3（rate-limit 保护），并行委派时这两个模型可能排队。

### Fallback 三参数（`oh-my-openagent.json:19-26` `runtime_fallback`）

- `max_fallback_attempts: 4` — 最多重试 4 次
- `cooldown_seconds: 60` — 失败后冷却 60 秒
- `timeout_seconds: 60` — 单次请求超时 60 秒
- `notify_on_fallback: true` — 触发 fallback 时弹 toast 提醒（**注意字段名是 `notify_on_fallback`，不是 `notify_on_footer`**）

> GLM-5.2 宕机 → 火山 GLM-5.2 → kimi-k2.6 → doubao-seed-2.0-pro（自动）。

---

## 二、关键词触发速查（最高频交互入口）🔥

> **核心特性**：`oh-my-openagent.json:305-307` `keyword_detector.enabled_expansions`
> 在普通对话里说这些词，**自动展开为对应模式**，无需手动 `/` 命令。

| 关键词 | 触发 | 适用场景 |
|---|---|---|
| `ultrawork` | ULTRAWORK 模式（最高精度 + 严格 output spec） | 实现需求明确、要求一次做对 |
| `team` | Team Mode（多 agent 协作） | 多模块并行、需不同角色 |
| `hyperplan` | 对抗式多 agent 规划（5 个 hostile critic 交叉批判） | 高风险架构决策、需求模糊 |
| `hyperplan-ultrawork` | 先 hyperplan 规划，再 ultrawork 执行 | 复杂工程端到端 |

> **用法示例**：直接打字「ultrawork 帮我把这个模块重写」即可，无需 `/ulw-loop`。

---

## 三、日常场景速查

### 场景 1：修 bug
- **小 bug**：直接描述 + 报错栈 → sisyphus 自诊自修
- **顽固 bug**（2 次修不好）：触发 `/debugging` 假设驱动循环
- **运行时崩溃**：「attach debugger」→ gdb/lldb/node inspect
- **MCP 加持**：报错截图 → 直接粘贴，`zai-mcp-server` 自动 OCR + 诊断

### 场景 2：实现新功能
- **单文件小改**：直接说 → sisyphus 自处理
- **跨文件中等**：直接说 → 委派 sisyphus-junior（deep category）
- **复杂多步**（5+ 步）：先 `/ulw-plan` 规划 → `/start-work` 执行
- **何时不用 /ulw-plan**：路径明确的修复、单文件改动、文档编辑——开销大于收益

### 场景 3：提交代码
- `/git-master` → atomic commit + repo style 匹配 + footer（`commit_footer: true` + `include_co_authored_by: true`，L281-282）

### 场景 4：审查工作
- `/review-work` → 5 路并行子 agent（目标/质量/安全/QA/上下文）
- **何时不用**：单文件 typo、纯文档、< 30 分钟的小改——5 个并行 agent 的 token + 时间成本不值
- **何时必用**：3+ 文件、安全/迁移/性能相关、30+ 分钟工作量

### 场景 5：查资料
- **本仓库**：描述目标 → 自动委派 explore（后台并行搜，别自己 grep）
- **外部文档/库**：「XXX 库怎么用」→ 自动委派 librarian
- **联网搜索**：`web-search-prime` MCP 实时搜（智谱直连，无 API key 加配置）
- **GitHub 仓库阅读**：`zread` MCP 直接读 repo 文件结构 + 源码
- **代码图谱**：`codegraph` MCP 提供 call graph（首次需 `codegraph serve --mcp` 启动）

### 场景 6：架构决策
- 「咨询 oracle」→ 高质量推理 + tradeoff
- **何时不用 oracle**：trivial 决定、能从代码推断的、单文件改动——oracle 是昂贵模型
- **何时必用**：2 次修复失败、多系统 tradeoff、不熟悉的代码模式

### 场景 7：飞书（27 个 lark skill）
- 「发消息给 XXX」→ lark-im
- 「今天日程」→ `/lark-workflow-standup-report`
- 「整理本周会议」→ `/lark-workflow-meeting-summary`
- 「读文档 https://...」→ lark-doc（按 URL 路径自动路由）
- **创建自定义飞书 skill**：`/lark-skill-maker` 封装重复操作

### 场景 8：安全审计
- `/security-research` → 3 漏洞猎手 + 2 PoC 工程师并行审计

### 场景 9：前端 / UI
- `/frontend`（**强制**：任何 UI/UX/styling 工作）→ anti-slop taste router + Lighthouse 审计
- **完成后**：`/visual-qa` 视觉回归验证（截图 diff）
- **MCP 加持**：`mermaid` MCP 渲染架构图（`/mermaid_preview`）

### 场景 10：长任务 / 批量
- `/ralph-loop` → 自引用循环直到完成
- `/ulw-loop` → ultrawork 模式（更高精度，但更慢）

### 场景 11：清理 / 重构
- `/remove-ai-slops` → 锁行为（先写回归测试）→ 清理 AI 代码味 → 验证
- `/refactor` → LSP + AST-grep 智能重构（安全重命名、extract）
- `/handoff` → 跨 session 交接（生成长期 handoff 文档）

---

## 四、效率技巧

### 1. 并行委派免费
`background_task.defaultConcurrency: 5`（L34）。最多 5 个后台 agent 同跑。
- 说「并行探索这几个方向」→ sisyphus 自动 fan-out
- 自己也能手动：`task(subagent_type="explore", run_in_background=true, ...)`

### 2. Team Mode（`team_mode.enabled: true`，L7-18）
- `max_parallel_members: 4` / `max_members: 8`
- 适用：多模块并行开发、planner + builders + reviewer 协作
- **何时不用**：单文件改动、路径明确的修复、< 5 步的任务——team spec 创建开销大于收益

### 3. 记忆系统后台运行
- `opencode-mem` 用 GLM-5-turbo 自动捕获对话成果（`autoCaptureEnabled: true`）
- `injectProfile: true` → 用户偏好画像注入到每轮
- 查看：http://127.0.0.1:4747（Web UI，`webServerEnabled: true`）
- 你不用管它——它管你

### 4. TDD 是默认的（`sisyphus_agent.tdd: true`，L70）
- 实现任务默认走 RED→GREEN→REFACTOR
- **豁免场景**：纯 prompt 文本、注释、版本号 bump、rename-only、一次性脚本、配置文件——明确说「不要 TDD」

### 5. 权限安全网（43 条 bash deny，`opencode.json:206-248`）
- 拦：sudo / rm -rf / kill / node -e / python -c / curl POST / force push / git reset --hard / npm publish / docker / curl|sh / eval / .env / ~/.ssh / ~/.aws / ~/.zshrc 等敏感文件 / 私钥读取
- 放：chmod / chown / git restore / git config alias（日常开发常用，但需注意 chmod 可改 ~/.ssh 权限、git restore 会丢未提交工作）
- 放手让 agent 跑命令

### 6. LSP 工具链（`opencode.json:108  "lsp": true`）
- 自动检测内置 LSP（TS/Pyright/gopls/ESLint）
- `lsp_diagnostics` / `lsp_goto_definition` / `lsp_find_references` / `lsp_rename` 全可用
- 配合 `/refactor`（AST-grep）做安全重命名

### 7. hashline_edit（`oh-my-openagent.json:3  "hashline_edit": true`）
- 编辑工具用 `LINE#ID` 格式精确定位行
- 你看到的文件内容每行带 hash 标识——这是特性，不是 bug

### 8. ⚠️ aggressive_truncation 副作用（`oh-my-openagent.json:55`）
- `experimental.aggressive_truncation: true` 会激进截断上下文
- **副作用**：长 session 中可能丢失关键历史信息
- **缓解**：重要上下文主动重述；感觉响应变慢或信息丢失时开新 session

### 9. dynamic_context_pruning（`oh-my-openagent.json:56-77`）
- `enabled: true`（动态上下文裁剪已启用）
- `protected_tools` 保护 task/todowrite/lsp_rename/session_read 等不被裁剪；`turn_protection` 保护最近 3 轮；策略含 deduplication / supersede_writes / purge_errors

---

## 五、避坑指南

| ❌ 不要 | ✅ 应该 | 原因 |
|---|---|---|
| 自己 grep 搜代码 | 描述目标让 sisyphus 委派 explore | explore 并行、跨文件、更深 |
| 用 `quick` 做前端 | 用 `/frontend` 或 visual-engineering | 前端有专门模型 + taste router |
| 复杂任务直接开干 | 先 `/ulw-plan` | 5+ 步无 plan 会返工 |
| 单文件 typo 跑 `/review-work` | 直接改 + 跑 lsp_diagnostics | 5 agent 审查对 1 行改动是浪费 |
| 简单问题咨询 oracle | 直接问 sisyphus | oracle 是昂贵模型，留给难题 |
| 单文件修复起 team_mode | 直接做 | team spec 创建开销 > 收益 |
| 所有改动强制 TDD | 文档/配置/脚本明确「不要 TDD」 | 强制测试拖慢非行为改动 |
| 长会话死撑 | 感觉变慢就 `/handoff` 或开新 session | aggressive_truncation 可能丢信息 |
| 手动写 commit | `/git-master` | atomic + style 匹配 |
| 忘记 skills 存在 | 遇事先想 skill | 你装了 40+ skill |
| 期望自动更新 | 定期 `make update` | `disabled_hooks` 禁了 auto-update-checker（L285-287） |

---

## 六、维护提醒

### `disabled_hooks: ["auto-update-checker"]`（`oh-my-openagent.json:285-287`）
**opencode 不会自动检查更新**。需主动维护：

| 周期 | 动作 |
|---|---|
| 每周 | `make update` → 清 node_modules 重装 + mem 软链 |
| 每月 | `npm view oh-my-openagent version` 对比本地，参考 README「如何升级 oh-my-openagent 主版本」章节 |
| 升级 OMO 后 | **必跑** `make check` 验证 |

### `model_capabilities.auto_refresh_on_start: true`（L28-32）
首次启动会刷新模型能力探测（`refresh_timeout_ms: 5000`），冷启动稍慢属正常。

---

## 七、一日工作流模板

```
早上：
  「/lark-workflow-standup-report」              ← 日程+待办
  「make update」                                ← 周维护（disabled_hooks 不自动更新）

开发：
  简单任务：「实现 XXX」                          ← sisyphus 自动路由
  复杂任务：「ultrawork 实现 XXX」                ← 关键词触发高精度模式
            或「/ulw-plan 规划 XXX」→「/start-work」
  前端：    「/frontend 重设计 XXX」              ← 专用通道
  难题：    「咨询 oracle，XXX 怎么选」           ← 重型推理

提交：
  「/git-master 提交」

审查（仅大改）：
  「/review-work」

下班：
  「/lark-workflow-meeting-summary 整理今天会议」

跨天交接：
  「/handoff」                                   ← 生成长期 handoff 文档
```

---

## 八、配置事实索引（审计用）

| 配置项 | 文件:行 | 当前值 |
|---|---|---|
| 11 agents | `oh-my-openagent.json:90-214` | sisyphus/prometheus/plan/oracle/metis/momus/atlas/librarian/explore/multimodal-looker/sisyphus-junior |
| 8 categories | `oh-my-openagent.json:215-296` | visual-engineering/ultrabrain/artistry/deep/quick/unspecified-low/unspecified-high/writing |
| team_mode | `oh-my-openagent.json:7-18` | enabled, max_parallel_members=4, max_members=8 |
| background_task | `oh-my-openagent.json:33-51` | defaultConcurrency=5, providerConcurrency 各 5, modelConcurrency 精细值见上 |
| runtime_fallback | `oh-my-openagent.json:19-26` | 4 retries / 60s cooldown / 60s timeout / notify_on_fallback=true |
| experimental | `oh-my-openagent.json:52-78` | task_system=true / preemptive_compaction=true / aggressive_truncation=true / dynamic_context_pruning.enabled=true |
| sisyphus_agent | `oh-my-openagent.json:79-85` | tdd=true / planner_enabled=true / replace_plan=true |
| keyword_detector | `oh-my-openagent.json:305-307` | ultrawork/team/hyperplan/hyperplan-ultrawork |
| disabled_hooks | `oh-my-openagent.json:302-304` | auto-update-checker |
| git_master | `oh-my-openagent.json:297-301` | commit_footer=true / include_co_authored_by=true |
| compaction | `opencode.json:112-114` | auto=true |
| lsp | `opencode.json:108` | true（自动检测） |
| permission.bash | `opencode.json:205-258` | 52 条规则（1 default allow + 2 force-with-lease allow + 49 deny，含 rm/docker 危险操作白名单） |
| permission.read | `opencode.json:184-204` | 19 条规则（2 allow + 17 deny，含私钥保护） |
| MCP 启用 | `opencode.json:59-109` | zai/web-search-prime/web-reader/zread/mermaid/codegraph/dbx（7 个启用，chrome-mcp disabled） |
| opencode-mem | `opencode-mem.jsonc` | autoCapture=true / injectProfile=true / Web UI :4747 |

---

> **反馈循环**：配置变更后跑 `make check` 验证，然后 `git diff USAGE.md` 看是否需同步更新本指南。
