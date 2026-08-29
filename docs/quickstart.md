# 快速开始

> 新机器 5 步装好全部配置。前置依赖装完后,`make install` 一条命令搞定。

## 前置依赖（`make install` 之前）

```bash
# Node.js v22
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

## 5 步装好

```bash
git clone <你的仓库地址> ~/.config/opencode
cd ~/.config/opencode

make install                              # 一键：依赖 + 环境变量 + 记忆配置 + 飞书 CLI
opencode auth login zhipuai-coding-plan   # 登录智谱凭证（同时初始化 opencode 进程）
opencode                                  # 启动验证（首次会初始化 plugin 缓存）
make check                                # 体检（13 项全绿即就绪）
```

### `make install` 依次执行

| 步骤 | 子命令 | 做什么 |
|---|---|---|
| 1 | `make deps` | npm install + opencode-mem 全局装 + 软链 |
| 2 | `make config` | 交互式输入 3 个 API key → 写入 `~/.zshrc` + `launchctl setenv` |
| 3 | `make mem` | 从模板生成 `opencode-mem.jsonc`（智谱直连，复用 `Z_AI_API_KEY`） |
| 4 | `make omo-config` | 从模板生成 `~/.omo/omo.jsonc`（OMO 统一配置，含 12 agent + 8 category 路由 + goal 禁用） |
| 5 | `make feishu` | 飞书 CLI + 27 个 SKILL |
| 6 | `make sync-skills` | 软链 oh-my-openagent 内置 skill 到 `~/.agents/skills/`（让 `ulw-plan` / `git-master` / `frontend` 等 20 个在 TUI 可见） |

## API key 获取地址

| 变量 | 服务 | 获取地址 |
|---|---|---|
| `Z_AI_API_KEY` | 智谱 BigModel | https://www.bigmodel.cn/usercenter/apikeys |
| `FEISHU_APP_SECRET` | 飞书开放平台 App Secret | https://open.feishu.cn/app/<YOUR_APP_ID> |

> 一行版：[智谱](https://www.bigmodel.cn/usercenter/apikeys) ｜ [飞书](https://open.feishu.cn/app/<YOUR_APP_ID>)

## Makefile 命令速查

| 命令 | 作用 |
|---|---|
| `make install` | 完整安装（新机器首次） |
| `make check` | 体检（13 项：环境 / 变量 / 依赖 / 记忆 / MCP / 飞书 / Web UI / 漂移检测 / skills.lock 校验 / skill 软链 / plugin 缓存健康 / OMO+opencode 字段验证 / superpowers 版本） |
| `make update` | 重装依赖（按 package.json 精确版本） |
| `make upgrade` | 升级 OMO + plugin 到 npm 最新（含 $schema URL 同步） |
| `make deps` | 仅装 npm 依赖 + opencode-mem 软链 |
| `make config` | 仅配置环境变量（交互式） |
| `make mem` | 仅生成 `opencode-mem.jsonc` |
| `make feishu` | 仅装飞书 CLI + SKILL |
| `make sync-skills` | 软链 oh-my-openagent 内置 skill 到 `~/.agents/skills/`（修 ulw-plan 等 TUI 不可见问题） |
| `make clean` | 清理 node_modules |
| `make export` | 导出配置到 tar.gz（默认 ~/Desktop，可选含 auth.json） |
| `make audit` | npm 安全审计（切官方源，绕过 npmmirror audit 404） |
| `make skills-lock` | 生成全部 skills SHA256 锁定（lark + OMO，供应链加固） |
| `make clean-state` | 清理 `.omo/` 和 tasks/ 运行时状态（修复状态机污染） |
| `make sbom` | 生成 SBOM（软件物料清单，CycloneDX 格式） |
| `make tui-sync` | 验证 tui.json 与 opencode.json plugin 同步 |

## Git Hooks（可选）

Pre-commit hook 会在每次 `git commit` 前自动跑 `make check`（critical 全绿）+ `make tui-sync`（plugin 同步），
失败则阻止 commit，防止损坏配置进入 git 历史。

```bash
bash scripts/install-hooks.sh   # 安装 pre-commit hook
```

安装后效果：
```bash
git commit -m "update: xxx"
# ▶ Running make check (critical tier) + make tui-sync...
# ✅ Pre-commit checks passed.
# [main 1234567] update: xxx
```

> hook 源文件在 `.githooks/pre-commit`，安装脚本复制到 `.git/hooks/pre-commit`。
> 每个 clone 都需要运行一次 `scripts/install-hooks.sh`。

## 多机同步

```bash
# 改了配置后
cd ~/.config/opencode
git add . && git commit -m "update: xxx" && git push

# 另一台机器拉新版
cd ~/.config/opencode
git pull
make update    # 清 node_modules 重装 + opencode-mem 软链
make check     # 体检全绿
```

## 灾备 / 恢复

### 机器挂了，如何恢复

```bash
# 1. clone 仓库
git clone <repo> ~/.config/opencode
cd ~/.config/opencode

# 2. 一键 bootstrap（install + prime-cache + check）
make bootstrap

# 3. 登录智谱凭证（同时初始化 opencode 进程）
opencode auth login zhipuai-coding-plan

# 4. 启动 opencode 验证
opencode
```
> ⚠️ `.opencode/dbx.md`（DBX 数据库连接字典）不在 git 内（含生产 host），**唯一备份通道是 `make export` 导出包**（2026-08-29 起已包含，见下）；平时改完 dbx.md 建议顺手跑一次 `make export`。
> ⚠️ `~/.omo/omo.jsonc` 已由 `make install` 自动从模板生成（含 12 agent + 8 category 路由、goal 禁用等自定义配置）。

### git 外文件的备份通道：`make export`（2026-08-29 增强）

导出包（约 3.6MB tar.gz，默认输出 ~/Desktop）覆盖 git 拿不到的四类内容：

| 包内路径 | 内容 | 对应 git 状态 |
| --- | --- | --- |
| `config/opencode/.opencode/` | dbx.md（生产 host）+ glm-max.ts + instructions/lang-zh | 前者不入 git，后三者在 git（双保险） |
| `agents/skills/` | 54 个用户 skill 目录（29 个 SKILL.md，含 ast-grep/frontend/hooloo 等自定义 skill 唯一副本；排除 .git/.DS_Store） | 不在 git |
| `opencode-mem/data/user-profiles.db*` | opencode-mem 用户画像（交互询问，默认含；向量库 1.5GB 不导） | 不在 git |
| `data/opencode/auth.json` | 登录凭证（交互询问，默认不含） | 不在 git |

仍需手动（不在这两条通道内）：环境变量值（`make config` 交互输入）、DBX 桌面 app 内重建 8 条连接（字典见 dbx.md）、`gh auth login`。

新机恢复：解压包后按包内 `README.md` 执行（拷贝 `.opencode/` + `agents/skills/` + 可选画像 → `make install` → `make config` → `make check`）。

> 手动分步（备选，等价于 `make bootstrap`）：
>
> ```bash
> # 1. clone 仓库
> git clone <repo> ~/.config/opencode
> cd ~/.config/opencode
>
> # 2. 一键安装（依赖 + 环境变量 + 记忆 + 飞书）
> make install
>
> # 3. 登录智谱凭证（同时初始化 opencode 进程）
> opencode auth login zhipuai-coding-plan
>
> # 4. 启动 opencode 验证
> opencode
>
> # 5. 体检
> make check
> ```

### 运行时数据（不在备份范围，但可重建）

| 数据 | 位置 | 恢复方式 |
|---|---|---|
| opencode 插件缓存 | `~/.cache/opencode/packages/` | opencode 启动时自动重建 |
| opencode-mem 数据 | `~/.opencode-mem/` | 重新交互积累（向量库 + SQLite + Web UI 缓存） |
| 全局 npm 包 | `claude-mermaid` / `codegraph` / `opencode-mem` / `lark-cli` | `make install` 重装 |

### 版本控制保护的（git clone 即得）

- 所有配置文件（`opencode.json` / `tui.json` / `Makefile` / `scripts/`；OMO 统一配置在 `~/.omo/omo.jsonc`，不入 git）
- 锁文件（`package-lock.json` + `skills.lock`）
- CI 配置（`.github/workflows/`）

