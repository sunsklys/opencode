# opencode 个人配置仓库

我的 opencode 配置（智谱 + 火山引擎 + 国产全模型路由）。

## 包含什么

| 文件 | 说明 |
|---|---|
| `opencode.json` | provider 定义（火山引擎 11 模型）+ MCP 服务 + plugin |
| `oh-my-openagent.json` | 11 agent + 8 category 路由（sisyphus / oracle / metis 等跨厂家 fallback） |
| `tui.json` | 主题配置 |
| `package.json` | OMO 依赖版本锁（^4.7.5）+ postinstall 全局依赖 |
| `package-lock.json` | npm 精确依赖版本 |
| `.env.example` | 环境变量模板（不含真实值） |

**不包含**（已被 .gitignore 排除）：
- `.env` - 含真实 API key（敏感！）
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
# 会自动拉 oh-my-openagent ^4.7.5 + claude-mermaid 等所有依赖

# postinstall 会自动安装全局依赖（claude-mermaid, codegraph）
# 如果 postinstall 失败，手动安装：
# npm i -g claude-mermaid @anthropic-ai/codegraph
```

### 4. 配置 API key

```bash
# 复制模板
cp .env.example .env

# 编辑填入真实 key
vim .env  # 或 nano .env

# 让 shell 自动加载（重要！）
# 在 ~/.zshrc 末尾添加这一行：
echo 'set -a; [ -f ~/.config/opencode/.env ] && source ~/.config/opencode/.env; set +a' >> ~/.zshrc

# 立即生效
source ~/.zshrc

# 验证环境变量已加载
echo $VOLC_API_KEY
echo $Z_AI_API_KEY
```

### 5. 登录 opencode 凭证

```bash
# 智谱 Coding Plan（必需，否则 9 个角色 fallback 全失效）
opencode auth login zhipuai-coding-plan
# 选择 zhipuai-coding-plan，输入对应 token
```

### 6. 验证

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
npm install  # 如果 package.json 有变化
```

---

## 故障排查

### `opencode` 启动报 "missing apiKey"
→ 环境变量没加载。检查 `echo $VOLC_API_KEY` 是否为空。
→ 解决：`source ~/.zshrc` 或重开终端。

### 智谱模型调不通
→ 没执行 `opencode auth login zhipuai-coding-plan`。
→ 解决：执行上面命令重新认证。

### npm install 卡住
→ 国内网络问题。
→ 解决：`npm config set registry https://registry.npmmirror.com`

### MCP 服务报错（mermaid / codegraph 不可用）
→ 全局依赖未安装。检查 `which claude-mermaid` 和 `which codegraph`。
→ 解决：`npm i -g claude-mermaid @anthropic-ai/codegraph`

---

## 角色路由速查

| 场景 | 路由 |
|---|---|
| 主调度 (sisyphus) | DeepSeek V4-Pro |
| 架构/深度推理 (oracle/hephaestus/prometheus/momus/metis/plan/ultrabrain/deep/artistry/unspecified-high) | DeepSeek V4-Pro |
| 通用编码 (atlas/sisyphus-junior/writing) | GLM-5.1 |
| 多模态/前端 (multimodal-looker/visual-engineering) | GLM-5v-Turbo |
| 检索/轻量 (librarian/explore/quick) | DeepSeek V4-Flash |
| 轻量通用 (unspecified-low) | GLM-5-Turbo |
