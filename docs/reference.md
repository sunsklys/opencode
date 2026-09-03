# 参考手册

> 配置文件字段地图、运行机制说明、升级流程、信任边界。配置审查和故障定位时用。

## 配置文件结构

> 字段地图，帮你快速定位配置。详细字段值请直接看源文件，本文档不逐字段穷举。

### `opencode.json`（opencode 主配置）

| 类别 | 关键字段 | 说明 |
|---|---|---|
| **插件/扩展** | `plugin` / `mcp` / `lsp` | 3 plugin + 7 MCP + LSP（true = 自动检测内置） |
| **模型路由** | `model` / `small_model` | 智谱单栈：glm-5.3 主 + glm-5-turbo 作 small（火山引擎已停订，provider 块已删） |
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
| `plugin` | TUI 模式加载的 plugin（与 `opencode.json` 保持同步） |
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

## plugin 加载机制与钉版策略（Wave3 闭合 @latest 旁路）

**omo 已钉精确版本**（2026-08-29）：`opencode.json` / `tui.json` 的 plugin spec 为 `oh-my-openagent@4.19.4`（不再是 `@latest`）。

为什么钉版是唯一闭合解：`@latest` 通道下防跳闸/major 检测/自愈三通道全缺——`upgrade.sh` 防跳闸只看 `package.json`，而 opencode 启动时按 spec 从 `~/.cache/opencode/packages/<spec>/` 解析缓存层，npm dist-tag `latest` 一旦切到 5.0，缓存会先于 node_modules 静默跳版。钉版后：缓存目录名即 spec（`oh-my-openagent@4.19.4/`），版本变化必须显式改 spec（`make upgrade` 的 4c 步骤自动同步双文件），配合 check-drift.mjs 的 pluginSpec 一致性守卫（package.json ↔ 双 json spec，失配 critical fail）。

**opencode-mem 已钉 `2.25.0` + 本地 tags 兜底 patch**（2026-09-02）：双 json 的 plugin spec 均为 `opencode-mem@2.25.0`，缓存目录 `~/.cache/opencode/packages/opencode-mem@2.25.0/` 的 `client.js` 带 `PATCH(tags-fallback)` 三层兜底（正文内嵌 `Tags:` 行提取 → type 映射 → 保底），防上游「LLM tags 偶发缺失无兜底入库 → detect 零容忍弹窗」缺陷链。相关资产：`scripts/patch-mem-tags.mjs`（可重放 patch，幂等/锚点校验/语法校验/失败回滚）、`scripts/fix-mem-untagged.mjs`（存量清理，双通道同源强正则）、check §3 pin 缓存+patch 存活检查、install.sh pin-aware 全局装（跟随 spec）。

**升级 runbook（上游发新版时六步）**：① `npm view opencode-mem version` + 读 changelog → ② 判断 tags 缺陷是否已修复（已修复 → 摘 patch 回 `@latest`，流程止于此）→ ③ 未修复则改双 spec（`opencode.json` + `tui.json` 同步，防 TUI 域旁路）→ ④ 清 pin 缓存目录并重启 opencode 重拉 → ⑤ 重放 patch（**前置门槛：diff 新旧 `client.js` 的 `addMemory` 函数体确认上游未在该区间插入新逻辑**，防锚点命中但语义漂移的静默错配）→ ⑥ `make check` 验证（§3 应报 patch 存活）。

`make check` 第 7 项比较：项目软链 `node_modules/opencode-mem`（全局版本，install.sh 按 spec 安装）↔ opencode 缓存目录版本；不一致警告后 `make update` 重装同步。

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
- **明确不拦（设计边界非遗漏）**：`bash -c '...'` / `sh -c '...'`（日常正当用途过宽：make recipe、脚本子进程包装；此类属于「已具备任意命令能力」的等价路径，由具体命令 deny（rm/sudo/dd/git push -f 等）+ `sh <(curl ...)` 进程替换变体承担残余风险）；`npm run <script>` 间接执行；`git config core.hooksPath` + hook 文件写入的组合链。
- **威胁模型定位**：deny 列表是**误操作护栏 + prompt injection 的第一通拦截**，不是对抗性防线——对手若已能诱导 agent 写文件，上述间接执行面无法靠 permission 黑名单封死。纵深依赖：文件 edit 层 deny（.ssh/.env/.aws）+ skills.lock 供应链校验 + MCP 钉版。
- **MCP 供应链三通道**：npx 通道钉版本（zai 精确 0.1.5——持 API key 且低频发布；dbx 钉 minor 0.4——连生产库但 5 天 5 版高频修复节奏，全精确钉有「钉住坏版本」反效果）；全局 bin 通道（claude-mermaid/codegraph）由 check 第 4 项版本常量比对；remote URL 通道（智谱 web 工具 3 条）豁免——供应链风险在服务端，本地不可钉。

## 上游版本观察项（2026-08-28 体检）

- **opencode CLI ≥1.18.24：config schema V2 过渡开始**——V1 引擎已可读取部分 V2 config 字段（混合配置前向兼容）。当前 `opencode.json` 全部字段经 1.18.27 官方 schema 验证合法，无需动作；后续官方宣布 V1 字段废弃时再评估迁移。另：官方 repo 已从 sst/opencode 迁至 **anomalyco/opencode**。
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
