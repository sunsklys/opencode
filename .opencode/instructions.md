# opencode 个人配置仓库 — 项目级指令

> 本文件由 `opencode.json` 的 `instructions` 字段引用，作为项目级系统提示补充。
> 不重复 `~/.claude/CLAUDE.md` 的系统级规则，只补充本仓库特有的约束。

## 仓库性质

这是 opencode + oh-my-openagent 的**个人 dotfile 配置仓库**，不是应用代码项目。

## 工作约束

1. **配置即代码**：所有改动通过 JSON / Shell / Markdown 表达，遵循现有风格（2 空格缩进、双引号、中文注释/文档）。
2. **不破坏安装链**：任何配置改动必须保证 `make install` 在新机器上仍能跑通；改 `package.json` 版本必须同步 README。
3. **README 同步**：新增 Makefile 命令 / 配置字段 / 故障排查条目时，必须同步更新 `README.md` 对应章节。
4. **体检先于提交**：提交前必须 `make check` 全绿（允许 warn 不允许 fail）。

## 当前活跃配置主题

- 11 agent + 8 category 的模型路由（GLM-5.2 主，DeepSeek-V4-Pro 兜底）
- 8 MCP（智谱 web 工具 / notion / mermaid / codegraph）
- 83 条 permission deny（bash 43 + read 22 + edit 18，三层纵深防御）
- OMO 4.18.1

详细字段地图见 `README.md` 的「配置文件结构」段。
