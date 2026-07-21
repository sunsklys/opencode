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

→ plugin 加载链问题。OMO plugin 启动时通过 `discoverSharedSkills()` 扫描自己的 `dist/skills/`（20 个 skill），缓存损坏 / `@latest` 漂移会让 shared scope 整批消失。
→ 一键诊断：`make check` 第 10 项检测三处 dist/skills 完整性（项目锁定 + builtin 缓存 + plugin 缓存，20×3），第 9 项自动自愈软链。
→ 修复优先级：
  - 第 10 项 fail（缓存损坏）→ `make update`（治根）
  - 第 9 项自愈（软链丢）→ 自动重建，无需手动（兑底）

## dbx MCP 连接失败 / spawn errno -88

症状：`opencode mcp list` 显示 `dbx failed: MCP error -32000: Connection closed`，或 node spawn 报 `Unknown system error -88`。

**根因 A（最常见）：npm 包二进制截断**
- `@dbx-app/mcp-server` 依赖平台专属 Rust 二进制（`@dbx-app/mcp-darwin-arm64` 等），npm 缓存损坏或解压中断会导致二进制缺末尾几百 KB。
- 诊断：`otool -l <binary> | grep filesize` 看段表末尾是否超出实际文件大小；`codesign -dv <binary>` 报 `unsupported format for signature`；`strings <binary>` 报 `truncated or malformed object`。
- 修复：
  ```bash
  npm cache clean --force
  npm uninstall -g @dbx-app/mcp-server
  npm install -g @dbx-app/mcp-server
  ```
  验证：`stat -f %z <binary>` 与 npm registry `unpackedSize` 一致。

**根因 B：Node spawn 未签名二进制被 macOS AMFI 拦截**
- 仅在二进制本身未损坏但未签名且带 `com.apple.provenance` xattr 时出现（SIP 保护，`xattr -d` 删不掉）。
- 现代化修复：用 shell wrapper 跳过 node spawn 路径（`/bin/sh exec` 不受影响）。
- 在 `opencode.json` 用 wrapper 路径：
  ```json
  "dbx": { "type": "local", "command": ["<path-to-wrapper>"] }
  ```
  wrapper 内容：`#!/bin/sh\nexec \"<binary>\" \"\$@\"`

**验证修复**：
  ```bash
  echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | node /path/to/dbx-mcp-server.js
  # 期望收到包含 "serverInfo":{"name":"dbx",...} 的 JSON 响应
  ```
  最后重启 opencode，`opencode mcp list` 看到 `✓ dbx connected`。
## 还没解决？

1. 跑 `make check` 看 12 项体检报告
3. 看 [reference.md](./reference.md) 里的「超时字段作用域对照」表，确认不是超时配置错位
