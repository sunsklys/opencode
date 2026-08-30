#!/usr/bin/env node
// 读取 ~/.omo/omo.jsonc（omo 4.19.4+ 统一配置），输出 [opencode] 作用域关键字段 JSON。
// 供 check.sh 体检使用；JSONC 注释安全（字符串内的 // 如 "https://" 不会被误伤）。
// 环境变量 OMO_CONFIG 可覆盖配置路径（测试用）。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const p = process.env.OMO_CONFIG || path.join(os.homedir(), '.omo', 'omo.jsonc');
let raw;
try {
  raw = fs.readFileSync(p, 'utf8');
} catch {
  console.log('{}');
  process.exit(0);
}

// 剥 JSONC 注释：识别字符串状态，仅剥字符串外的 // 与 /* */ 注释
let out = '';
let i = 0;
let inStr = false;
while (i < raw.length) {
  const ch = raw[i];
  const nx = raw[i + 1];
  if (inStr) {
    out += ch;
    if (ch === '\\' && nx !== undefined) {
      out += nx;
      i += 2;
      continue;
    }
    if (ch === '"') inStr = false;
    i += 1;
    continue;
  }
  if (ch === '"') {
    inStr = true;
    out += ch;
    i += 1;
    continue;
  }
  if (ch === '/' && nx === '/') {
    while (i < raw.length && raw[i] !== '\n') i += 1;
    continue;
  }
  if (ch === '/' && nx === '*') {
    i += 2;
    while (i < raw.length && !(raw[i] === '*' && raw[i + 1] === '/')) i += 1;
    i += 2;
    continue;
  }
  out += ch;
  i += 1;
}

let cfg;
try {
  cfg = JSON.parse(out);
} catch (e) {
  console.error(`omo.jsonc 解析失败: ${e.message}`);
  process.exit(1);
}

const s = cfg['[opencode]'] || {};
console.log(JSON.stringify({
  monitor: s.monitor?.enabled,
  goal_max: s.goal?.default_max_iterations,
  goal_enabled: s.goal?.enabled,
  babysitting: s.babysitting?.timeout_ms,
  notification: s.notification?.force_enable,
  comment_checker: !!s.comment_checker?.custom_prompt,
  disabled_skills: (s.disabled_skills || []).length,
  disabled_commands: (s.disabled_commands || []).length,
}));
