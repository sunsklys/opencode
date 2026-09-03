# opencode 个人配置仓库

我的 opencode 配置（智谱单栈全模型路由）。

## 包含什么

| 文件 | 说明 |
|---|---|
| `opencode.json` | 7 MCP 条目（全部启用）+ 3 plugin（superpowers 锁 #v6.3.0）+ LSP + permission（模型全部走智谱 coding plan，auth login 凭证） |
| `tui.json` | 主题配置 |
| `setup-feishu-cli.sh` | 飞书 CLI + SKILL 一键安装脚本 |
| `package.json` | oh-my-openagent 4.19.4（精确锁定）+ @opencode-ai/plugin 1.18.25（精确锁定）+ postinstall 全局依赖 |
| `package-lock.json` | npm 精确依赖版本 |
| `Makefile` | 一键安装 / 体检 / 更新编排（`make install` / `make check` / `make update`） |
| `scripts/` | 安装 / 环境变量 / 体检脚本（.sh，被 Makefile 调用）+ mem 维护（.mjs：`patch-mem-tags` 可重放 tags 兑底补丁，`fix-mem-untagged` 存量清理） |
| `opencode-mem.jsonc.template` | 智谱直连模板（`make mem` 生成 `opencode-mem.jsonc`） |
| `omo.jsonc.template` | OMO 统一配置模板（`make omo-config` 生成 `~/.omo/omo.jsonc`，含 12 agent + 8 category 路由） |
| `opencode-export.sh` | 配置导出脚本（`make export` 交互 / `HEADLESS=1` 无人值守三硬约束：强制排除 auth.json、落 ~/Backups/opencode/ 非 iCloud、retention 保 5；含 git 外四类内容） |
| `launchd/` | 周导出 + 月度 db-check 两个 launchd 任务模板（`make install-export-job` / `install-dbcheck-job` 装载） |
| `docs/` | 详细文档（见下） |

**不包含**（已被 .gitignore 排除）：
- `auth.json` - opencode 登录凭证
- `node_modules/` - 依赖（新机器 npm install 重建）
- `opencode.db` - 会话历史
- `opencode-mem.jsonc` - 本地持久记忆配置（`make mem` 从模板自动生成，智谱直连）
- `~/.opencode-mem/` - opencode-mem 数据目录（向量库 + SQLite + Web UI 缓存）
- `~/.omo/omo.jsonc` - OMO 统一配置（`make omo-config` 从模板自动生成，含 12 agent + 8 category 路由 + goal 禁用）

## 快速开始

新机器装好 Node.js ≥22 + opencode 后，5 步搞定 → **[docs/quickstart.md](./docs/quickstart.md)**

一句话流程：`git clone` → `make install` → `opencode auth login zhipuai-coding-plan` → `opencode` → `make check`。

## 详细文档

| 文档 | 用途 |
|---|---|
| [docs/quickstart.md](./docs/quickstart.md) | 新机器安装 / Makefile 命令速查 / Git Hooks / 多机同步 |
| [docs/reference.md](./docs/reference.md) | 配置文件字段地图 / experimental 归属 / 超时对照 / 功能开关 / 角色路由 / MCP 信任边界 / @latest 缓存机制 / 升级流程 |
| [docs/troubleshooting.md](./docs/troubleshooting.md) | 常见报错和修复路径 |
| [docs/usage.md](./docs/usage.md) | 日常使用指南 / 关键词触发 / 场景速查 / 避坑指南 / 配置事实索引 |

## opencode-mem pin+patch 机制（2026-09-02）

- **动机**：上游 2.25.0 四缺陷（tags 入库无兑底 / detect 零容忍 / run-batch 内存态 bug / turso 迁移重跑），本地防护而非根治
- **资产**：双 json spec `opencode-mem@2.25.0`；缓存目录 client.js 带 `PATCH(tags-fallback)`；`scripts/patch-mem-tags.mjs`（重放）；`scripts/fix-mem-untagged.mjs`（存量清理）
- **摘除判据**：上游 changelog 确认 tags 缺陷修复 → 双 spec 改回 `@latest` → 删 patch 脚本
- **重打命令**：`node scripts/patch-mem-tags.mjs`（幂等；升级 runbook 六步见 docs/reference.md）

## 灾备 / 恢复

机器挂了，三步恢复：

```bash
git clone <repo> ~/.config/opencode && cd ~/.config/opencode
make bootstrap         # install + prime-cache + check
opencode auth login zhipuai-coding-plan && opencode
```

> ⚠️ `.opencode/dbx.md`（DBX 数据库连接字典）不在 git 内（含生产 host），需从备份恢复或手动重建。
> 详细说明（含运行时数据表 / git 保护范围 / 手动分步备选）已迁移到 [docs/quickstart.md](./docs/quickstart.md) 的「灾备 / 恢复」段。

## 数据库维护

`opencode.db` 长期使用会膨胀（实测 1GB / event 表 16 万行会触发内嵌 Bun v1.3.14 的 NAPI panic 崩溃）。每月体检一次：

```bash
make db-check                          # 体检（只读，运行时安全）
make db-maintain CLEAN=1               # 维护（需先退出 opencode；清理 30 天前 session + VACUUM）
make db-maintain CLEAN=1 KEEP_DAYS=7   # 保留 7 天
make db-maintain CLEAN=1 INCREMENTAL=1 # 首次额外切 auto_vacuum=INCREMENTAL（未来自动增量回收）
make check-upgrade                     # 监控 opencode 新版 + 内嵌 Bun 是否已修复 NAPI bug
```

详见 [docs/troubleshooting.md](./docs/troubleshooting.md)「opencode 进程崩溃」段。
