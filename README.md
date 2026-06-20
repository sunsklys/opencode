# opencode 个人配置仓库

我的 opencode 配置（智谱 + 火山引擎 + 国产全模型路由）。

## 包含什么

| 文件 | 说明 |
|---|---|
| `opencode.json` | provider 定义（火山引擎 9 模型）+ 8 MCP + 2 plugin + LSP + permission |
| `oh-my-openagent.json` | 12 agent + 8 category 路由（sisyphus / oracle / metis 等跨厂家 fallback） |
| `tui.json` | 主题配置 |
| `setup-feishu-cli.sh` | 飞书 CLI + SKILL 一键安装脚本 |
| `package.json` | OMO 依赖版本锁（^4.12.0）+ postinstall 全局依赖 |
| `package-lock.json` | npm 精确依赖版本 |
**不包含**（已被 .gitignore 排除）：
- `auth.json` - opencode 登录凭证
- `node_modules/` - 依赖（新机器 npm install 重建）
- `opencode.db` - 会话历史
- `opencode-mem.jsonc` - 本地持久记忆配置（含 API key 占位符，需手动改国产模型）
- `~/.opencode-mem/` - opencode-mem 数据目录（向量库 + SQLite + Web UI 缓存）

---

## 新机器迁移步骤

### 1. 前置依赖

```bash
# Node.js (推荐 fnm 管理，opencode 需要 ≥22)
curl -fsSL https://fnm.vercel.app/install | bash
fnm install 22
fnm default 22

# opencode 主程序
curl -fsSL https://opencode.ai/install | bash
# 或: npm i -g opencode-ai

# 验证
node --version  # v22.x
opencode --version  # ≥ 1.16.x
```

### 2. 克隆配置

```bash
mkdir -p ~/.config
cd ~/.config
git clone <你的仓库地址> opencode
cd opencode
```

### 3. 安装依赖

```bash
npm install
# 会自动拉 oh-my-openagent ^4.12.0 + claude-mermaid 等所有依赖

# postinstall 会自动安装全局依赖（claude-mermaid, codegraph）
# 如果 postinstall 失败，手动安装：
# npm i -g claude-mermaid @colbymchenry/codegraph

# LSP 二进制（让 opencode 的 lsp_diagnostics/goto_definition/find_references/rename 可用）
# gopls 可选（Go 项目才需要）；typescript-language-server + pyright 几乎必装
npm i -g typescript-language-server pyright
# 可选：npm i -g gopls   # 或通过 nvim mason 装到 ~/.local/share/nvim/mason/bin/
# 可选：npm i -g eslint  # TS/JS 项目 lint

# opencode-mem plugin（本地持久记忆，本地 USearch 向量库，0 云成本）
# 直接 npm install 会触发 OMO 4.12.0 的 linux platform binary bug，需全局装 + 软链绕过：
npm i -g opencode-mem
ln -sf $(npm root -g)/opencode-mem node_modules/opencode-mem

### 4. 配置环境变量（直接写入 `~/.zshrc`）

> 不再使用 `.env` 文件中转。所有 API key 直接 export 到 `~/.zshrc`。

```bash
# 编辑 ~/.zshrc，在末尾追加：
cat >> ~/.zshrc << 'EOF'

# opencode 环境变量
export VOLC_API_KEY='ark-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
export Z_AI_API_KEY='xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.xxxxxxxxxxxxxxxx'
export FEISHU_APP_SECRET='你的App Secret'
# 同步给 macOS GUI 应用（IDE/从 Dock 启动的 opencode 也能继承）
launchctl setenv VOLC_API_KEY "$VOLC_API_KEY" 2>/dev/null
launchctl setenv Z_AI_API_KEY "$Z_AI_API_KEY" 2>/dev/null
launchctl setenv FEISHU_APP_SECRET "$FEISHU_APP_SECRET" 2>/dev/null
EOF

# 立即生效
source ~/.zshrc

# 验证
echo $VOLC_API_KEY
echo $Z_AI_API_KEY
echo $FEISHU_APP_SECRET
```

> **为什么用 `.zshrc` 而不是 `.zshenv`？**
> `.zshrc` 是交互式 shell 配置，opencode 从终端启动时会加载。
> 对于从 macOS GUI / IDE 启动的场景，上面的 `launchctl setenv` 会把变量
> 写入 launchd 进程环境，GUI 子进程能继承——所以两者结合覆盖全部场景。

> **GUI 应用继承**：上面 `launchctl setenv` 三行已经覆盖了从 Dock / IDE
> GUI 启动 opencode 的场景，无需额外操作。如果变量未同步，手动执行：
> ```bash
> launchctl setenv VOLC_API_KEY "$VOLC_API_KEY"
> launchctl setenv Z_AI_API_KEY "$Z_AI_API_KEY"
> launchctl setenv FEISHU_APP_SECRET "$FEISHU_APP_SECRET"
> ```
### 5. 安装飞书 CLI（可选）

> `FEISHU_APP_SECRET` 已在第 4 步写入 `~/.zshrc`，直接跑脚本即可。

```bash
bash setup-feishu-cli.sh
# 脚本会自动：安装 CLI → 安装 27 个 SKILL → 配置凭证 → 验证状态
```

> 飞书 CLI 用于在 OpenCode 中操作飞书文档、表格、日历、IM、邮件等。
> Bot 身份无需审批即可读取文档，脚本不会触发权限申请。

### 6. 登录 opencode 凭证
```bash
# 智谱 Coding Plan（必需，否则 9 个角色 fallback 全失效）
opencode auth login zhipuai-coding-plan
# 选择 zhipuai-coding-plan，输入对应 token
```

### 7. 验证

```bash
opencode
# 进入 TUI 后试一句话，看是否能正常路由到 sisyphus / oracle
```

### 8. 配置 opencode-mem（可选，本地持久记忆）

首次启动 opencode 后，plugin 会自动生成 `~/.config/opencode/opencode-mem.jsonc`，但默认是 OpenAI 占位符配置（auto-capture 会报错）。**需手动改成智谱直连**：

```bash
# 1. 启动 opencode 一次让模板生成（Ctrl+C 退出）
opencode

# 2. 编辑配置文件
$EDITOR ~/.config/opencode/opencode-mem.jsonc
# 找到 autoCaptureEnabled 附近的几行，改成：
#   - 注释掉默认的 memoryProvider/memoryModel/memoryApiUrl/memoryApiKey 四行（含 "sk-..." 占位符）
#   - 取消注释或新增以下 4 行（启用智谱直连）：
#       "memoryProvider": "openai-chat",
#       "memoryModel": "glm-5-turbo",
#       "memoryApiUrl": "https://open.bigmodel.cn/api/paas/v4",
#       "memoryApiKey": "env://Z_AI_API_KEY",
#
# 3. 重启 opencode，验证
curl http://127.0.0.1:4747/api/stats   # 返回 {"success":true,"data":{"total":0,...}} 即启动成功
# 跑几句对话后，total 应 > 0（说明 auto-capture 跑通了）
```

> **为什么用智谱直连而不是 `opencodeProvider` 模式？**
> `opencodeProvider` 模式（复用 opencode 已认证的 provider）要求 provider 支持 structured output 协议。
> 智谱 GLM 当前不支持，会报 `prompt response missing info` 错误。
> 改用智谱直连 OpenAI-compatible 接口（`memoryApiUrl` + `memoryApiKey`）绕过这个限制，
> 同时复用 `Z_AI_API_KEY` 环境变量，不需要额外 API key。

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
rm -rf node_modules package-lock.json  # 依赖有变化时全量重装
npm install
# 清理旧版 codegraph（如果之前装过错误的包名）
npm uninstall -g @anthropic-ai/codegraph 2>/dev/null

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
→ 用了 `opencodeProvider: "zhipuai-coding-plan"` 模式，但智谱不支持 structured output。
→ 解决：在 `~/.config/opencode/opencode-mem.jsonc` 改用智谱直连：
  - 注释掉 `opencodeProvider` 和 `opencodeModel` 两行
  - 启用 `memoryProvider/memoryModel/memoryApiUrl/memoryApiKey` 四件套（详见迁移步骤 8）
  - 重启 opencode

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

## 角色路由速查

| 场景 | 路由 |
|---|---|
| 主调度 (sisyphus) | GLM-5.2 (zhipu, high) |
| 架构/深度推理 (oracle/prometheus/momus/metis/plan) | GLM-5.2 (zhipu, max) |
| 高难度自主 (ultrabrain/deep) | GLM-5.2 (zhipu) |
| 创意/非常规 (artistry) | DeepSeek V4-Pro (high) |
| 编码实现 (hephaestus/atlas/sisyphus-junior/unspecified-high) | DeepSeek V4-Pro (high) |
| 多模态/前端 (multimodal-looker/visual-engineering) | GLM-5v-Turbo |
| 检索/轻量 (librarian/explore/quick/unspecified-low) | DeepSeek V4-Flash (low) |
| 写作 (writing) | GLM-5.2 |

> 所有 GLM-5.2 主模型均已配置 `volcengine-plan/glm-5.2` 作同模型跨 provider fallback（zhipuai 宕机先走火山通道保持模型一致，再退化到异构模型）。`max_fallback_attempts=4`。
