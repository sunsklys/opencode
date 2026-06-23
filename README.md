# opencode 个人配置仓库

我的 opencode 配置（智谱 + 火山引擎 + 国产全模型路由）。

## 包含什么

| 文件 | 说明 |
|---|---|
| `opencode.json` | provider 定义（火山引擎 8 模型）+ 8 MCP 条目（7 启用 + chrome-mcp 默认禁用）+ 2 plugin + LSP + permission |
| `oh-my-openagent.json` | 12 agent + 8 category 路由（sisyphus / oracle / metis 等跨厂家 fallback） |
| `tui.json` | 主题配置 |
| `setup-feishu-cli.sh` | 飞书 CLI + SKILL 一键安装脚本 |
| `package.json` | oh-my-openagent 4.12.1（精确锁定配合 hephaestus GLM 补丁）+ @opencode-ai/plugin 1.17.9（精确锁定）+ postinstall 全局依赖 |
| `package-lock.json` | npm 精确依赖版本 |
| `Makefile` | 一键安装 / 体检 / 更新编排（`make install` / `make check` / `make update`） |
| `scripts/*.sh` | 安装 / 环境变量 / 体检脚本（被 Makefile 调用） |
| `opencode-mem.jsonc.template` | 智谱直连模板（`make mem` 生成 `opencode-mem.jsonc`） |
| `.nvmrc` | 锁定 Node.js v22（fnm/nvm 自动识别） |
| `patches/` | oh-my-openagent 补丁（hephaestus GLM 支持） |
| `opencode-export.sh` | 配置导出脚本（`make export` 调用，打包 tar.gz 供新机恢复） |
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

> **迁移原则**：配置文件都进 git，新机器 `git clone` + `make install` 即可。`opencode-mem.jsonc` 不入 git（由 `make mem` 从模板生成，保持 `.template` 作权威源），避免本地实例澉移污染 git 历史。

## 快速开始（新机器）

> 装好 Node.js ≥22 和 opencode 后，5 步搞定全部配置。**第 3 步关键**：opencode 首次启动才创建 plugin 缓存，补丁才能同步进去。

```bash
git clone <你的仓库地址> ~/.config/opencode
cd ~/.config/opencode

make install                              # 一键：依赖 + 环境变量 + 记忆配置 + 飞书 CLI
opencode auth login zhipuai-coding-plan   # 登录智谱凭证（同时初始化 opencode 进程）
opencode                                  # 启动一次 TUI（装载 plugin 创建缓存），随即退出（Ctrl+C 或 /exit）
make patch-sync                           # 同步 hephaestus GLM 补丁到 opencode 缓存（两处）
make check                                # 体检（12 项全绿即就绪）
```

`make install` 依次执行：

| 步骤 | 子命令 | 做什么 |
|---|---|---|
| 1 | `make deps` | npm install + patch-package（hephaestus GLM 补丁）+ opencode-mem 全局装 + 软链 |
| 2 | `make config` | 交互式输入 3 个 API key → 写入 `~/.zshrc` + `launchctl setenv` |
| 3 | `make mem` | 从模板生成 `opencode-mem.jsonc`（智谱直连，复用 `Z_AI_API_KEY`） |
| 4 | `make feishu` | 飞书 CLI + 27 个 SKILL |
| 5 | `make sync-skills` | 软链 oh-my-openagent 内置 skill 到 `~/.agents/skills/`（让 `ulw-plan` / `git-master` / `frontend` 等 17 个在 TUI 可见） |

> API key 获取：[火山引擎](https://console.volcengine.com/ark) ｜ [智谱](https://www.bigmodel.cn/usercenter/apikeys) ｜ [飞书](https://open.feishu.cn/app/<YOUR_APP_ID>)

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
| `make check` | 体检（12 项：环境 / 变量 / 依赖 / 补丁 / 记忆 / MCP / 飞书 / Web UI / 漂移检测 / skills.lock 校验 / skill 软链 / plugin 缓存健康） |
| `make update` | 更新依赖到最新（清 node_modules 重装） |
| `make deps` | 仅装 npm 依赖 + opencode-mem 软链 |
| `make config` | 仅配置环境变量（交互式） |
| `make mem` | 仅生成 `opencode-mem.jsonc` |
| `make feishu` | 仅装飞书 CLI + SKILL |
| `make sync-skills` | 软链 oh-my-openagent 内置 skill 到 `~/.agents/skills/`（修 ulw-plan 等 TUI 不可见问题） |
| `make clean` | 清理 node_modules |
| `make export` | 导出配置到 tar.gz（默认 ~/Desktop，可选含 auth.json） |
| `make audit` | npm 安全审计（切官方源，绕过 npmmirror audit 404） |
| `make skills-lock` | 生成 lark skills SHA256 锁定（供应链加固） |
| `make clean-state` | 清理 `.omo/` 和 tasks/ 运行时状态（修复状态机污染） |
| `make sbom` | 生成 SBOM（软件物料清单，CycloneDX 格式） |
| `make tui-sync` | 验证 tui.json 与 opencode.json plugin 同步 |

### 手动分步（备选）

> `make install` 某步失败时可单独执行对应命令。以下是底层逻辑说明。

**环境变量**（`make config` 底层）：交互式写入 `~/.zshrc`。用 `.zshrc` 而非 `.zshenv`（opencode 从终端启动加载 `.zshrc`；GUI 场景由 `launchctl setenv` 覆盖）。脚本幂等，重复运行替换旧块而非追加。

**opencode-mem 记忆配置**（`make mem` 底层）：从 `opencode-mem.jsonc.template` 复制，已是智谱直连配置（`glm-5-turbo` + `bigmodel.cn` + `env://Z_AI_API_KEY`），无需手动改注释。

> **为什么用智谱直连而非 `opencodeProvider` 模式？**
> `opencodeProvider` 要求 provider 支持 structured output 协议，智谱 GLM 不支持会报 `prompt response missing info`。
> 改用智谱直连 OpenAI-compatible 接口绕过此限制，复用 `Z_AI_API_KEY` 无需额外 API key。

**飞书 CLI**（`make feishu` 底层）：见 `setup-feishu-cli.sh`。Bot 身份无需审批即可读文档。

**oh-my-openagent 版本锁定**：`package.json` 精确锁定 `4.12.1`（非 `^4.12.1`），因 `patches/oh-my-openagent+4.12.1.patch` 修改 `isHephaestusSupportedModel` 让 hephaestus agent 支持 GLM 模型。patch-package 按文件名版本匹配，升级需同步更新补丁。

### 如何升级 oh-my-openagent 主版本

> patch-package 按文件名锁版本（`patches/oh-my-openagent+X.Y.Z.patch`），升级时需重生成补丁。

```bash
# 1. 改 package.json 的 oh-my-openagent 版本号
# 2. 删除旧 patch
rm patches/oh-my-openagent+*.patch

# 3. 重装依赖（含 postinstall: patch-package + 全局 MCP）
make update

# 4. 验证 hephaestus GLM 补丁是否仍需要（看 isHephaestusSupportedModel 是否已原生支持 /glm/i）
grep -A2 "isHephaestusSupportedModel" node_modules/oh-my-openagent/dist/index.js | head -10

# 5a. 若上游已支持 GLM：补丁不再需要，删除 patches/ 引用，跳到第 7 步
# 5b. 若仍需要：手动编辑 node_modules/oh-my-openagent/dist/index.js
#    在 isHephaestusSupportedModel 函数的 return 语句末尾追加：|| /glm/i.test(modelName)

# 6. 生成新 patch
npx patch-package oh-my-openagent
#    会生成 patches/oh-my-openagent+<新版本>.patch

# 7. 提交：package.json + patches/oh-my-openagent+<新版本>.patch
# 8. 体检：make check
```
---

## API key 获取地址

| 变量 | 服务 | 获取地址 |
|---|---|---|
| `VOLC_API_KEY` | 火山引擎 Ark | https://console.volcengine.com/ark |
| `Z_AI_API_KEY` | 智谱 BigModel | https://www.bigmodel.cn/usercenter/apikeys |
| `FEISHU_APP_SECRET` | 飞书开放平台 App Secret | https://open.feishu.cn/app/<YOUR_APP_ID> |

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

### `ulw-plan` / `git-master` / `frontend` 等 OMO skill 不见了
→ plugin 加载链问题。OMO plugin 启动时通过 `discoverSharedSkills()` 扫描自己的 `dist/skills/`（17 个 skill），缓存损坏 / `@latest` 漂移 / 补丁冲突会让 shared scope 整批消失。
→ 一键诊断：`make check` 第 12 项检测三处 dist/skills 完整性（项目锁定 + builtin 缓存 + plugin 缓存，17×3），第 11 项自动自愈软链。
→ 修复优先级：
  - 第 12 项 fail（缓存损坏）→ `make update + make patch-sync`（治根）
  - 第 11 项自愈（软链丢）→ 自动重建，无需手动（兑底）

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

## plugin `@latest` 漂移检测（`make check` 第 9 项）

`opencode.json` / `tui.json` 用 `@latest` 标签加载 plugin，opencode 会绕过项目 `package-lock.json`，从 `~/.cache/opencode/packages/<plugin>@latest/` 加载运行时版本。`make check` 第 9 项比较：
- 项目软链 `node_modules/opencode-mem`（`npm i -g` 装的全局版本）
- opencode 缓存 `~/.cache/opencode/packages/opencode-mem@latest/node_modules/opencode-mem/`（`@latest` 拉到的版本）

两者不一致时警告：`@latest 已漂移，opencode 启动会加载缓存版本而非软链版本`。处理方式：`make update` 重装同步，或手动删缓存 `find ~/.cache/opencode/packages/opencode-mem@latest -delete`。

## @latest 缓存加载机制与 patch-sync

> **关键**：opencode 运行时不读项目 `node_modules`，而是从 `~/.cache/opencode/packages/` 加载 plugin。oh-my-openagent 的 hephaestus GLM 补丁打在项目 `node_modules/`，**必须手动同步到 opencode 缓存**才能生效。

### opencode 有**两处**缓存位置（都要同步）

OMO 在 npm 上 dual-publish 两个包名（官方主名 `oh-my-openagent` + 兼容名 `oh-my-opencode`），opencode 加载时两处都会出现：

| 位置 | 路径 | 来源 |
|---|---|---|
| **builtin** | `~/.cache/opencode/packages/node_modules/oh-my-opencode/dist/index.js` | opencode 主进程内置装（用兼容名） |
| **plugin** | `~/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js` | opencode.json plugin 字段触发装（用主名） |

opencode 实际加载哪个不固定，所以 `make patch-sync` **同步两处**，`make check` 第 4 项要求**两处都有补丁**。

### 问题表现

- 项目 `patches/oh-my-openagent+4.12.1.patch` 只打在 `node_modules/oh-my-openagent/dist/index.js`
- opencode 不读项目 `node_modules`，读自己的缓存
- 缓存版本缺 `|| /glm/i.test(modelName)` → hephaestus agent 的 GLM 模型被 `isHephaestusSupportedModel` 门控拒绝 → agent 被静默跳过

### 修复：`make patch-sync`

```bash
make patch-sync    # 同步项目补丁到 opencode 两处缓存
```

何时运行：

- 首次 `make install` 后启动 opencode 一次，退出，再跑
- opencode 升级后（缓存可能被刷新覆盖）
- 缓存被清空后
- `make check` 第 4 项报警时

### `package-lock.json` 是「装饰性的」

`package-lock.json` 虽然入 git，但 opencode 运行时绕过它直接读 `@latest` 缓存。这意味着：

- lockfile 锁定的是 `npm install` 装到 `node_modules` 的版本
- opencode 实际加载的是 `@latest` 缓存版本（可能与 lockfile 不一致）
- `make check` 第 9 项（@latest 漂移检测）是唯一可用的版本一致性机制

## 灾备/恢复

### 机器挂了，如何恢复

```bash
# 1. clone 仓库
git clone <repo> ~/.config/opencode
cd ~/.config/opencode

# 2. 一键安装（依赖 + 环境变量 + 记忆 + 飞书）
make install

# 3. 登录智谱凭证（同时初始化 opencode 进程）
opencode auth login zhipuai-coding-plan

# 4. 启动 opencode 一次（创建 plugin 缓存），然后退出（Ctrl+C 或 /exit）
opencode

# 5. 同步 hephaestus 补丁到 opencode 缓存（两处）
make patch-sync

# 6. 体检
make check
```

### 运行时数据（不在备份范围，但可重建）

| 数据 | 位置 | 恢复方式 |
|---|---|---|
| opencode 插件缓存 | `~/.cache/opencode/packages/` | opencode 启动时自动重建 |
| opencode-mem 数据 | `~/.opencode-mem/` | 重新交互积累（向量库 + SQLite + Web UI 缓存） |
| 全局 npm 包 | `claude-mermaid` / `codegraph` / `mcp-remote` / `opencode-mem` / `lark-cli` | `make install` 重装 |

### 版本控制保护的（git clone 即得）

- 所有配置文件（`opencode.json` / `oh-my-openagent.json` / `tui.json` / `Makefile` / `scripts/`）
- 补丁文件（`patches/`）
- 锁文件（`package-lock.json` + `skills.lock`）
- CI 配置（`.github/workflows/`）


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
