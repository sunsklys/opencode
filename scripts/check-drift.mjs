#!/usr/bin/env node
// check-drift.mjs - 配置漂移 + instructions 引用完整性检测
// 供 check.sh 体检消费；输出单行 JSON。
//
// 用法：
//   node scripts/check-drift.mjs            # 全部检测，输出 JSON
//   OMO_CONFIG=/path OMEM_CONFIG=/path ...  # 覆盖路径（测试用）
//
// 检测内容：
//   omo.drift   - omo.jsonc.template ↔ ~/.omo/omo.jsonc 规范化比较（排除运行时写入的 _migrations）
//   mem.drift   - opencode-mem.jsonc.template ↔ opencode-mem.jsonc 规范化比较（应完全一致）
//   instructions.missing - opencode.json instructions 数组中 {file:...} 引用但不存在的文件
//
// 规范化：剥 JSONC 注释（字符串状态机，URL 里的 // 不误伤）→ 去尾逗号 → JSON.parse
//         → 删 _migrations（仅 omo）→ 键排序 canonical stringify → 字符串比较

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const ROOT = path.dirname(new URL(import.meta.url).pathname);
const omoGenerated = process.env.OMO_CONFIG || path.join(os.homedir(), '.omo', 'omo.jsonc');
const omoTemplate = path.join(ROOT, '..', 'omo.jsonc.template');
const memGenerated = process.env.OMEM_CONFIG || path.join(ROOT, '..', 'opencode-mem.jsonc');
const memTemplate = path.join(ROOT, '..', 'opencode-mem.jsonc.template');

// --- JSONC 注释剥离（字符串状态机；与 read-omo-config.mjs 同策略）---
function stripComments(raw) {
  let out = '';
  let i = 0;
  let inStr = false;
  while (i < raw.length) {
    const ch = raw[i];
    const nx = raw[i + 1];
    if (inStr) {
      out += ch;
      if (ch === '\\' && nx !== undefined) { out += nx; i += 2; continue; }
      if (ch === '"') inStr = false;
      i += 1;
      continue;
    }
    if (ch === '"') { inStr = true; out += ch; i += 1; continue; }
    if (ch === '/' && nx === '/') { while (i < raw.length && raw[i] !== '\n') i += 1; continue; }
    if (ch === '/' && nx === '*') { i += 2; while (i < raw.length && !(raw[i] === '*' && raw[i + 1] === '/')) i += 1; i += 2; continue; }
    out += ch;
    i += 1;
  }
  return out;
}

// --- 键排序 canonical stringify（消除键序差异）---
function canonical(value) {
  if (Array.isArray(value)) return JSON.stringify(value.map(canonical));
  if (value && typeof value === 'object') {
    const keys = Object.keys(value).sort();
    return '{' + keys.map((k) => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
  }
  return JSON.stringify(value);
}

// --- 单对 template/生成物 漂移检测 ---
// 返回 { exists, drift, detail }
function checkPair(templatePath, generatedPath, label, stripKeys = []) {
  if (!fs.existsSync(generatedPath)) {
    return { exists: false, drift: null, detail: `${label} 生成物不存在（make 生成后此项生效）` };
  }
  let tObj, gObj;
  try {
    tObj = JSON.parse(stripComments(fs.readFileSync(templatePath, 'utf8')).replace(/,(\s*[}\]])/g, '$1'));
  } catch (e) {
    return { exists: true, drift: null, detail: `${label} template 解析失败: ${e.message}` };
  }
  try {
    gObj = JSON.parse(stripComments(fs.readFileSync(generatedPath, 'utf8')).replace(/,(\s*[}\]])/g, '$1'));
  } catch (e) {
    return { exists: true, drift: null, detail: `${label} 生成物解析失败: ${e.message}` };
  }
  for (const k of stripKeys) { delete tObj[k]; delete gObj[k]; }
  const drift = canonical(tObj) !== canonical(gObj);
  return { exists: true, drift, detail: drift ? `${label} 漂移（template 与生成物配置不一致）` : `${label} 一致` };
}

// --- instructions {file:...} 引用存在性 ---
function checkInstructions() {
  const cfgPath = path.join(ROOT, '..', 'opencode.json');
  const missing = [];
  let total = 0;
  try {
    const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    for (const entry of cfg.instructions || []) {
      const m = typeof entry === 'string' ? entry.match(/^\{file:(.+)\}$/) : null;
      if (!m) continue;
      total += 1;
      let p = m[1];
      if (p.startsWith('~/')) p = path.join(os.homedir(), p.slice(2));
      else if (!path.isAbsolute(p)) p = path.join(ROOT, '..', p);
      if (!fs.existsSync(p)) missing.push(m[1]);
    }
  } catch {
    return { total: 0, missing: ['opencode.json 解析失败'] };
  }
  return { total, missing };
}

// --- package.json ↔ plugin spec 版本一致性（Wave3：钉版闭合 @latest 旁路的守卫）---
// package.json 依赖的 oh-my-openagent 版本必须与 opencode.json/tui.json plugin spec 一致，
// 失配 = 「防跳闸变防升级」分裂（package.json 升级而 spec 未跟随，或反之）→ drift:true → critical fail
function checkPluginSpec() {
  const expected = 'oh-my-openagent@' + JSON.parse(fs.readFileSync(path.join(ROOT, '..', 'package.json'), 'utf8')).dependencies['oh-my-openagent'];
  const mismatches = [];
  for (const f of ['opencode.json', 'tui.json']) {
    try {
      const plugins = JSON.parse(fs.readFileSync(path.join(ROOT, '..', f), 'utf8')).plugin || [];
      if (!plugins.includes(expected)) mismatches.push(`${f} 缺少 ${expected}`);
    } catch (e) {
      mismatches.push(`${f} 解析失败: ${e.message}`);
    }
  }
  return { exists: true, drift: mismatches.length !== 0, detail: mismatches.length === 0 ? `plugin spec 一致（${expected}）` : 'plugin spec 失配: ' + mismatches.join('; ') };
}

const result = {
  omo: checkPair(omoTemplate, omoGenerated, 'omo.jsonc', ['_migrations']),
  mem: checkPair(memTemplate, memGenerated, 'opencode-mem.jsonc'),
  instructions: checkInstructions(),
  pluginSpec: checkPluginSpec(),
};
console.log(JSON.stringify(result));
