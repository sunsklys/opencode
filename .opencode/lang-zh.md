# 输出语言要求（强制，不可协商）

## 必须使用简体中文的场景

1. **思考过程（thinking / reasoning 字段）**：从第一个字符起就用中文起草。禁止先英文思考再翻译。技术术语（grep、API、JWT 等）可内嵌英文单词，但句子骨架必须是中文。
2. **回复正文**：所有解释、说明、总结、汇报、错误分析、方案对比、提问澄清——全部中文。
3. **工具调用里的自然语言字段**：`todowrite` 的 subject、`task_create` 的 subject/description、`task` 的 prompt、`question` 的 question/header、commit message、PR 描述——必须中文。
4. **代码注释、文档、日志字符串**：中文为主，技术专有名词保留英文原词。

## 允许保留英文原词的场景（不视为违规）

- 代码标识符：变量名、函数名、类名、文件路径、URL
- 标准 API/协议术语：HTTP、JSON、JWT、OAuth、SQL 关键字、HTTP 状态码等
- 命令行参数、shell 命令、配置键名（如 `prompt_append`、`reasoningEffort`）
- 第三方库名、产品名（React、opencode、GLM、OMO 等）
- 直接引用的英文原文

## 反例对比

❌ 错误（中英混杂）：
```
Let me check the configuration first. 让我检查一下配置。
```
✅ 正确：
```
先检查配置。
```

❌ 错误（thinking 全英文起草）：
```
The user wants X. I should grep for Y first, then call oracle.
```
✅ 正确（thinking 中文起草，术语保留）：
```
用户想要 X。我先 grep Y，再调 oracle。
```

❌ 错误（工具参数用英文）：
```
todowrite subject="Fix auth bug"
```
✅ 正确：
```
todowrite subject="修复认证 bug"
```

❌ 错误（commit message 英文）：
```
fix: resolve variant downgrade bug
```
✅ 正确：
```
fix: 修复 variant 降级 bug
```

## 输出前自检

每次产生一段输出（含思考）前自问：这段话里有没有不必要的英文整句？
- 有 → 立即改写为中文，只保留必要的英文专有名词
- 没有 → 通过
