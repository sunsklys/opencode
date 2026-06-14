# opencode 个人配置仓库

我的 opencode 配置（智谱 + 火山引擎 + 国产全模型路由）。

## 包含什么

| 文件 | 说明 |
|---|---|
| `opencode.json` | provider 定义（火山引擎 6 模型）+ MCP 服务 + plugin |
| `oh-my-openagent.json` | 12 agent + 8 category 路由（sisyphus / oracle / metis 等跨厂家 fallback） |
| `tui.json` | 主题配置 |
| `setup-feishu-cli.sh` | 飞书 CLI + SKILL 一键安装脚本 |
| `package.json` | OMO 依赖版本锁（^4.8.1）+ postinstall 全局依赖 |
| `package-lock.json` | npm 精确依赖版本 |
**不包含**（已被 .gitignore 排除）：
- `auth.json` - opencode 登录凭证
- `node_modules/` - 依赖（新机器 npm install 重建）
- `opencode.db` - 会话历史

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
# 会自动拉 oh-my-openagent ^4.8.1 + claude-mermaid 等所有依赖

# postinstall 会自动安装全局依赖（claude-mermaid, codegraph）
# 如果 postinstall 失败，手动安装：
# npm i -g claude-mermaid @colbymchenry/codegraph
```

### 4. 配置 API key

```bash
# 创建 ~/.zshenv（所有 zsh 实例均生效，非交互 shell 也会加载）
cat > ~/.zshenv << 'EOF'
# 火山引擎 Ark API
export VOLC_API_KEY='ark-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'

# 智谱 AI API
export Z_AI_API_KEY='xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.xxxxxxxxxxxxxxxx'

# 飞书 CLI App Secret（可选）
export FEISHU_APP_SECRET='你的App Secret'
EOF

# 立即生效
source ~/.zshenv

# 验证
echo $VOLC_API_KEY
echo $Z_AI_API_KEY
```

> 如果从 macOS GUI 启动 opencode，还需让 GUI 应用也能继承变量：
> ```bash
> launchctl setenv VOLC_API_KEY "$VOLC_API_KEY"
> launchctl setenv Z_AI_API_KEY "$Z_AI_API_KEY"
> ```
### 5. 安装飞书 CLI（可选）

```bash
# 设置环境变量（App Secret 请从飞书开放平台获取）
export FEISHU_APP_SECRET='你的App Secret'
bash setup-feishu-cli.sh
# 脚本会自动：安装 CLI → 安装 27 个 SKILL → 配置凭证 → 登录授权
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

---

## API key 获取地址

| 变量 | 服务 | 获取地址 |
|---|---|---|
| `VOLC_API_KEY` | 火山引擎 Ark | https://console.volcengine.com/ark |
| `Z_AI_API_KEY` | 智谱 BigModel | https://www.bigmodel.cn/usercenter/apikeys |

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
→ 解决：确认 `~/.zshenv` 存在且内容正确，然后 `source ~/.zshrc` 或重开终端。
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
→ 运行 `bash setup-feishu-cli.sh`（需先设置 `FEISHU_APP_SECRET` 环境变量）。
---

## 角色路由速查

| 场景 | 路由 |
|---|---|
| 主调度 (sisyphus) | DeepSeek V4-Pro |
| 架构/深度推理 (oracle/prometheus/momus/metis/plan/ultrabrain/deep/artistry/unspecified-high) | DeepSeek V4-Pro |
| 编码实现 (hephaestus/atlas/sisyphus-junior) | DeepSeek V4-Pro |
| 多模态/前端 (multimodal-looker/visual-engineering) | GLM-5v-Turbo |
| 检索/轻量 (librarian/explore/quick/unspecified-low) | DeepSeek V4-Flash |
| 写作 (writing) | GLM-5.1 |
