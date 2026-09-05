# 参考手册

> 配置文件字段地图、运行机制说明、升级流程、信任边界。配置审查和故障定位时用。

## 配置文件结构

> 字段地图，帮你快速定位配置。详细字段值请直接看源文件，本文档不逐字段穷举。

### `opencode.json`（opencode 主配置）

| 类别 | 关键字段 | 说明 |
|---|---|---|
| **插件/扩展** | `plugin` / `mcp` / `lsp` | 3 plugin + 7 MCP + LSP（true = 自动检测内置） |
| **模型路由** | `model` / `small_model` / `enabled_providers` | 智谱单栈：glm-5.3 主 + glm-5.3-flash 作 small；`enabled_providers` 白名单仅 zhipuai-coding-plan（本体层硬过滤，与 OMO 层 disabled_providers 双保险；火山引擎已停订，provider 块已删） |
| **行为开关** | `default_agent` / `share` / `autoupdate` / `compaction` | build / manual / true(patch 自动,minor/major 仅通知) / auto |
| **I/O 限制** | `tool_output` / `attachment` | 2000 行/512KB / 图像 1600x1600 |
| **安全** | `permission.read` / `permission.bash` / `watcher.ignore` | deny 列表 + 文件监听忽略 |

### `~/.omo/omo.jsonc`（OMO 统一配置）

| 类别 | 关键字段 | 说明 |
|---|---|---|
| **角色定义** | `agents` / `categories` | 12 agent + 8 category + fallback 链（详见「角色路由速查」） |
| **架构开关** | `team_mode` / `tmux` / `sisyphus_agent` / `default_mode` | 多 agent 协作 / TUI 可视化 / planner / ultrawork 默认值 |
| **容错与性能** | `runtime_fallback` / `model_fallback` / `background_task` / `model_capabilities` | 4 次重试 / 跨 provider fallback / 并发控制 / 能力探测 |
| **实验特性** | `experimental` / `keyword_detector` / `disabled_hooks` | task_system / context_pruning / intent 关键词 / hook 黑名单 |
| **编码习惯** | `i18n` / `hashline_edit` / `git_master` | zh / 行内 hash 编辑 / commit footer |

### `tui.json`（TUI 专用配置）

| 字段 | 说明 |
|---|---|
| `plugin` | TUI 模式加载的 plugin（与 `opencode.json` 保持同步；升级 plugin 时双 json spec 必须同批核对，防 TUI 域旁路旧版——check §14 的 pluginSpec/memSpecSync 双守卫拦截） |
| `theme` / `scroll_speed` / `mouse` | tokyonight / 8 / true |

### `opencode-mem.jsonc`（本地持久记忆配置，**不入 git**）

| 字段类别 | 说明 |
|---|---|
| **auto-capture** | `memoryProvider` / `memoryModel` / `memoryApiUrl` / `memoryApiKey`（智谱直连） |
| **存储** | `storagePath` / `embeddingModel` / `maxVectorsPerShard`（本地默认值） |
| **Web UI** | `webServerEnabled` / `webServerPort` / `webServerHost`（4747 / 127.0.0.1） |
| **用户画像** | `userProfileAnalysisInterval` / `injectProfile`（默认 10 / true） |

> **迁移原则**：配置文件都进 git，新机器 `git clone` + `make install` 即可。`opencode-mem.jsonc` 不入 git（由 `make mem` 从模板生成，保持 `.template` 作权威源），避免本地实例澉移污染 git 历史。

## 关于 `prompt_append` × 20（全覆盖）

> 20 个 agent/category（12 agent + 8 category）都挂了 `prompt_append`（`file://~/.config/opencode/.opencode/lang-zh.md`），看似 DRY 违反，实则是**必要的**。

**为什么不依赖 `i18n.locale: "zh"`？**
- OMO 的 `i18n.locale` 只管 **toast/UI 文案**翻译（`locales[currentLang][key]`，如 `toast.fallback_runtime`）
- LLM 回答什么语言**完全不由 i18n 控制**，只由 system prompt / prompt_append 决定
- 源码证据：`locales` 对象全是 toast key；`prompt_append` 被合并进 system prompt（OMO dist/index.js 搜索 `locales` / `prompt_append` 定位）

**优化方向（已实施）**：
- prompt_append 支持 `file://` 协议（OMO dist/index.js 搜索 `file://` 定位）
- 已提取到 `.opencode/lang-zh.md`，用 `prompt_append: "file://~/.config/opencode/.opencode/lang-zh.md"` 单源引用
- **必须用 `~/` 绝对锚定**，不能用相对路径 `file://.opencode/...`：相对路径依赖 opencode 启动 cwd，当 cwd ≠ `~/.config/opencode/`（如从家目录启动）时 `resolvePromptAppend` 会解析到错误位置并静默失败，agent system prompt 会嵌入 `[WARNING: Could not resolve file URI]` 而非中文指令——上游支持 tilde 展开见 `resolve-file-uri.ts:30` + 测试 `resolve-file-uri.test.ts:76`（issue #4593）

**为什么不能收敛为「全局一次注入」（2026-09-05 T11 实证）**：

- `opencode.json` 的 `instructions` 数组（instructions.md 3138B + dbx.md 3061B）只注入**主会话** system prompt，**不注入 task/subagent 会话**——subagent 系统提示中两者内容实测缺失（2026-09-05 以 category subagent 会话对照验证）。若把 `lang-zh.md` 从 20 处 `prompt_append` 收敛进 instructions 数组，所有 subagent（explore/librarian/category delegate 等）的中文约束即失效
- `prompt_append` 注入形态：OMO `resolvePromptAppend`（dist/index.js ~L159551）把 `file://` URI 读成**文件正文**拼在 agent prompt 尾部；20 处引用是「每个 agent 定义各带一份」，**同一 session 只注入一份**，不存在 20 份叠加——重复的成本是每个被创建的 subagent session 各带一份（2058B ≈ 0.9k token），不是乘以 20
- 主会话的轻微重复（instructions.md 语言简版 ~600B + lang-zh.md 完整版 2058B）是有意设计：简版全局兜底、完整版 agent 级强制，见 instructions.md L14 的交叉引用

## 超时字段作用域对照

> 5 个超时相关字段分散在 opencode.json 和 ~/.omo/omo.jsonc，作用域完全不重叠。配置审查时必读。

| 字段 | 文件 | 作用域 | 触发动作 | 源码证据 |
|---|---|---|---|---|
| `monitor.max_runtime_ms` (OMO 默认 1800000=30min，未显式覆写) | ~/.omo/omo.jsonc | **外部子进程**（monitor 启动的 shell command） | setTimeout 强制 SIGTERM 杀子进程 | `spawnMonitorProcess` 函数（OMO dist/index.js） |
| `babysitting.timeout_ms` (300000=5min) | ~/.omo/omo.jsonc | **主会话 idle 检测**（`session.idle` 事件后） | 给用户发提醒（不杀进程） | `unstable-agent-babysitter` hook（OMO dist/index.js） |
| `runtime_fallback.timeout_seconds` (60) | ~/.omo/omo.jsonc | **单 session 单次调用**（含主模型 + fallback 累计） | 触发 fallback 切换 | `prepareFallback` 函数（OMO dist/index.js） |
| `experimental.mcp_timeout` (60000) | opencode.json | **单次 MCP 工具调用**（网络超时） | MCP 调用失败，agent 收到错误 | opencode 本体字段 |
| `model_capabilities.refresh_timeout_ms` (5000) | ~/.omo/omo.jsonc | **启动时模型能力探测**（一次性） | 跳过刷新，用缓存元数据 | `model_capabilities` 刷新逻辑（OMO dist/index.js） |

**关键区分**：
- `monitor.max_runtime_ms` 是**子进程硬超时**（kill），`babysitting.timeout_ms` 是**主会话 idle 提醒**（nudge）。两者不冲突，monitor 跑 30min 时 babysitting 不会杀它
- `runtime_fallback.timeout_seconds` 是单 session 累计（含主模型首次失败 + 所有 fallback 尝试），`max_fallback_attempts=4` 意味着「主失败 + 3 fallback = 4 次」

## experimental 命名空间归属澄清

> `opencode.json` 和 `~/.omo/omo.jsonc` 都有 `experimental` 块，但归属完全不同。

| 字段 | 归属 | 说明 |
|---|---|---|
| `experimental.batch_tool` | opencode 本体 | 批量工具调用 |
| `experimental.continue_loop_on_deny` | opencode 本体 | 拒绝后继续循环 |
| `experimental.mcp_timeout` | opencode 本体 | 全局 MCP 超时 |
| `experimental.policies` | opencode 本体 | provider 访问策略（本项目未启用，改用 OMO `disabled_providers`） |
| `experimental.task_system` | OMO 注入 | task 跟踪系统 |
| `experimental.preemptive_compaction` | OMO 注入 | 预防性压缩 |
| `experimental.aggressive_truncation` | OMO 注入 | 激进截断 |

> 配置审查时先看字段在哪一边：opencode 本体字段在 `opencode.json` 写一次就生效；OMO 注入字段在 `~/.omo/omo.jsonc`，opencode 本体不识别。

## 功能开关速查

| 功能 | 配置位置 | 状态 |
|---|---|---|
| LSP 工具链（`lsp_diagnostics` / `lsp_goto_definition` / `lsp_find_references` / `lsp_rename`） | `opencode.json` → `"lsp": true` | ✅ 已启用（自动检测内置 LSP） |
| opencode-mem 本地持久记忆 | `opencode.json` plugin 字段 + `opencode-mem.jsonc` | ✅ 已启用（智谱 glm-5.3-flash auto-capture） |
| 7 个 MCP（智谱 web 工具 / mermaid / codegraph / dbx，全部启用） | `opencode.json` mcp 字段 | ✅ 已启用（另有 4 个插件注入：websearch / context7 / grep_app / lsp） |
| permission 加固（read + bash + edit 三层 deny，92 条，含裸解释器 sh/bash/zsh、stdin 模式、`eval` / `: > .env*` / `: > .ssh/*` / `: > .aws/*`） | `opencode.json` permission.{read,bash,edit} | ✅ 已启用（护栏非防线，见「shell 权限信任边界」） |
| MCP 供应链钉版（npx 通道：`@z_ai/mcp-server@0.1.5` 精确 / `@dbx-app/mcp-server@0.4` minor；全局 bin：check 第 4 项版本比对） | `opencode.json` mcp 字段 + check.sh 常量 | ✅ 三通道分层（remote URL 豁免） |
| Web UI（查看记忆） | `opencode-mem.jsonc` webServerEnabled | ✅ http://127.0.0.1:4747 |
| 一键安装 / 体检 / 更新 | `Makefile` + `scripts/*.sh` | ✅ `make install` / `make check` / `make update` |
| **monitor 后台监控**（agent 能 watch dev server / test runner / build log） | `~/.omo/omo.jsonc` → `monitor.enabled=true`（idle 模式） | ✅ 已启用 |
| **goal 迭代上限**（防 goal 失控烧钱） | `~/.omo/omo.jsonc` → `goal.default_max_iterations=100` | ⚠️ enabled=false（仅 cap 预留） |
| **babysitting 超时**（适配 GLM-5.3 max reasoning 首响应延迟） | `~/.omo/omo.jsonc` → `babysitting.timeout_ms=300000` | ✅ 5min（默认 2min） |
| **comment_checker**（中文注释质量检查） | `~/.omo/omo.jsonc` → `comment_checker.custom_prompt` | ✅ 已启用（中文提示） |
| **disabled_skills**（禁用 playwright/dev-browser/agent-browser） | `~/.omo/omo.jsonc` → `disabled_skills` | ✅ 已禁用不用的内置功能 |
| **experimental.batch_tool + continue_loop_on_deny**（批量工具调用 + 拒绝后继续循环） | `opencode.json` → `experimental` | ✅ 已启用 |
| **海外 provider + zen 防误用**（deny openai/anthropic/google/opencode；opencode=zen 未认证，防 fallback 选入后 Model not found 4 连失败） | `~/.omo/omo.jsonc` → `disabled_providers` | ✅ 已启用（OMO 层过滤，替代原 experimental.policies） |
| **experimental.mcp_timeout**（全局 MCP 超时 60s，宽松适配远程接口） | `opencode.json` → `experimental.mcp_timeout=60000` | ✅ 已启用 |
| **compaction.prune + tail_turns**（自动修剪旧工具输出 + 保留近 6 轮） | `opencode.json` → `compaction` | ✅ prune=true, tail_turns=6 |
| **formatter**（启用内置格式化器，需项目装 prettier/dprint） | `opencode.json` → `formatter=true` | ✅ 已启用（检测不到则 no-op） |
| **instructions**（项目级系统提示补充，含 DBX 连接字典 + 安全护栏） | `opencode.json` → `instructions: ['{file:~/.config/opencode/.opencode/instructions.md}', '{file:~/.config/opencode/.opencode/dbx.md}']`（双文件 + 绝对路径） | ✅ 已启用 |

## 角色路由速查

| 场景 | 路由 |
|---|---|
| 主调度 (sisyphus) | GLM-5.3 (zhipu, max) |
| 架构/深度推理 (oracle/prometheus/momus/metis/plan) | GLM-5.3 (zhipu, max) |
| 高难度自主 (ultrabrain/deep) | GLM-5.3 (zhipu, max) |
| 创意/非常规 (artistry) | GLM-5.3 (zhipu, max)（fallback 链 = models 轮转：GLM-5.2 → GLM-5.3） |
| 编码实现 (atlas/sisyphus-junior/unspecified-high) | GLM-5.3 (zhipu, max)（fallback 链 = models 轮转：GLM-5.2 → GLM-5.3） |
| 多模态/前端 (multimodal-looker/visual-engineering) | GLM-5v-Turbo |
| 检索/轻量 (librarian/explore/unspecified-low) | GLM-5-Turbo (medium) |
| 快速执行 (quick) | GLM-5-Turbo (low) |
| 写作 (writing) | GLM-5.3 |

> 全部 holder 的 fallback_models 采用 **models 轮转**（去首项 + 首模型兜底）：任何单模型故障都在智谱栈内闭环重试，永不溢出到硬编码链（glm-5.2-highspeed 因订阅套餐无权限已于 2026-08-17 移出全部路由；硬编码链不检查 disabled_providers 是上游盲区）。多模态组 glm-5v-turbo → glm-4.6v 轮转。单 provider 部署，智谱全栈宕机时无跨厂商兜底（火山引擎已停订）。`max_fallback_attempts=4`；`providerConcurrency zhipuai-coding-plan=3` 仅辖后台任务中无模型级条目的 glm-5.3/glm-5.2（详见 usage.md 并发控制块）。

## team_mode 成本控制

当前 team_mode 配置只显式启用 `enabled: true`，未显式设置 token/cost 上限（`max_members=8`, `max_member_turns=500` 为 OMO 默认值，未显式覆写）。OMO schema 暂不暴露 `max_total_tokens_per_run` 或 `max_cost_cents_per_run` 字段。如需隐性成本控制，可显式下调 `max_member_turns`。

## MCP 数据流向与信任边界

> 处理敏感项目前必读。部分 MCP 接口会把对话/文件内容发到远程服务器。

| MCP 接口 | 类型 | 数据流向 | 信任边界 |
|---|---|---|---|
| `zai-mcp-server` | 本地启动 | 发往智谱 bigmodel.cn（Z_AI_API_KEY 鉴权） | 智谱服务器可见你的提问内容 |
| `web-search-prime` / `web-reader` / `zread` | 远程接口 | 直连 bigmodel.cn | 智谱服务器可见查询/读取内容 |
| `dbx` | 本地启动 | 出网到数据库服务器（按 dbx 客户端连接配置） | 受 dbx 客户端连接配置控制（生产 / 测试 / DTS 分连接管控，见 dbx.md 安全护栏） |
| `mermaid` / `codegraph` | 本地启动 | 本地处理，不出网 | 无远程信任问题 |

> **敏感项目建议**：临时关 `opencode-mem.jsonc` → `autoCaptureEnabled: false`，避免会话要点出网到智谱做元数据推理。

> **dbx.md 暴露面**（2026-09-05 T4 实证，07af51d 已拆分收敛）：`.opencode/dbx.md` 现为 **36 行 stub**（连接名 + 安全护栏 + 查询路由，无 host 无表级拓扑），生产 host 与库表索引已外移至 `.opencode/dbx-topology.md`（按需 read，不入 git，受 .gitignore 保护）。instructions 数组的 `{file:...dbx.md}` **仅注入主会话系统提示**（T11 实证：instructions 数组不进 subagent）；剩余暴露面：stub 的连接名/库名随助手回复与工具调用摘要进入 opencode-mem 2.25.0 分析窗口（128KB 上限，系统提示本身不进窗口）外发 open.bigmodel.cn，且 mem 无内容排除配置项。拆分前田dbx.md 58 行 6 生产 host 全量注入的历史风险已随拆分消除。

### 内置匿名 remote MCP（OMO 4.19.4 自带，opencode.json 不可见）

oh-my-openagent `createBuiltinMcps()` 默认注册三条 remote MCP，不经过 `opencode.json` 的 `mcp` 段——配置文件里看不到，属隐性外部出站依赖（dist/index.js 实证）：

| MCP | 端点 | 鉴权 | 行为细节 |
|---|---|---|---|
| `websearch` | `https://mcp.exa.ai/mcp?tools=web_search_exa` | 匿名；`EXA_API_KEY` 在值时升级 Bearer | 默认 exa 后端。omo 配置 `websearch.provider: "tavily"` **且** `TAVILY_API_KEY` 在值时才切换 `https://mcp.tavily.com/mcp/`（仅设 key 不切换；provider 配了 tavily 但 key 缺失时该 MCP 直接不注册） |
| `context7` | `https://mcp.context7.com/mcp` | 匿名；`CONTEXT7_API_KEY` 在值时升级 Bearer | 库文档查询，查询词出网 |
| `grep_app` | `https://mcp.grep.app` | 匿名（无 key 通道） | 代码模式搜索，搜索串出网 |

当前环境三条全部匿名直连（live omo.jsonc 无 websearch 覆盖，三个 key 均未设）——出站内容对端可见、无账号归因、审计链路里没有凭证记录。禁用通道：omo.jsonc 的 `disabled_mcps` 列表（合法值 `websearch` / `context7` / `grep_app` / `lsp` / `codegraph`）。

### 凭证路径分离（auth.json OAuth vs Z_AI_API_KEY env）

- **主模型链路**：`~/.local/share/opencode/auth.json`（权限 600，仅含 `zhipuai-coding-plan` 一键）——opencode 引擎持有的 OAuth 凭证，所有会话模型请求走它。与本仓库 .gitignore 的 `auth.json` 同名不同物（仓库根不存在该文件）。
- **侧链 API key**（`~/.zshrc` 注入 env）：`Z_AI_API_KEY` 有三个消费方——① `zai-mcp-server`（opencode.json environment 段，`Z_AI_MODE=ZHIPU`）② 智谱 web 工具三条 remote 的 `Authorization: Bearer {env:Z_AI_API_KEY}`（web-search-prime / web-reader / zread）③ opencode-mem 直连分析（`env://Z_AI_API_KEY` → open.bigmodel.cn）。
- 另两密钥单一用途：`FEISHU_APP_SECRET`（lark-cli 系 skill）、`KINGSOFT_DOCS_TOKEN`（kdocs skill）。
- **分离含义**：轮换/撤销 env key 不影响主模型登录（auth.json 独立）；审计出站面时两条凭证链路（OAuth + API key）各自都要过一遍，缺一侧即漏账。

### GUI key 时窗行为（launchctl setenv 的隐式条件）

`~/.zshrc` 末尾的 `launchctl setenv` 仅在 shell 启动时执行——依赖「**开过终端**」这个隐式前提。macOS 重启后到首次打开终端之间的窗口期内，GUI/Dock 启动的 opencode 进程 env 里没有 `Z_AI_API_KEY` / `FEISHU_APP_SECRET`（侧链三消费方 + lark-cli 全部静默降级或报鉴权失败；主模型链路不受影响——auth.json 不经此通道）。`KINGSOFT_DOCS_TOKEN` 无 setenv 行，GUI 域恒不可用（仅终端会话可用）。当前缓解为操作约定：重启后先开一次终端再启 opencode；是否引入 LaunchAgent 登录时自动注入（消除时窗），决策待定。

## 上下文注入量化与 MCP 收敛评估（T11，2026-09-05）

> 实测方法：对 7 个本地/远程 MCP server 发 initialize + tools/list（只读探针，不执行工具），统计 name + description + inputSchema 的 JSON 字符量；token 按 chars/4（英文为主）～ chars/3（混合）区间估算。

### 每 session 常驻注入量化（subagent 口径）

| 注入项 | 覆盖范围 | 实测 chars | token（/4～/3） |
|---|---|---|---|
| MCP 工具定义（opencode.json 7 server，33 工具） | 所有 session 含 subagent | 24639 | 6.2k～8.2k |
| MCP 工具定义（OMO 内置 3 server，4 工具） | 同上 | 8449 | 2.1k～2.8k |
| 外部 skill 描述（54 个 SKILL.md frontmatter） | 同上 | 18318 | 4.6k～6.1k |
| lang-zh.md（prompt_append） | 每个 agent 一份 | 2058 | ~0.9k（中文） |
| instructions.md + dbx.md（instructions 数组） | **仅主会话** | 6199 | 1.5k～2.1k |
| 合计（subagent session） | — | ~53.5k | **~13.4k～18k** |

Wave3 审计「15k+ tokens 常驻」口径成立，但归属需修正：大头是 MCP 工具定义（8.3k～11k）与 skill 描述（4.6k～6.1k），**不是**检索/浏览入口重叠本身。检索/浏览相关（web-search-prime + web-reader + zread + 内置 exa/context7/grep_app）实测合计 12018 chars ≈ 3k～4k token。

### 审计移交两处事实修正

- **zai-mcp-server 无 websearch 工具**：实测 8 工具全为视觉类（ui_to_artifact / extract_text_from_screenshot / diagnose_error_screenshot / understand_technical_diagram / analyze_data_visualization / ui_diff_check / analyze_image / analyze_video，合计 7670 chars），与 OMO 内置 `websearch`（exa 后端）无重叠；analyze_image 与 opencode 内置 `look_at` 部分重叠但粒度不同（精细分析 vs 快速摘要）
- **lang-zh.md 引用是 20 处不是 12 处**：12 agent + 8 category 全挂；且同一 session 只注入一份（见上文 prompt_append 段）

### MCP 保留矩阵（评估结论；配置变更停 G11）

| 功能面 | 保留 | 候选禁用 | 理由 | 禁用损失 | 节省 |
|---|---|---|---|---|---|
| Web 搜索 | web-search-prime + 内置 websearch(exa) 双入口 | 无 | 互补非重叠：prime 强中文/中国区时效（location:cn 默认、recency 过滤、content_size 摘要粒度），exa 强英文语义与 category:people/company 检索；两者免费/付费链路也不同（Z_AI key vs 匿名） | — | 0 |
| 网页阅读 | opencode 内置 webfetch | web-reader（1069 chars） | webfetch 覆盖 URL→markdown/text/html 主路径，免费零依赖 | retain_images / images_summary / links_summary / no_gfm 精细控制 | ~270 token |
| GitHub 仓库阅读 | webfetch（raw.githubusercontent / api.github.com）+ 内置 grep_app | zread（1203 chars） | 结构浏览/单文件读可由 webfetch 可达 | **search_doc（zread.ai 索引的仓库文档/issue 语义搜索）无替代**——按「不删功能」红线默认保留，仅当确认低频可弃才禁 | ~300 token |
| 视觉/图像 | zai-mcp-server 8 工具 | 无 | ui_to_artifact / ui_diff_check / analyze_video 无替代 | — | 0 |
| 库文档 | 内置 context7 | 无 | 唯一入口 | — | 0 |
| 数据库 | dbx 17 工具 | 无 | 生产诊断链路（hooloo 等任务高频） | — | 0 |
| 图表渲染 | mermaid | 无 | 唯一入口 | — | 0 |
| 本地符号索引 | codegraph | 无 | 与 grep/glob 互补（符号级 + 调用路径） | — | 0 |

**结论：无一项可无条件禁用**。可议两项（web-reader / zread）合计上限 ~570 token/session，均有功能损失；lang-zh.md 正文瘦身（删反例对比段可省 ~400 token/session）同理不推荐——few-shot 示例对语言行为校准价值高，且行为退化无法本地验证，违背「宁缺毋滥」。

### G11 待批 diff（若批准两项禁用；不删条目，回退 = 删 `enabled` 行）

```diff
   "web-reader": {
     "type": "remote",
     "url": "https://open.bigmodel.cn/api/mcp/web_reader/mcp",
     "headers": {
       "Authorization": "Bearer {env:Z_AI_API_KEY}"
-    }
+    },
+    "enabled": false
   },
   "zread": {
     "type": "remote",
     "url": "https://open.bigmodel.cn/api/mcp/zread/mcp",
     "headers": {
       "Authorization": "Bearer {env:Z_AI_API_KEY}"
-    }
+    },
+    "enabled": false
   },
```

> 生效条件：改后需重启 opencode（配置非热加载）。zread 的 `search_doc` 损失评估见保留矩阵——若日常确用 zread 浏览未 clone 的仓库，建议只批 web-reader 一项（~270 token）。
## plugin 加载机制与钉版策略（Wave3 闭合 @latest 旁路）

**omo 已钉精确版本**（2026-08-29）：`opencode.json` / `tui.json` 的 plugin spec 为 `oh-my-openagent@4.19.4`（不再是 `@latest`）。

为什么钉版是唯一闭合解：`@latest` 通道下防跳闸/major 检测/自愈三通道全缺——`upgrade.sh` 防跳闸只看 `package.json`，而 opencode 启动时按 spec 从 `~/.cache/opencode/packages/<spec>/` 解析缓存层，npm dist-tag `latest` 一旦切到 5.0，缓存会先于 node_modules 静默跳版。钉版后：缓存目录名即 spec（`oh-my-openagent@4.19.4/`），版本变化必须显式改 spec（`make upgrade` 的 4c 步骤自动同步双文件），配合 check-drift.mjs 的 pluginSpec 一致性守卫（package.json ↔ 双 json spec，失配 critical fail）。

**opencode-mem 已钉 `2.25.0` + 本地 tags 兜底 patch**（2026-09-02）：双 json 的 plugin spec 均为 `opencode-mem@2.25.0`，缓存目录 `~/.cache/opencode/packages/opencode-mem@2.25.0/` 的 `client.js` 带 `PATCH(tags-fallback)` 三层兜底（正文内嵌 `Tags:` 行提取 → type 映射 → 保底），防上游「LLM tags 偶发缺失无兜底入库 → detect 零容忍弹窗」缺陷链。相关资产：`scripts/patch-mem-tags.mjs`（可重放 patch，幂等/锚点校验/语法校验/失败回滚）、`scripts/fix-mem-untagged.mjs`（存量清理，双通道同源强正则）、check §3 pin 缓存+patch 存活检查、install.sh pin-aware 全局装（跟随 spec）。

**升级 runbook（上游发新版时六步）**：① `npm view opencode-mem version` + 读 changelog → ② 判断 tags 缺陷是否已修复（已修复 → 摘 patch 回 `@latest`，流程止于此）→ ③ 未修复则改双 spec（`opencode.json` + `tui.json` 同步，防 TUI 域旁路）→ ④ 清 pin 缓存目录并重启 opencode 重拉 → ⑤ 重放 patch（**前置门槛：diff 新旧 `client.js` 的 `addMemory` 函数体确认上游未在该区间插入新逻辑**，防锚点命中但语义漂移的静默错配）→ ⑥ `make check` 验证（§3 应报 patch 存活）。

`make check` 第 7 项比较：项目软链 `node_modules/opencode-mem`（全局版本，install.sh 按 spec 安装）↔ opencode 缓存目录版本；不一致警告后 `make update` 重装同步。

### 缓存目录残留审计（2026-09-05 T9，全量只读，清理待 G9 批准）

钉版切换后的存量残留盘点（du/stat/源码三重取证）：

| 残留 | 大小 | 零引用证据 |
|---|---|---|
| `~/.cache/opencode/packages/` 五个 `@latest` 目录：antigravity-auth 43M（5/10）/ pty 84M（5/16）/ notify 69M、vibeguard 68K、worktree 133M（6/20 实验） | ~329M | `opencode.json` + `tui.json` 双 plugin 数组 grep 零匹配；workspace 根 `packages/package.json` 仍是老包名时代清单（`oh-my-opencode@^4.12.1` + notify/vibeguard/worktree），现三个固定 spec 均不指向它们（注意：该 manifest 属 opencode 缓存机制自管理，只删目录不动 manifest，重建时多拉 4 条依赖无害） |
| `repos/github.com/code-yeongyu/oh-my-openagent` 裸名 checkout | 139M | references 用 `branch: dev` → materialize 走 `@dev` 后缀目录（323M，9/5 仍活跃更新）；裸名 7/27 后零触碰，属早期默认分支时期产物 |
| LSP 死重：`packages/@vue` 52M + `bin/lua-language-server-*` 22.6M | ~75M | `lsp-install-decisions.json` 中 vue（9/1）/ lua-ls（7/22）均 declined，落盘为弹窗前旧版行为；@vue 与 lua 均不在 core `config/lsp.ts` 内置清单 |
| `~/.cache/opencode/skills/security-research/` + `security-review/` 明名双文件 | 15K | opencode 现 skill 发现机制只认 `cache/skills/<Bun.hash(base)>/` + `.opencode-version` 结构（core/src/skill/discovery.ts L113）；4.19.4 的 skill 定义内联在 `dist/index.js`（grep `
Team Mode security`
命中），明名目录无消费者 |
| `bin/kotlin-ls` 0B 空目录、`.superpowers/` 空目录、zshrc L120 `/usr/local/sbin`（目录不存在） | ~0 | 占位残留；kotlin-ls 非 core 内置 LSP |
| 可选项：`bin/vscode-eslint` 106M | 106M | 非 core 内置 LSP、本仓库无 eslint 配置、6/23 后零触碰；但无 declined 决策记录（区别于 @vue/lua），若近期打开过含 eslint 的前端项目则保留 |

补充事实：① `opencode.log` 按启动重置（当前仅覆盖当日），T6 统计的 materialize 失败（token mismatch 258 / overwritten 210）已无日志证据可复现；② 四个 checkout（anomalyco / omo@dev / omo 裸名 / superpowers）当前全部干净（`status --porcelain` 空、stash 0）——T6 的「脏 checkout 重置」移交项经实证无需任何 git 操作；③ `packages/list@latest`（300K）9/5 仍被触碰，活跃，保留。

## plugin git 源版本锁定（superpowers）

`opencode.json` 第 3 行的 superpowers plugin 用 git 源（`superpowers@git+https://...`），不像 `@latest` 的 npm 包有 npm registry 做 semver 网关。为保证可复现性，**显式锁定到 git tag**：

```json
"superpowers@git+https://github.com/obra/superpowers.git#v6.3.0"
```

**为什么锁 tag 而非 commit SHA**：obra 维护规范的 semver tag（v3.1.0 → v6.3.0），可读性远好于 SHA；升级时一眼能看出当前锁的版本。

**`make check` 第 13 项** 会检测：
- opencode.json 是否锁定版本（无 `#vX.Y.Z` 时警告「未锁定」）
- 远端是否有比本地新的 tag（有时警告「有新版 → 运行 make upgrade-superpowers」）
- 无网络时软失败（仅警告「跳过」，不阻断）

**升级流程**：

```bash
make upgrade-superpowers   # 查远端最新 → 改 opencode.json → 清缓存 → 提示重启
```

升级后必须**重启 opencode**，因为 plugin 在启动时加载到内存，运行时不会重读。

## 自定义 plugin：`.opencode/plugin/glm-max.ts`

**作用**：恢复 GLM 5.2/5.3 的 `reasoningEffort: "max"` 被 OMO `chat.params` hook 降级为 `"high"` 的问题。

**背景**：OMO 的 model-capability 兼容性检查在 `chat.params` hook 里，会把 GLM 5.2/5.3 的 `variant: "max"` 降级为 `"high"` 并删除 `reasoningEffort`（heuristic glm family 不含 reasoningEfforts）。

本 plugin 在 OMO 之后执行（`.opencode/plugin/*.ts` 自动发现，排在 plugin_origins 末尾），恢复被删除的 `reasoningEffort`。

**升级风险**：
- 依赖 OMO 内部 hook 执行顺序，OMO 升级可能改变顺序导致失效
- OMO 修复后可移除此 plugin

**状态**：已知技术债，当前能工作，暂不处理。

## shell 权限信任边界（护栏非防线）

2026-08-29 Wave2 安全加固确立的定位声明，实测探针矩阵支撑（opencode run 真实引擎验证）：

- **引擎匹配语义**：bash permission 按 tree-sitter AST 拆 command 节点后逐节点匹配 pattern；含管道符的 pattern（如曾经的 `curl * | *sh*`）不匹配任何节点——该类规则是死规则，已于本轮删除，改为拦截管道尾部的裸解释器节点（`sh` / `bash` / `zsh` deny）与 stdin 模式（`sh -s` / `bash -s`）。
- **拦截面（实测 7 变体全拦）**：`curl X | sh` / `echo ... | bash` / `curl X | zsh` / `wget X | sh` 等管道注入；裸解释器交互也拦。
- **明确不拦（设计边界非遗漏）**：`sh <(curl ...)` 进程替换变体、`npm run <script>` 间接执行、`git config core.hooksPath` + hook 文件写入的组合链。~~`bash -c '...'` / `sh -c '...'`~~ 已于 2026-09-05 T1 转为 deny（解释器 -c/-e 内联代码 10 条：sh/bash/zsh -c*、node -e*/--eval*、python/python3 -c*、ruby -e*、perl -e*，见下节「权限残留风险」）——原「正当用途过宽」判断经四人对审推翻：正当路径可逐条 allow 豁免，不应以放弃拦截换便利。
- **威胁模型定位**：deny 列表是**误操作护栏 + prompt injection 的第一通拦截**，不是对抗性防线——对手若已能诱导 agent 写文件，上述间接执行面无法靠 permission 黑名单封死。纵深依赖：文件 edit 层 deny（.ssh/.env/.aws）+ skills.lock 供应链校验 + MCP 钉版。
- **MCP 供应链三通道**：npx 通道钉版本（zai 精确 0.1.5——持 API key 且低频发布；dbx 钉 minor 0.4——连生产库但 5 天 5 版高频修复节奏，全精确钉有「钉住坏版本」反效果）；全局 bin 通道（claude-mermaid/codegraph）由 check 第 4 项版本常量比对；remote URL 通道（智谱 web 工具 3 条）豁免——供应链风险在服务端，本地不可钉。

## 权限残留风险（2026-09-05 T1 加固后）

T1（fix/security-permissions 分支）闭合缺口 a/c/d/e/f 后，经 opencode v1.18.29 源码逐行验证仍存的残留面（每条附复现路径与上游证据行号；升级 opencode 时按此表复核是否已被上游修复）：

| # | 残留 | 根因（v1.18.29 源码） | 复现路径 | 缓解 |
|---|---|---|---|---|
| 1 | bash 横向读敏感文件 | `cd` 在 CWD 表被跳过权限评估（shell.ts L28、L407），`cat` 段文本只匹配 bash 规则不匹配 read 规则 | `cd ~/.ssh && cat id_rsa` → cd 段跳过、cat 段命中 `*`:allow，仅触发一次 external_directory 询问（习惯性批准即绕过 read 层 deny） | 直接 read 被 `**/id_rsa*` 拦；交互警觉 |
| 2 | symlink 逃逸 external_directory | containsPath / resolvePath 均为字符串路径判断不解析 realpath（instance-context.ts L18-24、shell.ts L366） | worktree 内 `ln -s ~/.ssh lnk` 后 `cat lnk/id_rsa` → 字符串路径在 worktree 内跳过 external_directory，cat 段 allow，OS 层 follow symlink 读到目标 | read 层按文件名仍拦（`lnk/id_rsa` 含 `/id_rsa`）；bash 侧不拦 |
| 3 | FILES 表覆盖面 | external_directory 路径提取仅对 FILES 表命令（shell.ts L29-50：rm/cp/mv/mkdir/touch/chmod/chown/cat + PowerShell 系），python/awk/sed/tee 不在表内 | `python -c` 已 deny；但 `python wr.py`（脚本内 open 写任意路径）不提取路径、不询问 external_directory | 解释器 -c/-e deny 已缩小面；脚本写入属纵深依赖 |
| 4 | 会话内 always 覆盖配置 deny | ask() 求值 approved 在 ruleset 之后 + findLast 后者优先（permission/index.ts L73、L32-L33）；read/edit 的 always pattern 为 `*`（read.ts L258、edit.ts L105）、bash 为前缀通配（shell.ts L409） | 对任意一次 read 选「always」→ approved 加 `read:*:allow` → 同会话后续 read `id_rsa` / `.env` 全部 allow（覆盖配置 deny）；bash 一次 `git push` always → `git push *` allow 覆盖 `git push --force*` deny | 会话内交互慎选 always；上游修复后副此表 |
| 5 | patterns 为空整体放行 | for-of 空 patterns 不执行 + `!needsAsk` 提前 return（permission/index.ts L72、L84）；bash 侧 `scan.patterns.size === 0` 直接 return（shell.ts L282） | 纯 `cd ~/.ssh` 命令（CWD-only）不产生任何 permission 事件 | 单独 cd 无危害；配合 #1 横向才成链 |
| 6 | ask/run 不对称 | 混合 patterns 一旦含 ask 整体升级交互（L75-L84，allow 不豁免）；disabled() 单条件匹配与 evaluate 双条件不对称（L210 vs L32） | 多段命令一段无规则 → 整条询问（含已 allow 段） | 方向安全（多问不少问），仅体验成本 |

键序规范（缺口 g 落地）：opencode.json 为纯 JSON 不支持注释，键序敏感声明落在本节——**permission 规则对象内后声明优先（findLast），通配更宽的规则必须放窄规则之后，allow 豁免（如 `*.env.example`）必须放对应 deny（`*.env.*`）之后**；harness 键序探针（scripts/check-permissions.mjs probeKeyOrder）持续锁定该语义，上游改求值语义即红。

## 上游版本观察项（2026-08-28 体检）

- **opencode CLI ≥1.18.24：config schema V2 过渡开始**——V1 引擎已可读取部分 V2 config 字段（混合配置前向兼容）。当前 `opencode.json` 全部字段经 1.18.29 官方 schema 验证合法，无需动作；后续官方宣布 V1 字段废弃时再评估迁移。另：官方 repo 已从 sst/opencode 迁至 **anomalyco/opencode**。
- **oh-my-openagent 5.0.0-beta 线（截至 2026-08-28 已至 beta.24）**：major 重构——omo-native 发行版、Senpi 引擎集成、**`/start-work` 改名 `/ulw-execute`**、**`omo` 命令改名 `omo-agent-toolkit`**、`shared/<name>` skill 改裸名注册。beta.20 出过杀 session 崩溃，beta 质量未稳——**等 5.0.0 正式版再升级**，届时除标准升级流程外还需同步清理：`disabled_skills` 条目、skill/command 引用名、脚本中的 `omo` 命令调用。
- **omo 4.19.4 的 reasoning 规范**：`models` 链是 canonical 形式，`fallback_models` / `variant` / `reasoningEffort` 已 deprecated（back-compat 窗口内仍可读，运行时归一优先级 reasoning > reasoningEffort > variant）。2026-08-28 已全量清理为 `models` 链 + `reasoning` key，升级 5.0 时无需再动。
- **`omo doctor` 的已知误报**：它会用旧版 schema 校验 `agents.*.models` 为 Unknown key（实际运行时与 `config migrate` 均支持），升级后如仍见此类告警可忽略 `Unknown config key: agents.*.models` 条目。
- **glm-max.ts 与 reasoning 归一的关系**：plugin 在最终 chat.params 层无条件强制 `reasoningEffort=max`，与配置层 key 形式无关，两者独立生效、互不依赖。
## 如何升级 oh-my-openagent 主版本

> **升级前必读**：major 跨越（如 4→5）时 `make upgrade` 自带防跳闸（默认拒绝，`FORCE=1` 或交互 y 放行）；spec 钉版后 4c 步骤自动同步双 json。

### 升级核对四件套（5.0 发布日必查，对抗审查收敛版）

1. **disabled_skills 条目**：`~/.omo/omo.jsonc` 的 `disabled_skills`（当前 playwright/dev-browser/agent-browser）——5.0 改裸名注册后条目名可能变化，逐条核对仍生效。
2. **skill / command 引用名清扫**：5.0 已改名 `/start-work`→`/ulw-execute`、`omo` 命令→`omo-agent-toolkit`——grep 本仓库与日常用法中的旧名。
3. **scripts/docs 中 omo 命令调用**：`grep -rn "omo " scripts/ docs/ Makefile` 核对调用面。
4. **doctor models 误报静默核对**：上游仅 5.0 线修复了 `agents.*.models` Unknown key 误报（dev commit 989636bc5，validate.ts 原生解析 agent.models 链）；stable 4.19.4 实跑 13 条误报现行存在。升级后跑 `omo doctor` 确认误报消失，然后删除 `.opencode/instructions.md` 的误报甄别记录。

断言时效声明：以上基于 2026-08-29 dev HEAD（c034b5313）；升级当天以当时 release notes 重验：`git -C ~/.local/share/opencode/repos/github.com/code-yeongyu/oh-my-openagent@dev log -S '<关键词>' --since=2026-08-25 --oneline`。

```bash
# 推荐：一键升级（自动检测 npm 最新 → 改 package.json + 双 json spec → 重装 → 同步 $schema URL）
make upgrade
make check              # 体检（含 pluginSpec 守卫）
```

```bash
# 推荐：一键升级（自动检测 npm 最新 → 改 package.json → 重装 → 同步 $schema URL）
make upgrade
make check              # 体检
```

### 手动分步（`make upgrade` 失败或需控制每步时）

```bash
# 1. 改 package.json 的 oh-my-openagent 版本号
# 2. 重装依赖（含 postinstall: 全局 MCP）
make update

# 3. 同步 $schema URL（~/.omo/omo.jsonc 顶部）改到新版本号
# 4. 体检
make check
# 5. 提交：package.json + package-lock.json + skills.lock + 文档（OMO 配置 ~/.omo/omo.jsonc 不在 git 内）
```

## 手动分步安装（备选）

> `make install` 某步失败时可单独执行对应命令。以下是底层逻辑说明。

**环境变量**（`make config` 底层）：交互式写入 `~/.zshrc`。用 `.zshrc` 而非 `.zshenv`（opencode 从终端启动加载 `.zshrc`；GUI 场景由 `launchctl setenv` 覆盖）。脚本幂等，重复运行替换旧块而非追加。

**opencode-mem 记忆配置**（`make mem` 底层）：从 `opencode-mem.jsonc.template` 复制，已是智谱直连配置（`glm-5.3-flash` + `bigmodel.cn` + `env://Z_AI_API_KEY`），无需手动改注释。

> **为什么用智谱直连而非 `opencodeProvider` 模式？**
> `opencodeProvider` 要求 provider 支持 structured output 协议，智谱 GLM 不支持会报 `prompt response missing info`。
> 改用智谱直连 OpenAI-compatible 接口绕过此限制，复用 `Z_AI_API_KEY` 无需额外 API key。

**飞书 CLI**（`make feishu` 底层）：见 `setup-feishu-cli.sh`。Bot 身份无需审批即可读文档。

**oh-my-openagent 版本锁定**：`package.json` 精确锁定 `4.19.4`（非 `^4.19.4`），确保所有机器运行相同版本。
