// 一键清理 opencode-mem 项目记忆的 untagged 条目（消除 web UI /project-memories 的"需要迁移"提示）
//
// 背景：auto-capture 入库时 LLM 偶发不返回结构化 tags（client.js 无兜底）→ tags=NULL 积累
//      → /api/migration/tags/detect 零容忍弹窗。上游 run-batch 自身有缺陷且体验差，此脚本替代。
//
// tags 生成策略（无 LLM 依赖，确定性规则）：
//   1. content 内嵌 "Tags: a, b, c" 行 → 直接提取（LLM 写错位置的高置信 tags）
//   2. 否则按 type 字段映射基础 tags（粗粒度兜底，保证 detect 归零）
//
// 写入语义与官方管道一致（api-handlers.js:1251 + vector-search.js:270）：
//   tags 文本 + tags_vector = vector32(embed("Topics: …"))，模型 nomic-embed-text-v1（本地）
//
// 用法：node ~/.config/opencode/scripts/fix-mem-untagged.mjs
// 依赖：借用 opencode-mem 插件缓存内的 @libsql/client 与 @huggingface/transformers
//       （路径从 opencode.json 的 plugin spec 动态解析，pin/latest 自动跟随）
import { createRequire } from "node:module";
import { join } from "node:path";
import os from "node:os";
import { readdirSync, existsSync, readFileSync } from "node:fs";

const ocConfig = JSON.parse(readFileSync(join(os.homedir(), ".config/opencode/opencode.json"), "utf-8"));
const memSpec = ocConfig.plugin?.find((p) => String(p).startsWith("opencode-mem@")) || "opencode-mem@2.25.0";
const MEM_MODULES = join(os.homedir(), `.cache/opencode/packages/${memSpec}/node_modules`);

const require2 = createRequire(join(MEM_MODULES, "noop.js"));
const { createClient } = require2("@libsql/client");

const DATA = join(os.homedir(), ".opencode-mem/data");
const MODEL = "Xenova/nomic-embed-text-v1"; // 与 opencode-mem 配置一致

const TYPE_TAGS = {
  "bug-fix": "bug-fix,troubleshooting",
  "analysis": "analysis",
  "verification": "code-verification",
  "refactor": "refactor",
  "configuration": "configuration",
  "feature": "feature",
  "discussion": "discussion",
  "other": "memory",
};

function extractInlineTags(content) {
  // 匹配 content 末尾的 "Tags: a, b, c" 行（LLM 偶尔把 tags 写进正文；与 patch-mem-tags.mjs 强版正则同源）
  const m = String(content).match(/\n\s*Tags?:\s*([^\n]{2,200})\s*$/);
  if (!m) return null;
  const tags = m[1].split(",").map((t) => t.trim().toLowerCase().replace(/[^a-z0-9_\u4e00-\u9fff.-]/g, "")).filter(Boolean);
  return tags.length >= 1 ? tags.slice(0, 5) : null;
}

const shardDirs = ["projects", "users"];
const targets = [];
for (const dir of shardDirs) {
  const d = join(DATA, dir);
  if (!existsSync(d)) continue;
  for (const f of readdirSync(d)) {
    if (!/_shard_\d+\.db$/.test(f)) continue;
    const db = createClient({ url: "file:" + join(d, f), timeout: 5000 });
    const rs = await db.execute(
      "SELECT id, type, content FROM memories WHERE tags IS NULL OR tags = ''",
    );
    for (const r of rs.rows) {
      const inline = extractInlineTags(r.content);
      const type = String(r.type || "").toLowerCase();
      const tags = inline ?? (TYPE_TAGS[type] ?? "memory").split(",");
      targets.push({ file: join(d, f), id: r.id, tags, src: inline ? "inline" : "type:" + (type || "?") });
    }
  }
}

if (targets.length === 0) {
  console.log("无 untagged 记忆，无需处理。");
  process.exit(0);
}

console.log(`待处理 ${targets.length} 条，加载 embedding 模型…`);
const mod = require2("@huggingface/transformers");
mod.env.allowLocalModels = true;
mod.env.cacheDir = join(DATA, ".cache");
mod.env.backends.onnx.wasm.numThreads = 1;
const pipe = await mod.pipeline("feature-extraction", MODEL);

let ok = 0;
for (const t of targets) {
  const input = `Topics: ${t.tags.join(", ")}`;
  const out = await pipe(input, { pooling: "mean", normalize: true });
  const vecJson = JSON.stringify(Array.from(new Float32Array(out.data)));
  const db = createClient({ url: "file:" + t.file, timeout: 5000 });
  const rs = await db.execute({
    sql: "UPDATE memories SET tags = ?, tags_vector = vector32(?) WHERE id = ? AND (tags IS NULL OR tags = '')",
    args: [t.tags.join(","), vecJson, t.id],
  });
  if (rs.rowsAffected === 1) {
    ok++;
    console.log(`ok  ${t.id}  [${t.src}]  ${t.tags.join(",")}`);
  } else {
    console.log(`SKIP ${t.id}（并发修改，已非空）`);
  }
}

// 终检：全部分片 untagged 应归零
let remain = 0;
for (const dir of shardDirs) {
  const d = join(DATA, dir);
  if (!existsSync(d)) continue;
  for (const f of readdirSync(d)) {
    if (!/_shard_\d+\.db$/.test(f)) continue;
    const db = createClient({ url: "file:" + join(d, f), timeout: 5000 });
    const rs = await db.execute("SELECT COUNT(*) c FROM memories WHERE tags IS NULL OR tags = ''");
    remain += Number(rs.rows[0].c);
  }
}
console.log(`完成 ${ok}/${targets.length}，剩余 untagged=${remain}${remain === 0 ? " ✅ 迁移提示将不再弹出" : " ❌ 仍有残留"}`);
process.exit(remain === 0 ? 0 : 1);
