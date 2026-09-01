# F3 上游 Issue 草稿（anomalyco/opencode）

> 状态：DRAFT——等待 `gh auth login` 后查重 + 用户确认提交。
> 对应本地缓解：commit 8d0a1f3（compaction prune/tail_turns 显式继承）。

## Title

Thinking tokens returned in full to conversation context (~2x context growth on reasoning-heavy models)

## Body

**Environment:** opencode 1.18.25, provider `zhipuai-coding-plan`, model `glm-5.3` (reasoning effort `max`), macOS.

**Mechanism:** `transform.ts:321-353` returns the full thinking text back into the conversation context after each turn.

**Measured impact** (29,915-message local DB, `message.data->tokens`):

```sql
-- per-agent thinking:output ratio
select json_extract(data,'$.agent') a,
       count(*) c,
       sum(json_extract(data,'$.tokens.reasoning')) thinking,
       sum(json_extract(data,'$.tokens.output')) output
from message group by a order by thinking desc;
```

- Main agent chain: 5,188,931 thinking vs 4,951,216 output tokens (**1.05:1**)
- Reviewer agent (oracle): 941,098 vs 440,982 (**2.13:1**) → reasoning-heavy roles carry ~2x effective context

**Ask:** strip or summarize thinking before re-sending history (or make retention configurable per model). Full-text re-send compounds context growth quadratically over long sessions and interacts badly with aggressive truncation workarounds.

## 提交前检查单

1. `gh auth login`
2. 查重：`gh search issues --repo anomalyco/opencode "thinking tokens" --state open`
3. 用户确认后：`gh issue create --repo anomalyco/opencode --title "<Title>" --body-file docs/f3-upstream-issue-draft.md`
