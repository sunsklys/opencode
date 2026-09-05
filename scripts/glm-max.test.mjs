// glm-max plugin 匹配逻辑回归测试（node:test，零依赖）
// 驱动真实文件：直接 import .opencode/plugin/glm-max.ts 导出的 isGlm5Max
// Node ≥22.6 type stripping；v23.6+ 默认启用，无需 flag
import { test } from "node:test"
import assert from "node:assert/strict"

import { isGlm5Max } from "../.opencode/plugin/glm-max.ts"

// Given: 各形态 modelID；When: isGlm5Max(id)；Then: 是否强制 reasoningEffort=max
// flash 系（title 生成/librarian/explore/multimodal 的 glm-5.3-flash）必须排除
const CASES = [
  // GLM 5.2/5.3 本体与 provider 前缀/variant 后缀 → true
  ["glm-5.3", true],
  ["glm-5.2", true],
  ["zhipuai-coding-plan/glm-5.3", true],
  ["zhipuai-coding-plan/glm-5.2", true],
  ["glm-5.3:max", true],
  // 同前缀非 flash 变体（日期后缀）仍属 GLM 5.3 → true
  ["glm-5.3-0520", true],
  // flash 系必须排除 → false
  ["glm-5.3-flash", false],
  ["zhipuai-coding-plan/glm-5.3-flash", false],
  ["glm-5.3-flash:low", false],
  // 其他模型 → false
  ["glm-4.6v", false],
  ["glm-4.5-air", false],
  ["claude-sonnet-4", false],
]

for (const [modelID, expected] of CASES) {
  test(`isGlm5Max("${modelID}") → ${expected}`, () => {
    assert.equal(isGlm5Max(modelID), expected)
  })
}
