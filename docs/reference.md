# 参考手册

> 配置文件字段地图、运行机制说明、升级流程、信任边界。配置审查和故障定位时用。

## 配置文件结构

> 字段地图，帮你快速定位配置。详细字段值请直接看源文件，本文档不逐字段穷举。

### `opencode.json`（opencode 主配置）

| 类别 | 关键字段 | 说明 |
|---|---|---|
| **插件/扩展** | `plugin` / `mcp` / `lsp` | 2 plugin + 8 MCP + LSP（true = 自动检测内置） |
| **模型路由** | `provider` / `small_model` | 火山引擎 8 模型 + 智谱 glm-5-turbo 作 small（避开火山 deepseek-v4-flash 月配额限制） |
| **行为开关** | `default_agent` / `share` / `autoupdate` / `compaction` | build / manual / notify / auto |
| **I/O 限制** | `tool_output` / `attachment` | 2000 行/512KB / 图像 1600x1600 |
| **安全** | `permission.read` / `permission.bash` / `watcher.ignore` | deny 列表 + 文件监听忽略 |

### `oh-my-openagent.json`（OMO 框架配置）

| 类别 | 关键字段 | 说明 |
|---|---|---|
| **角色定义** | `agents` / `categories` | 11 agent + 8 category + fallback 链（详见「角色路由速查」） |
| **架构开关** | `team_mode` / `tmux` / `sisyphus_agent` / `default_mode` | 多 agent 协作 / TUI 可视化 / planner / ultrawork 默认值 |
| **容错与性能** | `runtime_fallback` / `model_fallback` / `background_task` / `model_capabilities` | 4 次重试 / 跨 provider fallback / 并发控制 / 能力探测 |
| **实验特性** | `experimental` / `keyword_detector` / `disabled_hooks` | task_system / context_pruning / intent 关键词 / hook 黑名单 |
| **编码习惯** | `i18n` / `hashline_edit` / `git_master` | zh / 行内 hash 编辑 / commit footer |

### `tui.json`（TUI 专用配置）

| 字段 | 说明 |
|---|---|
| `plugin` | TUI 模式加载的 plugin（与 `opencode.json` 保持同步） |
| `theme` / `scroll_speed` / `mouse` | tokyonight / 3 / true |

### `opencode-mem.jsonc`（本地持久记忆配置，**不入 git**）

| 字段类别 | 说明 |
|---|---|
| **auto-capture** | `memoryProvider` / `memoryModel` / `memoryApiUrl` / `memoryApiKey`（智谱直连） |
| **存储** | `storagePath` / `embeddingModel` / `maxVectorsPerShard`（本地默认值） |
| **Web UI** | `webServerEnabled` / `webServerPort` / `webServerHost`（4747 / 127.0.0.1） |
| **用户画像** | `userProfileAnalysisInterval` / `injectProfile`（默认 10 / true） |

> **迁移原则**：配置文件都进 git，新机器 `git clone` + `make install` 即可。`opencode-mem.jsonc` 不入 git（由 `make mem` 从模板生成，保持 `.template` 作权威源），避免本地实例澉移污染 git 历史。

## 关于 `prompt_append` × 12 重复

> 12 个 agent/category 都挂了 `"prompt_append": "始终使用中文（简体）回答..."`，看似 DRY 违反，实则是**必要的**。

**为什么不依赖 `i18n.locale: "zh"`？**
- OMO 的 `i18n.locale` 只管 **toast/UI 文案**翻译（`locales[currentLang][key]`，如 `toast.fallback_runtime`）
- LLM 回答什么语言**完全不由 i18n 控制**，只由 system prompt / prompt_append 决定
- 源码证据：`index.js:85706-85759` 的 `locales` 对象全是 toast key；`index.js:123759-123763` 显示 prompt_append 被合并进 system prompt

**优化方向（已实施）**：
- prompt_append 支持 `file://` 协议（源码 `index.js:149996-150022`）
- 已提取到 `.opencode/lang-zh.md`，用 `prompt_append: "file://.opencode/lang-zh.md"` 单源引用

## 超时字段作用域对照

> 5 个超时相关字段分散在 opencode.json 和 oh-my-openagent.json，作用域完全不重叠。配置审查时必读。

| 字段 | 文件 | 作用域 | 触发动作 | 源码证据 |
|---|---|---|---|---|
| `monitor.max_runtime_ms` (1800000=30min) | oh-my-openagent.json | **外部子进程**（monitor 启动的 shell command） | setTimeout 强制 SIGTERM 杀子进程 | index.js:133018 `spawnMonitorProcess` |
| `babysitting.timeout_ms` (300000=5min) | oh-my-openagent.json | **主会话 idle 检测**（`session.idle` 事件后） | 给用户发提醒（不杀进程） | index.js:110060-110110 `unstable-agent-babysitter` hook |
| `runtime_fallback.timeout_seconds` (60) | oh-my-openagent.json | **单 session 单次调用**（含主模型 + fallback 累计） | 触发 fallback 切换 | index.js:103092-103115 `prepareFallback` |
| `experimental.mcp_timeout` (30000) | opencode.json | **单次 MCP 工具调用**（网络超时） | MCP 调用失败，agent 收到错误 | opencode 本体字段 |
| `model_capabilities.refresh_timeout_ms` (5000) | oh-my-openagent.json | **启动时模型能力探测**（一次性） | 跳过刷新，用缓存元数据 | index.js:81832-81857 |

**关键区分**：
- `monitor.max_runtime_ms` 是**子进程硬超时**（kill），`babysitting.timeout_ms` 是**主会话 idle 提醒**（nudge）。两者不冲突，monitor 跑 30min 时 babysitting 不会杀它
- `runtime_fallback.timeout_seconds` 是单 session 累计（含主模型首次失败 + 所有 fallback 尝试），`max_fallback_attempts=4` 意味着「主失败 + 3 fallback = 4 次」

## experimental 命名空间归属澄清

> `opencode.json` 和 `oh-my-openagent.json` 都有 `experimental` 块，但归属完全不同。

| 字段 | 归属 | 说明 |
|---|---|---|
| `experimental.batch_tool` | opencode 本体 | 批量工具调用 |
| `experimental.continue_loop_on_deny` | opencode 本体 | 拒绝后继续循环 |
| `experimental.mcp_timeout` | opencode 本体 | 全局 MCP 超时 |
| `experimental.policies` | opencode 本体 | provider 访问策略 |
| `experimental.task_system` | OMO 注入 | task 跟踪系统 |
| `experimental.preemptive_compaction` | OMO 注入 | 预防性压缩 |
| `experimental.aggressive_truncation` | OMO 注入 | 激进截断 |

> 配置审查时先看字段在哪一边：opencode 本体字段在 `opencode.json` 写一次就生效；OMO 注入字段在 `oh-my-openagent.json`，opencode 本体不识别。

## 功能开关速查

| 功能 | 配置位置 | 状态 |
|---|---|---|
| LSP 工具链（`lsp_diagnostics` / `lsp_goto_definition` / `lsp_find_references` / `lsp_rename`） | `opencode.json` → `"lsp": true` | ✅ 已启用（自动检测内置 LSP） |
| opencode-mem 本地持久记忆 | `opencode.json` plugin 字段 + `opencode-mem.jsonc` | ✅ 已启用（智谱 glm-5-turbo auto-capture） |
| 8 个 MCP（智谱 web 工具 / notion / mermaid / codegraph / zread / chrome-mcp disabled） | `opencode.json` mcp 字段 | ✅ 已启用 |
| permission 加固（read + bash + edit 三层 deny，含 `eval` / `: > .env*` / `: > .ssh/*` / `: > .aws/*`） | `opencode.json` permission.{read,bash,edit} | ✅ 已启用（纵深层防御） |
| Web UI（查看记忆） | `opencode-mem.jsonc` webServerEnabled | ✅ http://127.0.0.1:4747 |
| 一键安装 / 体检 / 更新 | `Makefile` + `scripts/*.sh` | ✅ `make install` / `make check` / `make update` |
| **monitor 后台监控**（agent 能 watch dev server / test runner / build log） | `oh-my-openagent.json` → `monitor.enabled=true`（idle 模式） | ✅ 已启用 |
| **ralph_loop 迭代上限**（防 ralph 失控烧钱） | `oh-my-openagent.json` → `ralph_loop.default_max_iterations=30` | ✅ 显式 cap（默认 100） |
| **babysitting 超时**（适配 GLM-5.2 max reasoning 首响应延迟） | `oh-my-openagent.json` → `babysitting.timeout_ms=300000` | ✅ 5min（默认 2min） |
| **comment_checker**（中文注释质量检查） | `oh-my-openagent.json` → `comment_checker.custom_prompt` | ✅ 已启用（中文提示） |
| **disabled_skills/commands**（禁用 playwright-cli/dev-browser/agent-browser + ralph-loop/cancel-ralph） | `oh-my-openagent.json` → `disabled_skills/disabled_commands` | ✅ 已禁用不用的内置功能 |
| **experimental.batch_tool + continue_loop_on_deny**（批量工具调用 + 拒绝后继续循环） | `opencode.json` → `experimental` | ✅ 已启用 |
| **experimental.policies**（deny openai/anthropic/google provider，防误用海外模型） | `opencode.json` → `experimental.policies` | ✅ 已启用 |
| **experimental.mcp_timeout**（全局 MCP 超时 30s，宽松适配远程接口） | `opencode.json` → `experimental.mcp_timeout=30000` | ✅ 已启用 |
| **compaction.prune + tail_turns**（自动修剪旧工具输出 + 保留近 6 轮） | `opencode.json` → `compaction` | ✅ prune=true, tail_turns=6 |
| **formatter**（启用内置格式化器，需项目装 prettier/dprint） | `opencode.json` → `formatter=true` | ✅ 已启用（检测不到则 no-op） |
| **instructions**（项目级系统提示补充） | `opencode.json` → `instructions: ['.opencode/instructions.md']` | ✅ 已启用 |

## 角色路由速查

| 场景 | 路由 |
|---|---|
| 主调度 (sisyphus) | GLM-5.2 (zhipu, max) |
| 架构/深度推理 (oracle/prometheus/momus/metis/plan) | GLM-5.2 (zhipu, max) |
| 高难度自主 (ultrabrain/deep) | GLM-5.2 (zhipu, max) |
| 创意/非常规 (artistry) | GLM-5.2 (zhipu, max)（fallback → DeepSeek V4-Pro） |
| 编码实现 (atlas/sisyphus-junior/unspecified-high) | GLM-5.2 (zhipu, max)（fallback → DeepSeek V4-Pro） |
| 多模态/前端 (multimodal-looker/visual-engineering) | GLM-5v-Turbo |
| 检索/轻量 (librarian/explore/unspecified-low) | DeepSeek V4-Flash (low) |
| 快速执行 (quick) | DeepSeek V4-Flash (minimal) |
| 写作 (writing) | GLM-5.2 |

> **调度与深度推理类** GLM-5.2 主模型（sisyphus / oracle / prometheus / momus / metis / plan / ultrabrain / deep / writing）均配置 `volcengine-plan/glm-5.2` 作同模型跨 provider fallback（zhipuai 宕机先走火山通道保持模型一致，再退化到异构模型）。编码实现类（atlas / sisyphus-junior / artistry / unspecified-high）的 fallback 首位是 `deepseek-v4-pro`。`max_fallback_attempts=4`。

## team_mode 成本控制

当前 team_mode 配置无显式 token/cost 上限（`max_members=8`, `max_member_turns=500`）。
OMO schema 暂不暴露 `max_total_tokens_per_run` 或 `max_cost_cents_per_run` 字段。
建议保守设置：`max_member_turns: 200`（从 500 下调）作为隐性成本控制。

## MCP 数据流向与信任边界

> 处理敏感项目前必读。部分 MCP 接口会把对话/文件内容发到远程服务器。

| MCP 接口 | 类型 | 数据流向 | 信任边界 |
|---|---|---|---|
| `zai-mcp-server` | 本地启动 | 发往智谱 bigmodel.cn（Z_AI_API_KEY 鉴权） | 智谱服务器可见你的提问内容 |
| `web-search-prime` / `web-reader` / `zread` | 远程接口 | 直连 bigmodel.cn | 智谱服务器可见查询/读取内容 |
| `notion` | mcp-remote 远程 | https://mcp.notion.com/mcp | **双向**：opencode 可读写你全部 Notion（页面/数据库/评论）。处理敏感 Notion 库时建议临时禁用（`opencode.json` → `mcp.notion.enabled: false`） |
| `mermaid` / `codegraph` | 本地启动 | 本地处理，不出网 | 无远程信任问题 |
| `chrome-mcp` | 已禁用 | - | - |

> **敏感项目建议**：临时关 `opencode-mem.jsonc` → `autoCaptureEnabled: false`，避免会话要点出网到智谱做元数据推理。

## plugin `@latest` 漂移检测（`make check` 第 7 项）

`opencode.json` / `tui.json` 用 `@latest` 标签加载 plugin，opencode 会绕过项目 `package-lock.json`，从 `~/.cache/opencode/packages/<plugin>@latest/` 加载运行时版本。`make check` 第 7 项比较：
- 项目软链 `node_modules/opencode-mem`（`npm i -g` 装的全局版本）
- opencode 缓存 `~/.cache/opencode/packages/opencode-mem@latest/node_modules/opencode-mem/`（`@latest` 拉到的版本）

两者不一致时警告：`@latest 已漂移，opencode 启动会加载缓存版本而非软链版本`。处理方式：`make update` 重装同步（**Makefile L110 已自动清 opencode-mem@latest 缓存，下次启动 opencode 重拉 npm latest，与全局软链同步**），或手动删缓存 `find ~/.cache/opencode/packages/opencode-mem@latest -delete`。

## 如何升级 oh-my-openagent 主版本

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

# 3. 同步 $schema URL（oh-my-openagent.json 顶部）改到新版本号
# 4. 体检
make check
# 5. 提交：package.json + oh-my-openagent.json
```

## 手动分步安装（备选）

> `make install` 某步失败时可单独执行对应命令。以下是底层逻辑说明。

**环境变量**（`make config` 底层）：交互式写入 `~/.zshrc`。用 `.zshrc` 而非 `.zshenv`（opencode 从终端启动加载 `.zshrc`；GUI 场景由 `launchctl setenv` 覆盖）。脚本幂等，重复运行替换旧块而非追加。

**opencode-mem 记忆配置**（`make mem` 底层）：从 `opencode-mem.jsonc.template` 复制，已是智谱直连配置（`glm-5-turbo` + `bigmodel.cn` + `env://Z_AI_API_KEY`），无需手动改注释。

> **为什么用智谱直连而非 `opencodeProvider` 模式？**
> `opencodeProvider` 要求 provider 支持 structured output 协议，智谱 GLM 不支持会报 `prompt response missing info`。
> 改用智谱直连 OpenAI-compatible 接口绕过此限制，复用 `Z_AI_API_KEY` 无需额外 API key。

**飞书 CLI**（`make feishu` 底层）：见 `setup-feishu-cli.sh`。Bot 身份无需审批即可读文档。

**oh-my-openagent 版本锁定**：`package.json` 精确锁定 `4.16.2`（非 `^4.16.2`），确保所有机器运行相同版本。
