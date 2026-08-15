/**
 * reasoningEffort 恢复 plugin
 *
 * 背景：OMO 的 model-capability 兼容性检查在 chat.params hook 里，
 * 会把 GLM 5.2/5.3 的 variant:"max" 降级为 "high" 并删除 reasoningEffort
 * （heuristic glm family 不含 reasoningEfforts）。
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

      // GLM 5.2/5.3: 强制 reasoningEffort=max
      //    OMO heuristic glm family 不含 reasoningEfforts，会丢弃 reasoningEffort
      //    GLM 的 max reasoning 通过此 option 直接传递（variant 机制见顶部注释）
      const isGlm5Max = ["glm-5.2", "glm-5-2", "glm-5p2", "glm-5.3", "glm-5-3", "glm-5p3"].some((name) => id.includes(name))
      if (isGlm5Max) {
        output.options.reasoningEffort = "max"
      }
    },
  }),
}

export default plugin
