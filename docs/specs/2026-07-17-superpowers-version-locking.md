# superpowers plugin 版本锁定

- **日期**: 2026-07-17
- **状态**: 设计已批准，待实施
- **作者**: 配置审计（superpowers brainstorming 流程产物）

## 背景

`opencode.json` 第 3 行的 plugin 列表里，`superpowers` 是唯一的 git 源 plugin：

```json
"plugin": ["oh-my-openagent@latest", "opencode-mem@latest", "superpowers@git+https://github.com/obra/superpowers.git"]
```

其他两个 plugin（`oh-my-openagent`、`opencode-mem`）用 `@latest` 标签，但项目 `package.json` 精确锁定 `oh-my-openagent` 到 4.18.2（README 强调的仓库纪律）。**superpowers 既不在 package.json 里，也没有版本锁定**——每次清缓存重装都拉 main 分支 HEAD，存在两个问题：

1. **不可复现**：新机器 `make bootstrap` 拿到的代码可能和当前开发机不同。
2. **破坏性更新无感知**：obra 推送破坏性变更（如 v6 → v7 改 skill 协议）后，下次清缓存就突然坏掉。

obra 维护规范的 git tag（v3.1.0 → v6.1.1），可锁定。

## 目标

- **可复现**：新机器、CI、灾备恢复都能拿到相同版本的 superpowers。
- **可检测**：`make check` 体检时能发现"远端有新 tag"。
- **可升级**：提供一键命令升级到指定版本。
- **不破坏现有鲁棒性**：`make check` 在无网环境下仍能跑（软失败）。

## 非目标（YAGNI）

- ❌ 不做 superpowers 之外的 git 源 plugin 通用版本管理（目前只有这一个）。
- ❌ 不做自动升级（破坏 plugin 稳定性，需人工决策）。
- ❌ 不做 npm/gem 等其他源的版本检测（已有 `@latest` 漂移检测机制，docs/reference.md L148）。

## 设计

### 改动清单

| 文件 | 类型 | 说明 |
|---|---|---|
| `opencode.json` L3 | 修改 | 字符串末尾加 `#v6.1.1` |
| `docs/reference.md` | 新增小节 | `## plugin git 源版本锁定（superpowers）` |
| `README.md` | 修改 | plugin 表格 superpowers 行加锁定说明 |
| `Makefile` | 新增 2 target | `check-superpowers-version`（检测）、`upgrade-superpowers`（升级） |
| `scripts/check-superpowers.sh` | 新建 | 检测逻辑（软失败） |
| `scripts/upgrade-superpowers.sh` | 新建 | 升级逻辑 |

### check 流程

```
make check
  └─ check-superpowers.sh
       ├─ grep opencode.json 提取 #vX.Y.Z（无则警告「未锁定」并 exit 0）
       ├─ git ls-remote --tags https://github.com/obra/superpowers.git
       │    失败（无网） → 「⚠ superpowers 远端检测跳过（无网络）」exit 0
       ├─ 取最新 tag（按 semver 排序，过滤 ^{} 等 deref 条目）
       └─ 比对：
            远端 > 本地 → 「⚠ superpowers 有新版: v6.1.1 → v6.2.0，运行 make upgrade-superpowers」exit 0
            远端 == 本地 → 「✓ superpowers 最新 (v6.1.1)」exit 0
            远端 < 本地 → 「⚠ 本地版本 v6.1.1 比远端 v6.0.0 还新（异常）」exit 0
```

**核心约束**：任何失败路径都 exit 0，只警告，不阻断 `make check`。

### upgrade 流程

```
make upgrade-superpowers
  └─ upgrade-superpowers.sh
       ├─ git ls-remote --tags 查远端最新 tag（如 v6.2.0）
       ├─ 读 opencode.json 当前锁定版本
       ├─ 相同 → echo "已是最新，无需升级" exit 0
       ├─ sed -i '' 替换 opencode.json 中的 #vX.Y.Z → #v<最新>
       ├─ rm -rf ~/.cache/opencode/packages/superpowers@git+https:*
       ├─ npm install（重建缓存，opencode 启动时拉新版本）
       └─ echo "✓ superpowers vX.Y.Z → v<最新>，请重启 opencode"
```

### make check 集成位置

当前 `make check` 是 **33/33**。新增 `check-superpowers-version` 作为第 **34** 项（放最后）。

**为什么放最后**：依赖网络，放最后不污染前 33 项本地纯净性。无网时第 34 项显示「跳过」但前 33 项仍能跑过。

### 错误处理矩阵

| 情况 | 行为 | exit code |
|---|---|---|
| opencode.json 无 `#v...` | 警告「未锁定版本」 | 0 |
| `git ls-remote` 网络失败 | 警告「跳过」 | 0 |
| 远端 tag 列表为空 | 警告「tag 解析失败」 | 0 |
| 远端 > 本地 | 警告「有新版」+ 升级提示 | 0 |
| 远端 == 本地 | 「✓ 最新」 | 0 |
| 远端 < 本地（异常） | 警告「本地比远端新」 | 0 |

## 测试策略

| 用例 | 步骤 | 期望 |
|---|---|---|
| 当前状态（v6.1.1 = 远端 v6.1.1） | `make check` | 34/34 全绿，第 34 项显示「✓ 最新」 |
| 模拟落后 | 临时改 opencode.json 为 `#v6.0.0`，跑 check | 第 34 项显示「⚠ 有新版 v6.1.1」 |
| 模拟未锁定 | 临时去掉 `#v6.1.1`，跑 check | 第 34 项显示「⚠ 未锁定版本」 |
| 模拟断网 | 关 wifi 跑 check | 第 34 项显示「⚠ 跳过」，前 33 项全绿 |
| upgrade 干跑 | `make upgrade-superpowers`（已是最新时） | echo「已是最新」不改文件 |
| upgrade 实跑 | 模拟 v6.0.5 → 升级 | opencode.json 改为 `#v6.1.1`，缓存被清，提示重启 |

## 实施顺序

1. 改 `opencode.json` L3 加 `#v6.1.1`
2. 写 `scripts/check-superpowers.sh`
3. 写 `scripts/upgrade-superpowers.sh`
4. 改 `Makefile` 加 2 个 target
5. 跑 `make check` 验证 34/34
6. 模拟 4 种异常场景（落后 / 未锁定 / 断网 / 干跑）
7. 更新 `docs/reference.md` + `README.md`
8. `make check` 再次验证全绿
9. commit + push

## 风险

| 风险 | 缓解 |
|---|---|
| obra 删 tag（罕见） | 检测脚本 exit 0 不阻断；upgrade 时 git ls-remote 失败也有保护 |
| sed 在 macOS / Linux 行为不同 | 用 `sed -i ''`（macOS 兼容）；脚本头加 `set -e` |
| 缓存清理误删其他 plugin | `rm -rf` 路径明确带 `superpowers@git+https:*` glob，不影响其他 |
| 升级后 skill 协议变破坏 | upgrade 命令提示重启 opencode；可通过 git revert 回滚 |

## 后续可能扩展（非本次范围）

- 通用 git 源 plugin 版本管理（如果未来加第二个 git 源 plugin）
- 集成到 `make upgrade`（目前只升 oh-my-openagent 主版本）
