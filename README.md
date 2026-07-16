# opencode 个人配置仓库

我的 opencode 配置（智谱 + 火山引擎 + 国产全模型路由）。

## 包含什么

| 文件 | 说明 |
|---|---|
| `opencode.json` | provider 定义（火山引擎 8 模型）+ 8 MCP 条目（7 启用 + chrome-mcp 默认禁用）+ 2 plugin + LSP + permission |
| `oh-my-openagent.json` | 11 agent + 8 category 路由（sisyphus / oracle / metis 等跨厂家 fallback） |
| `tui.json` | 主题配置 |
| `setup-feishu-cli.sh` | 飞书 CLI + SKILL 一键安装脚本 |
| `package.json` | oh-my-openagent 4.18.1（精确锁定）+ @opencode-ai/plugin 1.18.2（精确锁定）+ postinstall 全局依赖 |
| `package-lock.json` | npm 精确依赖版本 |
| `Makefile` | 一键安装 / 体检 / 更新编排（`make install` / `make check` / `make update`） |
| `scripts/*.sh` | 安装 / 环境变量 / 体检脚本（被 Makefile 调用） |
| `opencode-mem.jsonc.template` | 智谱直连模板（`make mem` 生成 `opencode-mem.jsonc`） |
| `.nvmrc` | 锁定 Node.js v22（fnm/nvm 自动识别） |
| `opencode-export.sh` | 配置导出脚本（`make export` 调用，打包 tar.gz 供新机恢复） |
| `docs/` | 详细文档（见下） |

**不包含**（已被 .gitignore 排除）：
- `auth.json` - opencode 登录凭证
- `node_modules/` - 依赖（新机器 npm install 重建）
- `opencode.db` - 会话历史
- `opencode-mem.jsonc` - 本地持久记忆配置（`make mem` 从模板自动生成，智谱直连）
- `~/.opencode-mem/` - opencode-mem 数据目录（向量库 + SQLite + Web UI 缓存）

## 快速开始

新机器装好 Node.js ≥22 + opencode 后，5 步搞定 → **[docs/quickstart.md](./docs/quickstart.md)**

一句话流程：`git clone` → `make install` → `opencode auth login zhipuai-coding-plan` → `opencode` → `make check`。

## 详细文档

| 文档 | 用途 |
|---|---|
| [docs/quickstart.md](./docs/quickstart.md) | 新机器安装 / Makefile 命令速查 / Git Hooks / 多机同步 |
| [docs/reference.md](./docs/reference.md) | 配置文件字段地图 / experimental 归属 / 超时对照 / 功能开关 / 角色路由 / MCP 信任边界 / @latest 缓存机制 / 升级流程 |
| [docs/troubleshooting.md](./docs/troubleshooting.md) | 常见报错和修复路径 |

## 灾备 / 恢复

机器挂了，三步恢复：

```bash
git clone <repo> ~/.config/opencode && cd ~/.config/opencode
make bootstrap         # install + prime-cache + check
opencode auth login zhipuai-coding-plan && opencode
```

> 详细说明（含运行时数据表 / git 保护范围 / 手动分步备选）已迁移到 [docs/quickstart.md](./docs/quickstart.md) 的「灾备 / 恢复」段。
