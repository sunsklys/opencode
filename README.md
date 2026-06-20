# opencode 个人配置仓库

我的 opencode 配置（智谱 + 火山引擎 + 国产全模型路由）。

## 包含什么

| 文件 | 说明 |
|---|---|
| `opencode.json` | provider 定义（火山引擎 8 模型）+ 8 MCP + 2 plugin + LSP + permission |
| `oh-my-openagent.json` | 12 agent + 8 category 路由（sisyphus / oracle / metis 等跨厂家 fallback） |
| `tui.json` | 主题配置 |
| `setup-feishu-cli.sh` | 飞书 CLI + SKILL 一键安装脚本 |
| `package.json` | oh-my-openagent 4.12.0（精确锁定配合 hephaestus GLM 补丁）+ @opencode-ai/plugin ^1.17.8 + postinstall 全局依赖 |
| `package-lock.json` | npm 精确依赖版本 |
| `Makefile` | 一键安装 / 体检 / 更新编排（`make install` / `make check` / `make update`） |
| `scripts/*.sh` | 安装 / 环境变量 / 体检脚本（被 Makefile 调用） |
| `opencode-mem.jsonc.template` | 智谱直连模板（`make mem` 生成 `opencode-mem.jsonc`） |
| `.nvmrc` | 锁定 Node.js v22（fnm/nvm 自动识别） |
| `patches/` | oh-my-openagent 补丁（hephaestus GLM 支持） |
**不包含**（已被 .gitignore 排除）：
- `auth.json` - opencode 登录凭证
- `node_modules/` - 依赖（新机器 npm install 重建）
- `opencode.db` - 会话历史
- `opencode-mem.jsonc` - 本地持久记忆配置（`make mem` 从模板自动生成，智谱直连）
- `~/.opencode-mem/` - opencode-mem 数据目录（向量库 + SQLite + Web UI 缓存）

---

---

## 配置文件结构

> 本节是「字段地图」，帮你快速定位配置。详细字段值请直接看源文件，README 不逐字段穷举。

### `opencode.json`（opencode 主配置）

| 类别 | 关键字段 | 说明 |
|---|---|---|
| **插件/扩展** | `plugin` / `mcp` / `lsp` | 2 plugin + 8 MCP + LSP（true = 自动检测内置） |
| **模型路由** | `provider` / `small_model` | 火山引擎 8 模型 + deepseek-v4-flash 作 small |
| **行为开关** | `default_agent` / `share` / `autoupdate` / `compaction` | build / manual / notify / auto |
| **I/O 限制** | `tool_output` / `attachment` | 2000 行/512KB / 图像 1600x1600 |
| **安全** | `permission.read` / `permission.bash` / `watcher.ignore` | deny 列表 + 文件监听忽略 |

### `oh-my-openagent.json`（OMO 框架配置）

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
| `theme` / `scroll_speed` / `mouse` | tokyonight / 3 / true |

### `opencode-mem.jsonc`（本地持久记忆配置，**不入 git**）

| 字段类别 | 说明 |
|---|---|
| **auto-capture** | `memoryProvider` / `memoryModel` / `memoryApiUrl` / `memoryApiKey`（智谱直连） |
| **存储** | `storagePath` / `embeddingModel` / `maxVectorsPerShard`（本地默认值） |
| **Web UI** | `webServerEnabled` / `webServerPort` / `webServerHost`（4747 / 127.0.0.1） |
| **用户画像** | `userProfileAnalysisInterval` / `injectProfile`（默认 10 / true） |

> **迁移原则**：配置文件都进 git，新机器 `git clone` + `make install` 即可。`opencode-mem.jsonc` 不入 git（含 API key 引用），由 `make mem` 从模板自动生成。

## 快速开始（新机器）

> 装好 Node.js ≥22 和 opencode 后，3 条命令搞定全部配置。

```bash
git clone <你的仓库地址> ~/.config/opencode
cd ~/.config/opencode

make install                              # 一键：依赖 + 环境变量 + 记忆配置 + 飞书 CLI
opencode auth login zhipuai-coding-plan   # 登录智谱凭证
make check                                # 体检（8 项全绿即就绪）
```

`make install` 依次执行：

| 步骤 | 子命令 | 做什么 |
|---|---|---|
| 1 | `make deps` | npm install + patch-package（hephaestus GLM 补丁）+ opencode-mem 全局装 + 软链 |
| 2 | `make config` | 交互式输入 3 个 API key → 写入 `~/.zshrc` + `launchctl setenv` |
| 3 | `make mem` | 从模板生成 `opencode-mem.jsonc`（智谱直连，复用 `Z_AI_API_KEY`） |
| 4 | `make feishu` | 飞书 CLI + 27 个 SKILL |

> API key 获取：[火山引擎](https://console.volcengine.com/ark) ｜ [智谱](https://www.bigmodel.cn/usercenter/apikeys) ｜ [飞书](https://open.feishu.cn/app/cli_aaa482d9dcb8dbcd)

### 前置依赖（make install 之前）

```bash
# Node.js（.nvmrc 已锁定 v22，fnm/nvm 自动识别）
curl -fsSL https://fnm.vercel.app/install | bash
fnm install 22 && fnm default 22

# opencode 主程序
curl -fsSL https://opencode.ai/install | bash

# LSP 二进制（让 lsp_diagnostics / goto_definition 等可用）
npm i -g typescript-language-server pyright
# 可选：npm i -g gopls   # Go 项目
# 可选：npm i -g eslint  # TS/JS lint
# python3（setup-env.sh 依赖；macOS 自带，Linux 极简环境需：apt/yum install python3）
```

### Makefile 命令速查

| 命令 | 作用 |
|---|---|
| `make install` | 完整安装（新机器首次） |
| `make check` | 体检（8 项：环境 / 依赖 / 补丁 / 记忆 / Web UI / 飞书） |
| `make update` | 更新依赖到最新（清 node_modules 重装） |
| `make deps` | 仅装 npm 依赖 + opencode-mem 软链 |
| `make config` | 仅配置环境变量（交互式） |
| `make mem` | 仅生成 `opencode-mem.jsonc` |
| `make feishu` | 仅装飞书 CLI + SKILL |
| `make clean` | 清理 node_modules |

### 手动分步（备选）

> `make install` 某步失败时可单独执行对应命令。以下是底层逻辑说明。

**环境变量**（`make config` 底层）：交互式写入 `~/.zshrc`。用 `.zshrc` 而非 `.zshenv`（opencode 从终端启动加载 `.zshrc`；GUI 场景由 `launchctl setenv` 覆盖）。脚本幂等，重复运行替换旧块而非追加。

**opencode-mem 记忆配置**（`make mem` 底层）：从 `opencode-mem.jsonc.template` 复制，已是智谱直连配置（`glm-5-turbo` + `bigmodel.cn` + `env://Z_AI_API_KEY`），无需手动改注释。

> **为什么用智谱直连而非 `opencodeProvider` 模式？**
> `opencodeProvider` 要求 provider 支持 structured output 协议，智谱 GLM 不支持会报 `prompt response missing info`。
> 改用智谱直连 OpenAI-compatible 接口绕过此限制，复用 `Z_AI_API_KEY` 无需额外 API key。

**飞书 CLI**（`make feishu` 底层）：见 `setup-feishu-cli.sh`。Bot 身份无需审批即可读文档。

**oh-my-openagent 版本锁定**：`package.json` 精确锁定 `4.12.0`（非 `^4.12.0`），因 `patches/oh-my-openagent+4.12.0.patch` 修改 `isHephaestusSupportedModel` 让 hephaestus agent 支持 GLM 模型。patch-package 按文件名版本匹配，升级需同步更新补丁。
---

## API key 获取地址

| 变量 | 服务 | 获取地址 |
|---|---|---|
| `VOLC_API_KEY` | 火山引擎 Ark | https://console.volcengine.com/ark |
| `Z_AI_API_KEY` | 智谱 BigModel | https://www.bigmodel.cn/usercenter/apikeys |
| `FEISHU_APP_SECRET` | 飞书开放平台 App Secret | https://open.feishu.cn/app/cli_aaa482d9dcb8dbcd

---

## 多机同步

```bash
# 改了配置后
cd ~/.config/opencode
git add . && git commit -m "update: xxx" && git push

# 另一台机器拉新版
cd ~/.config/opencode
git pull
make update    # 清 node_modules 重装 + 补丁 + opencode-mem 软链
make check     # 体检全绿
```

---

## 故障排查

### `opencode` 启动报 "missing apiKey"
→ 环境变量没加载。检查 `echo $VOLC_API_KEY` 是否为空。
→ 解决：确认 `~/.zshrc` 里的 `export VOLC_API_KEY=...` 存在且正确，然后 `source ~/.zshrc` 或重开终端。
→ 如果从 LazyVim/Neovim GUI 启动，还需确认 `launchctl getenv VOLC_API_KEY` 有值。

### 智谱模型调不通
→ 没执行 `opencode auth login zhipuai-coding-plan`。
→ 解决：执行上面命令重新认证。

### npm install 卡住
→ 国内网络问题。
→ 解决：`npm config set registry https://registry.npmmirror.com`

### MCP 服务报错（mermaid / codegraph 不可用）
→ 全局依赖未安装。检查 `which claude-mermaid` 和 `which codegraph`。
→ 解决：`npm i -g claude-mermaid @colbymchenry/codegraph`

### 飞书 CLI 读文档报权限错误
→ Bot 身份不需要审批，直接用 `--as bot` 即可。
→ 用户身份敏感权限（多维表格、审批等）需要管理员审批。
→ 解决：`lark-cli auth status` 查看当前状态。

### 飞书 CLI 在新电脑上提示未配置
→ 运行 `bash setup-feishu-cli.sh`（`FEISHU_APP_SECRET` 需已在 `~/.zshrc` 中配置）。

### opencode-mem 报 `prompt response missing info`
→ `opencode-mem.jsonc` 用了 `opencodeProvider` 模式，但智谱不支持 structured output。
→ 解决：`rm opencode-mem.jsonc && make mem` 重新生成智谱直连配置，重启 opencode。

### opencode 启动报 `Missing key lsp.xxx.command`
→ `opencode.json` 的 `lsp` 字段格式错误（每个 LSP 条目必须有 `command` 字段）。
→ 解决：直接用 `"lsp": true` 让 opencode 自动检测启用所有内置 LSP，不要手动列各语言。

---

## 功能开关速查

| 功能 | 配置位置 | 状态 |
|---|---|---|
| LSP 工具链（`lsp_diagnostics` / `lsp_goto_definition` / `lsp_find_references` / `lsp_rename`） | `opencode.json` → `"lsp": true` | ✅ 已启用（自动检测内置 LSP） |
| opencode-mem 本地持久记忆 | `opencode.json` plugin 字段 + `opencode-mem.jsonc` | ✅ 已启用（智谱 glm-5-turbo auto-capture） |
| 8 个 MCP（智谱 web 工具 / notion / mermaid / codegraph / zread / chrome-mcp disabled） | `opencode.json` mcp 字段 | ✅ 已启用 |
| permission 加固（28 条 deny，含 `eval` / `: > .env*` / `: > .ssh/*` / `: > .aws/*`） | `opencode.json` permission.bash | ✅ 已启用 |
| Web UI（查看记忆） | `opencode-mem.jsonc` webServerEnabled | ✅ http://127.0.0.1:4747 |
| 一键安装 / 体检 / 更新 | `Makefile` + `scripts/*.sh` | ✅ `make install` / `make check` / `make update` |

## 角色路由速查

| 场景 | 路由 |
|---|---|
| 主调度 (sisyphus) | GLM-5.2 (zhipu, max) |
| 架构/深度推理 (oracle/prometheus/momus/metis/plan) | GLM-5.2 (zhipu, max) |
| 高难度自主 (ultrabrain/deep) | GLM-5.2 (zhipu, max) |
| 创意/非常规 (artistry) | GLM-5.2 (zhipu, max)（fallback → DeepSeek V4-Pro） |
| 编码实现 (hephaestus/atlas/sisyphus-junior/unspecified-high) | GLM-5.2 (zhipu, max)（fallback → DeepSeek V4-Pro） |
| 多模态/前端 (multimodal-looker/visual-engineering) | GLM-5v-Turbo |
| 检索/轻量 (librarian/explore/unspecified-low) | DeepSeek V4-Flash (low) |
| 快速执行 (quick) | DeepSeek V4-Flash (minimal) |
| 写作 (writing) | GLM-5.2 |

> **调度与深度推理类** GLM-5.2 主模型（sisyphus / oracle / prometheus / momus / metis / plan / ultrabrain / deep / writing）均配置 `volcengine-plan/glm-5.2` 作同模型跨 provider fallback（zhipuai 宕机先走火山通道保持模型一致，再退化到异构模型）。编码实现类（hephaestus / atlas / sisyphus-junior / artistry / unspecified-high）的 fallback 首位是 `deepseek-v4-pro`。`max_fallback_attempts=4`。
