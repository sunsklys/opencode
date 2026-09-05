# OMO 5.0 迁移 Runbook

> 适用：oh-my-openagent 4.19.4 → 5.0 升级窗口。执行前提：OMO 5.0 正式发布。
> 背景评审：2026-09-01 对抗评审（3 轮 16 靶），fallback_models 废弃键经 4.19.4 运行时归一（dist:99021-99032）零功能损失，故迁移延迟至本窗口。
> 勘误（2026-09-01 终验）：评审项 F3「thinking 全文回传致上下文膨胀」经双证据复核不成立（glm 系 capabilities.interleaved=null 不走回传分支 + db 25,866 条 assistant 消息 reasoning parts 零存储），issue 草稿已撤（revert 5ef41e2）。L-F2（chat 单轮 fallback 丢档）复核属实，维持知悉不改。

## 0. 例外条款（先读）

读 5.0 release notes：若 **fallback_models 支持被明确移除**，不要等待——立即执行本 runbook（留在 4.19.4 是唯一替代）。否则按正常窗口执行。

## 1. 前置条件

- OMO 5.0 已发布；`make upgrade`；`omo --version` ≥ 5.0
- `/Users/edy/.config/opencode` 工作区干净（`git status --porcelain` 为空）

## 2. 备份（审批门）

```bash
git -C /Users/edy/.config/opencode tag pre-omo-5.0
cp ~/.omo/omo.jsonc ~/.omo/omo.jsonc.pre5-$(date +%Y%m%d)
diff /Users/edy/.config/opencode/omo.jsonc.template ~/.omo/omo.jsonc  # 必须无输出
```

## 3. 迁移执行

1. 先 dry-run（5.0 迁移引擎支持 `--dry-run`/lock+journal/`~/.omo/migration-backup-<ts>`/no-clobber；**先对照 5.0 release notes 确认确切 CLI flag**）
2. 检查 journal + 备份目录，确认无异常后正式执行

## 4. 迁移后补丁清单（逐项审批门）

### 4a. 链序保真核对

12 agent 的迁移后 `models[0]` 必须等于迁移前主模型：

| agent | models[0] 期望 | fallback 期望 |
|---|---|---|
| sisyphus/prometheus/plan/oracle/metis/momus/atlas/sisyphus-junior/hephaestus | glm-5.3 | glm-5.2 |
| librarian/explore | glm-5.3-flash | glm-5.2 |
| multimodal-looker | glm-5.3-flash | 5v-turbo → 4.6v |

### 4b. librarian/explore 补 5.2 档位

`glm-5.2` entry → `{ "model": "zhipuai-coding-plan/glm-5.2", "reasoning": "high" }`

- 原因：5.2 枚举 `[high, max]` 无 low；当前 low 继承走退化分支静默升档
- **预期修正**（终裁增量 4）：chat 运行时 fallback 丢档是**单轮粒度**（`applyFallbackToChatMessage` 删 message.variant，dist:94420-94433；下一轮 applyAgentVariant 自动恢复）。models[] 对象化**不解决** chat 单轮损失（上游缺口）——本补丁只为 fallback 链档位语义诚实，勿期待修复单轮凹陷

### 4c. multimodal-looker 视觉 entry 保持裸串

`5v-turbo`/`4.6v` 为 toggle 型模型（variants 空数组），无档位语义，**不要**包对象

### 4d. writing models[0] 显式对象化（可选加固）

`"zhipuai-coding-plan/glm-5.3"` → `{ "model": "zhipuai-coding-plan/glm-5.3", "reasoning": "low" }`

- 顶层 `variant: "low"` 已于 2026-09-01 落地（commit f63de31）且是委派路径的有效旋钮——本步仅为 schema 显式性
- 备选：`max`（若写作输出平淡则对齐 artistry）

### 4e. variant 字段存活性核对（关键）

确认 7 处 category 顶层 variant（6 处 f63de31 + visual-engineering 07a4686）迁移后未丢失：

```bash
rg --no-config -n '"variant":' ~/.omo/omo.jsonc
# 期望恰好 7 行：visual-engineering high / ultrabrain max / artistry max /
# deep max / unspecified-low low / unspecified-high max / writing low
```

丢失则按上述矩阵补回。

### 4f. 回归验证

```bash
make -C /Users/edy/.config/opencode check   # critical 全绿
omo doctor                                  # 无新增错误
```

冒烟：librarian/explore/multimodal-looker/writing 各发一个委派任务 + 一次 team 实例化查 runtimeState variant 是否等于用户配置值。

## 5. 回退

```bash
# 恢复迁移备份（或 .pre5- 副本）
cp ~/.omo/migration-backup-<ts>/omo.jsonc ~/.omo/omo.jsonc  # 路径以实际备份为准
git -C /Users/edy/.config/opencode revert <sha>
cp /Users/edy/.config/opencode/omo.jsonc.template ~/.omo/omo.jsonc
# 重启 opencode
```

## 6. F4 灾备预案（附）

智谱故障时：改 `opencode.json` 移除目标 provider 出 disabled 列表 + 准备该 provider 凭证（一行 + 凭证预备，平时不预配）。

## 7. 观察项（迁移后一周）

- ultrabrain/deep/artistry 委派路径 token 量**上升属预期**（variant 修复=档位恢复而非回归）
- ~~exp: 实验到期评审~~ 已全部撤销：评审温度 0.3（revert 0f7308f，证据弱）、三执行器 high 回 max（b3794bd，用户拍板）——重型 agent 档位终态统一 max
- 并发对齐后（7d1a2fb：provider/flash 3→10，实测上限≈12）留意 5 小时积分消耗速率（Max 档 28,000/5h），thinking max 生成密度高（oracle 实测 2.14:1）属预期，非故障
- compaction prune 生效验证：任一 agent 触发压缩后，会话历史应裁剪为摘要+最近 ~6 轮（soft gate）

## 8. 预升级语义门（2026-09-05 T8 扩展，升级窗口必读）

> 依据：OMO dev HEAD `fd1d0dbbc` 与 opencode anomalyco dev HEAD `e2894562f` 源码只读对照 + T1-T3（已合 main：751f2c5 / 5c234e4 / f154cec）结论。断言时效同 reference.md：发布日以当时 release notes 与正式版源码重验。

### 8a. 权限 v2 强制预升级门（不过此门不升级）

opencode CLI 的 v2 core 线（anomalyco dev，`packages/core`）重写了 permission 求值。若 5.0 窗口附带 opencode CLI 切 v2 引擎（config schema V2 过渡完成），三个语义漂移点：

| 漂移点 | v1（当前 1.18.x） | v2（dev core） | 证据 |
|---|---|---|---|
| 复合命令拆段 | tree-sitter 拆 command 节点逐段匹配 | 整条命令串作单一 resource 求值 | `core/src/tool/bash.ts` L142-149（`resources:[input.command]`）；L66 TODO 自认 "Port tree-sitter bash / PowerShell parser-based approval reduction" 未做 |
| 规则形态 | `permission.bash.{pattern: value}` 映射 | `Rule{action, resource, effect}` 扁平数组 | `core/src/permission.ts` L76-86 evaluate：findLast 双匹配 action+resource，无匹配默认 ask |
| 同串 allow/deny 决胜 | 段级评估，任一 deny 段整体 deny（allow 段不豁免） | 整串 findLast，同串多规则并存时后声明胜 | permission.ts L80（findLast）+ L158-161（effects 聚合） |

漂移实例（本仓库规则直接受影响）：`cd x && sh -c "y"` 在 v1 拆段后 `sh -c` 段命中 deny（ad9536e 的解释器规则）；v2 整串与 `sh -c*` 前缀失配（串首是 `cd`）→ 漂移到默认 ask。同理 `git push --force origin` 在 v2 整串同时匹配 `git push *`（allow）与 `git push --force*`（deny），靠声明序决胜——窄规则必须后声明的键序规范在 v2 方向不变且更关键。

**升级门（强制）**：`scripts/check-permissions.mjs` 的 37 案例表是 v1 语义回归基线（harness 复刻 v1 求值，升级本身不动它）。发布日若确认 v2 引擎启用，须将 37 案例以 v2 语义（整串单 resource + findLast + 默认 ask）重新评估——扩展 harness 加 v2 求值模式或逐条手测；任何案例 deny→ask/allow 漂移，先改 opencode.json 规则（整串形态覆盖，如 `* && sh -c*`、`*id_rsa*`）再升级。

### 8b. 权限残留清单 v2 复核（reference.md 六条逐条判定）

| # | 残留（v1） | v2 判定 | 证据 |
|---|---|---|---|
| 1 | bash 横向 `cd ~/.ssh && cat id_rsa` | **未修复，拦截面更粗**：整串匹配 + 命令参数外目录扫描降为 advisory only（只警告不询问） | bash.ts L138-141（warning 文案 "advisory only"） |
| 2 | symlink 逃逸 external_directory | **部分改善，待复验**：v2 `FSUtil.resolve` 走 `fs.realPath`（fs-util.ts L96），advisory 扫描解析真实路径；但扫描不阻塞，workdir 的 external_directory assert 走 LocationMutation 另一条路径，升级后实测 | fs-util.ts L94-97 |
| 3 | FILES 表覆盖面（python wr.py 不提取路径） | **形态变化，未修复**：token 扫描仅识别绝对路径参数且 advisory（bash.ts L66 TODO 自认 parser-based 未做）——v1 至少对 FILES 表命令询问，v2 连询问都没有 | bash.ts L79-95 |
| 4 | 会话 always 覆盖配置 deny | **已修复**：`denied()` 只对配置规则求值并先行短路（permission.ts L147-149、L157），savedRules 后置无法翻转配置 deny；always 级联同样跳过 denied 的 pending（L268） | permission.ts L155-162、L259-283 |
| 5 | patterns 空整体放行 | **结构消解，新触发面**：v2 规则是扁平数组无 pattern-set 结构；但 resources 空数组时 effects 为空 → 聚合为 allow（L159-160），bash 恒传单 resource 故实际触发面窄 | permission.ts L159-160 |
| 6 | ask/run 不对称 | **已修复**：ask 与 assert 共用 evaluateInput 同一聚合（L155-162、L190-218），对称 | permission.ts L190-218 |

v2 上线后按此表逐条复测，reference.md 残留表同步更新（#4/#6 预期销项）。

### 8c. glm-max.ts 摘除判据

插件根因（见 `.opencode/plugin/glm-max.ts` 头注释）：OMO heuristic 表 glm family **不含** reasoningEfforts → model-capability 兼容检查在 chat.params 里丢弃 GLM 5.2/5.3 的 reasoningEffort → 插件在 OMO 之后执行恢复。

dev 现状（model-core/model-capability-heuristics.ts L93-103）：glm family 已含 `reasoningEfforts: ["high", "max"]` + aliases（low→high、medium→high、xhigh→max）——根因已修复，插件可摘。

摘除步骤：删 `.opencode/plugin/glm-max.ts` + `scripts/glm-max.test.mjs`（check.sh/Makefile 无引用，无连带改动）→ 实跑一个 max 档 agent 验证 chat.params 到达。

两个注意：
- **发布时复验**：以正式版 node_modules 内 dist 复核 glm 条目 reasoningEfforts 仍含 max（dev β 到正式版之间可能回摆）
- **语义差异预期**：插件行为=本体无条件强制 max；5.x 原生=尊重配置档位（如 reasoning:low 会被 alias 升 high 而非保持 low）——摘除后档位语义以配置为准，属预期变化而非回归

### 8d. /start-work → /ulw-execute 改名清扫

已有记录：reference.md「上游版本观察项」+ 升级核对四件套第 2 项。本仓库残留引用清点（2026-09-05，`grep -rn start-work` 排除 node_modules）：

| 位置 | 性质 | 动作 |
|---|---|---|
| docs/usage.md:65、:204 | 操作面（教用户用 `/start-work` 执行） | 升级日改写为 `/ulw-execute` |
| Makefile:168、:171（clean-state 注释） | `.omo` 状态目录/文件名（boulder 保留项），非命令引用 | 升级后核对 ulw-execute 时代状态文件名是否随之改变 |
| docs/reference.md:226、:237 / .opencode/instructions.md:41 / scripts/upgrade.sh:52 | 描述性（升级纪律与历史记录） | 保留 |

CHANGELOG 补充细节：`start_work` config key 同步改 `ulw_execute`（旧 key 兼容一个版本并警告）；flag `omo-senpi-start-work-continuation-disabled` 随组件改名。

### 8e. 4 breaking × 本仓库命中矩阵

| breaking（CHANGELOG L37-40） | 命中 | 一行证据 |
|---|---|---|
| `/start-work` → `/ulw-execute`（hard cutover 无别名） | **1 处操作面** | grep 命中 docs/usage.md:65、:204（8d 已列动作） |
| `omo` bin → `omo-agent-toolkit`（旧 bin 同版移除） | 零 | `which omo` exit 1；scripts 内无裸 `omo` 调用（check.sh 的 "omo" 是 template 对指代非 bin） |
| 旧配置文件停读（`oh-my-openagent.json[c]` 等首启迁移进 `~/.omo/omo.jsonc`） | 零 | 本仓库一直走 `omo.jsonc.template` → `~/.omo/omo.jsonc`（§2 diff 门），旧文件不存在 |
| `shared/<name>` skill 裸名注册（含 disabled_skills 条目失配） | 零（disabled_skills 待核） | skills.lock 全为 lark-* 本地 skill；opencode.json/tui.json 无 `shared/` 引用；disabled_skills 升级核对已列 reference.md 四件套第 1 项 |

结论：4 breaking 中仅 start-work 一项实际命中且已有清扫路径（8d），其余零暴露。

### 8f. fallback retry_on_errors 的 5.x 语义注意

T3（f154cec）在配置层移除 429 后，5.x 判定逻辑与 4.x 同构（T3 dist 对照 + dev 源码双证，`model-core/runtime-fallback-error-classifier.ts`）：

- **quota 文本路径仍在**：中文文本（使用上限 / 额度不足 / 已耗尽 / 预扣费组合，L147-152）→ `quota_exceeded` → `isRuntimeFallbackRetryableError` L172-178 无条件 return true 可重试——账号级确定性错误跨模型重试的问题在 5.x 原样保留
- **429 硬编码 retry-safe 仍在**：`isStatusCodeRetrySafe` L38-40 把 429 与 5xx/408/425 并列恒 safe，与配置无关
- **新增 terminal quota 豁免**：terminal quota / terminal billing limit / hard billing limit 文本或 `terminal_quota_exhausted` detailType → abort → 不可重试（L74-97、L170）；message-update-handler 另有 terminalQuota402Abort（402+terminal → abort）

**升级后重验观察门**：D4 上游 issue 落地前，升级 5.x 后首个 429 窗口执行 `grep '"statusCode":429'` 精确匹配（避免 sessionID 误报），确认 fallback 不再全上下文重发；同时留意 quota 文本路径是否需要配置层补充规避。

### 8g. 双声明同步检查（升级操作纪律）

opencode.json 与 tui.json 的 plugin 数组版本标记（当前均为 `oh-my-openagent@4.19.4`，两文件 L3-4）**必须同升**：两文件是双进程双导出面（opencode 主进程与 tui 各自加载插件），单边改版本即插件版本漂移。

守卫已在位：check.sh tui 同步门（tui.json plugin 与 opencode.json 不同步即 fail）+ §14 五对零漂移门（含 pluginSpec/memSpecSync）。升级日走 `make upgrade`（自动同步双 json spec），勿手改单边；手动分步时以 §14 全绿为完成标准。

### 8h. GitHub references 限制注记（占位）

TODO(T6)：GitHub references 网络恶化的限制与对策——待 T6（GitHub 网络恶化任务）结论回填。
