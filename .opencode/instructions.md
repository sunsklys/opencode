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

## 当前活跃配置主题

- 11 agent + 8 category 的模型路由（GLM-5.2 主，DeepSeek-V4-Pro 兜底）
- 7 MCP（智谱 web 工具 / mermaid / codegraph / dbx，全部启用）
- 84 条 permission deny（bash 49 + read 17 + edit 18，三层纵深防御）
- OMO 4.19.0

详细字段地图见 `README.md` 的「配置文件结构」段。
