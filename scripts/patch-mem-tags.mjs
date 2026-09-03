// 可重放 patch：给 opencode-mem 的 client.js addMemory 打「tags 三层兜底」补丁
//
// 动机（上游 2.25.0 缺陷）：auto-capture 的 LLM 偶发不返回结构化 tags（空数组/字段缺失/
// 写进 summary 正文），client.js:115 `metadata?.tags || []` 无兜底 → tags=NULL 入库 →
// /api/migration/tags/detect 零容忍 → web UI 反复弹「需要迁移」。
//
// 补丁逻辑：tags 为空时 ①提取正文末尾 "Tags: a, b, c" 行 ②按 type 映射兜底 ③保底 ["memory"]。
// 正常路径（tags 非空）零影响。
//
// 用法：
//   node ~/.config/opencode/scripts/patch-mem-tags.mjs                # 默认 patch @2.25.0
//   node ~/.config/opencode/scripts/patch-mem-tags.mjs <目录名>       # 例: opencode-mem@2.26.0
//
// 幂等：已打过补丁（存在 PATCH 标记）则跳过；锚点匹配不到则报错退出（上游代码已变，需人工审查）。
// 上游修复此问题后可停用本脚本并摘除补丁。
import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import os from "node:os";

const dirName = process.argv[2] || "opencode-mem@2.25.0";
const target = join(os.homedir(), `.cache/opencode/packages/${dirName}/node_modules/opencode-mem/dist/services/client.js`);

if (!existsSync(target)) {
  console.error(`目标不存在: ${target}`);
  process.exit(1);
}

const MARKER = "PATCH(tags-fallback)";
const ANCHOR = `            await this.initialize();
            const tags = metadata?.tags || [];`;

const REPLACEMENT = `            await this.initialize();
            // ${MARKER}: LLM 偶发不返回结构化 tags（空数组/字段缺失/写进正文）时三层兜底，
            // 保证 tags 永不为空，消除 /api/migration/tags/detect 零容忍提示。
            // 正常路径（tags 非空）零影响；上游修复后可移除。重打: patch-mem-tags.mjs
            let tags = metadata?.tags || [];
            if (!Array.isArray(tags) || tags.length === 0) {
                const inline = String(content).match(/\\n\\s*Tags?:\\s*([^\\n]{2,200})\\s*$/);
                if (inline) {
                    tags = inline[1]
                        .split(",")
                        .map((t) => t.trim().toLowerCase().replace(/[^a-z0-9_\\u4e00-\\u9fff.-]/g, ""))
                        .filter(Boolean)
                        .slice(0, 5);
                }
            }
            if (!Array.isArray(tags) || tags.length === 0) {
                const typeFallback = {
                    "bug-fix": ["bug-fix", "troubleshooting"],
                    analysis: ["analysis"],
                    verification: ["code-verification"],
                    refactor: ["refactor"],
                    configuration: ["configuration"],
                    feature: ["feature"],
                };
                tags = typeFallback[String(metadata?.type || "").toLowerCase()] || ["memory"];
            }
            // END ${MARKER}`;

let src = readFileSync(target, "utf-8");

if (src.includes(MARKER)) {
  console.log(`已打过补丁，跳过: ${target}`);
  process.exit(0);
}

const idx = src.indexOf(ANCHOR);
if (idx === -1) {
  console.error(`锚点未找到（上游代码已变化，需人工审查 addMemory）: ${target}`);
  process.exit(1);
}
if (src.indexOf(ANCHOR, idx + 1) !== -1) {
  console.error(`锚点不唯一，需人工审查: ${target}`);
  process.exit(1);
}

writeFileSync(target + ".orig", src, "utf-8"); // src 仍为原始内容（替换前）
src = src.slice(0, idx) + REPLACEMENT + src.slice(idx + ANCHOR.length);
writeFileSync(target, src, "utf-8");

// 语法校验
try {
  execFileSync(process.execPath, ["--check", target], { stdio: "pipe" });
} catch (e) {
  // 回滚，绝不留破损文件
  writeFileSync(target, readFileSync(target + ".orig", "utf-8"));
  console.error("语法校验失败，已回滚:", String(e.stderr || e));
  process.exit(1);
}
unlinkSync(target + ".orig"); // 校验通过，清理备份

console.log(`补丁已应用并通过语法校验: ${target}`);
