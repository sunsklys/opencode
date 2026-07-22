/**
 * reasoningEffort / variant 恢复 plugin
 *
 * 背景：OMO 的 model-capability 兼容性检查在 chat.params hook 里会：
 * 1. 把 GLM 5.2 的 variant:"max" 降级为 "high"（heuristic glm 不含 max）
 * 2. 对不匹配 heuristic family 的 volcengine-plan 模型（doubao/minimax 等）
 *    删除 reasoningEffort（reason: unknown-model-family）
 *
 * 本 plugin 在 OMO 之后执行（.opencode/plugin/*.ts 自动发现，排在 plugin_origins
 * 末尾），恢复被错误降级/删除的值。
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

      // 1. GLM 5.2: 强制 variant=max + reasoningEffort=max
      //    OMO heuristic glm family 不含 max variant/reasoningEfforts
      const isGlm52 = ["glm-5.2", "glm-5-2", "glm-5p2"].some((name) => id.includes(name))
      if (isGlm52) {
        output.options.reasoningEffort = "max"
        const message = input.message as unknown
        if (isRecord(message)) message.variant = "max"
        return
      }

      // 2. volcengine-plan fallback: 恢复被 OMO 删除的 reasoningEffort
      //    OMO 对 unknown-family 模型（doubao/minimax/kimi）删除 reasoningEffort
      //    这些模型实际支持 reasoning，恢复为安全默认值
      if (providerID.includes("volcengine") && !("reasoningEffort" in output.options)) {
        output.options.reasoningEffort = "high"
      }
    },
  }),
}

export default plugin
