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
