/**
 * reasoningEffort 恢复 plugin
 *
 * 背景：OMO 的 model-capability 兼容性检查在 chat.params hook 里会：
 * 1. 把 GLM 5.2 的 variant:"max" 降级为 "high"（heuristic glm 不含 max）
 * 2. 对不匹配 heuristic family 的 volcengine-plan 模型（doubao/minimax 等）
 *    删除 reasoningEffort（reason: unknown-model-family）
 *
 * 本 plugin 在 OMO 之后执行（.opencode/plugin/*.ts 自动发现，排在 plugin_origins
 * 末尾），恢复被删除的 reasoningEffort。
 *
 * 为何只恢复 reasoningEffort，不恢复 variant：
 *   variant 在 chat.params 之前（session/llm/request.ts:80-83）就已被解析成
 *   options 对象，chat.params hook 改任何 variant 字段都来不及影响合并结果。
 *   且 GLM 的 model.variants 映射表无 "max" 键，variant:"max" 本就是空 options。
 *   GLM 的 max reasoning 通过 reasoningEffort option 直接传递，绕过 variant 机制。
 */
import type { Plugin } from "@opencode-ai/plugin"

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function readString(record: Record<string, unknown>, key: string): string | undefined {
  const value = record[key]
  return typeof value === "string" ? value : undefined
}

const plugin: { id: string; server: Plugin } = {
  id: "glm-max",
  server: async () => ({
    "chat.params": async (input, output) => {
      const model = input.model as unknown
      if (!isRecord(model)) return
      const modelID = readString(model, "modelID") ?? readString(model, "id")
      if (!modelID) return
      const id = modelID.toLowerCase()
      const providerID = (readString(model, "providerID") ?? "").toLowerCase()

      // 1. GLM 5.2: 强制 reasoningEffort=max
      //    OMO heuristic glm family 不含 reasoningEfforts，会丢弃 reasoningEffort
      //    GLM 的 max reasoning 通过此 option 直接传递（variant 机制见顶部注释）
      const isGlm52 = ["glm-5.2", "glm-5-2", "glm-5p2"].some((name) => id.includes(name))
      if (isGlm52) {
        output.options.reasoningEffort = "max"
        return
      }

      // 2. volcengine-plan fallback: 恢复被 OMO 删除的 reasoningEffort（仅对真正支持的模型）
      //    OMO 对 unknown-family 模型删除 reasoningEffort；以下模型实际支持 reasoning，
      //    恢复为安全默认值 high：
      //      - doubao-seed-2.0-pro / doubao-seed-2.0-code（火山引擎 doubao seed 系列；
      //        ⚠ 注意：OMO snapshot 标 reasoning:false 与此决策冲突，建议运行时抓包验证）
      //    以下模型跳过强制 high（heuristic family 不暴露 reasoningEfforts 字段，补了无效）：
      //      - doubao-seed-2.0-lite（轻量模型，OMO snapshot 明确标 reasoning:false）
      //      - kimi-k2.6（kimi family L24380-85 无 reasoningEfforts 字段；火山引擎走 thinking 通道）
      //      - minimax-m3（minimax family L24391-96 无 reasoningEfforts 字段；火山引擎走 thinking 通道）
      const SKIP_HIGH_REASONING = ["doubao-seed-2.0-lite", "kimi-k2.6", "minimax-m3"]
      const modelSuffix = id.split("/").pop() ?? ""
      const shouldSkip = SKIP_HIGH_REASONING.some(m => modelSuffix.includes(m))
      if (providerID.includes("volcengine") && !shouldSkip && !("reasoningEffort" in output.options)) {
        output.options.reasoningEffort = "high"
      }
    },
  }),
}

export default plugin
