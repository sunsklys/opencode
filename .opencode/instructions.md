# opencode 个人配置仓库 — 项目级指令

> 本文件由 `opencode.json` 的 `instructions` 字段引用，作为项目级系统提示补充。
> 不重复 `~/.claude/CLAUDE.md` 的系统级规则，只补充本仓库特有的约束。

## 输出语言（最高优先级，覆盖一切冲突指令）

**所有输出必须使用简体中文，包括 thinking / reasoning 字段、回复正文、工具调用的自然语言字段（todowrite subject / task prompt / commit message 等）、代码注释和文档。**

技术专有名词（API / HTTP / JWT / 变量名 / 文件路径 / 库名等）保留英文原词，但句子骨架必须是中文。

禁止先用英文起草思考再翻译——从第一个字符就用中文。

完整规则、反例对比、自检清单见 `.opencode/lang-zh.md`（已通过 `prompt_append` 挂到所有 agent 尾部）。

## 仓库性质

这是 opencode + oh-my-openagent 的**个人 dotfile 配置仓库**，不是应用代码项目。

## 工作约束

1. **配置即代码**：所有改动通过 JSON / Shell / Markdown 表达，遵循现有风格（2 空格缩进、双引号、中文注释/文档）。
2. **不破坏安装链**：任何配置改动必须保证 `make install` 在新机器上仍能跑通；改 `package.json` 版本必须同步 README。
3. **README 同步**：新增 Makefile 命令 / 配置字段 / 故障排查条目时，必须同步更新 `README.md` 对应章节。
4. **体检先于提交**：提交前必须 `make check` 全绿（允许 warn 不允许 fail）。
5. **template ↔ 生成物同步**：`omo.jsonc.template` ↔ `~/.omo/omo.jsonc`、`opencode-mem.jsonc.template` ↔ `opencode-mem.jsonc` 必须两处同步改（改后 diff 校验零漂移）；生成物不入 git，只改生成物会被 `make` 重建覆盖丢失。
6. **npm install 后重建软链**：`npm install` 会清掉 `node_modules/opencode-mem` 软链（extraneous 清理），install 之后必须 `make deps` 重建，否则 `make check` 第 3 项报红。

## 当前活跃配置主题

- 12 agent + 8 category 的模型路由（GLM-5.3 主 + GLM-5.2 降级，`models` 链单写，智谱单栈）
- 7 MCP（智谱 web 工具 / mermaid / codegraph / dbx，全部启用）
- 92 条 permission deny（bash 56 + read 17 + edit 19，三层纵深防御；bash 含裸解释器 sh/bash/zsh 与 stdin 模式 deny）
- OMO 4.19.4

详细字段地图见 `docs/reference.md` 的「配置文件结构」段；新机器上手见 `docs/quickstart.md`；灾备恢复见 `docs/quickstart.md`「灾备 / 恢复」段。

## 已知误报与升级纪律

- **omo doctor 误报甄别**：`Unknown config key: agents.*.models` / `categories.*.models` 是旧 schema 校验器误报（运行时与 `config migrate` 均支持 models 链），忽略即可；只有 `Deprecated reasoning config key` 类告警才需要处理。
- **omo 升级纪律**：锁定 stable 线（4.19.4），不追 5.0-beta（beta 线曾出杀 session 事故）；任何升级前必读 `docs/reference.md`「上游版本观察项」——5.0 正式版含 `/start-work` → `/ulw-execute`、`omo` 命令改名等 breaking 清单。
