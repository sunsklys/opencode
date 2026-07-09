# 故障排查

> 常见报错和修复路径。如果这里没有，先跑 `make check` 看 12 项体检哪一项 fail。

## `opencode` 启动报 "missing apiKey"

→ 环境变量没加载。检查 `echo $VOLC_API_KEY` 是否为空。
→ 解决：确认 `~/.zshrc` 里的 `export VOLC_API_KEY=...` 存在且正确，然后 `source ~/.zshrc` 或重开终端。
→ 如果从 LazyVim/Neovim GUI 启动，还需确认 `launchctl getenv VOLC_API_KEY` 有值。

## 智谱模型调不通

→ 没执行 `opencode auth login zhipuai-coding-plan`。
→ 解决：执行上面命令重新认证。

## npm install 卡住

→ 国内网络问题。
→ 解决：`npm config set registry https://registry.npmmirror.com`

## MCP 服务报错（mermaid / codegraph 不可用）

→ 全局依赖未安装。检查 `which claude-mermaid` 和 `which codegraph`。
→ 解决：`npm i -g claude-mermaid @colbymchenry/codegraph`

## 飞书 CLI 读文档报权限错误

→ Bot 身份不需要审批，直接用 `--as bot` 即可。
→ 用户身份敏感权限（多维表格、审批等）需要管理员审批。
→ 解决：`lark-cli auth status` 查看当前状态。

## 飞书 CLI 在新电脑上提示未配置

→ 运行 `bash setup-feishu-cli.sh`（`FEISHU_APP_SECRET` 需已在 `~/.zshrc` 中配置）。

## opencode-mem 报 `prompt response missing info`

→ `opencode-mem.jsonc` 用了 `opencodeProvider` 模式，但智谱不支持 structured output。
→ 解决：`rm opencode-mem.jsonc && make mem` 重新生成智谱直连配置，重启 opencode。

## opencode 启动报 `Missing key lsp.xxx.command`

→ `opencode.json` 的 `lsp` 字段格式错误（每个 LSP 条目必须有 `command` 字段）。
→ 解决：直接用 `"lsp": true` 让 opencode 自动检测启用所有内置 LSP，不要手动列各语言。

## `ulw-plan` / `git-master` / `frontend` 等 OMO skill 不见了

→ plugin 加载链问题。OMO plugin 启动时通过 `discoverSharedSkills()` 扫描自己的 `dist/skills/`（18 个 skill），缓存损坏 / `@latest` 漂移会让 shared scope 整批消失。
→ 一键诊断：`make check` 第 10 项检测三处 dist/skills 完整性（项目锁定 + builtin 缓存 + plugin 缓存，18×3），第 9 项自动自愈软链。
→ 修复优先级：
  - 第 10 项 fail（缓存损坏）→ `make update`（治根）
  - 第 9 项自愈（软链丢）→ 自动重建，无需手动（兑底）

## 还没解决？

1. 跑 `make check` 看 12 项体检报告
3. 看 [reference.md](./reference.md) 里的「超时字段作用域对照」表，确认不是超时配置错位
