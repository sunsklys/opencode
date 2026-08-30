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

// --- 文档引用防漂移护栏（Wave4：堵「手改不走 upgrade.sh」路径，42aea26 教训）---
// 机器校验高漂移值：README 的 plugin 版本 ↔ package.json；docs 的「N 项体检」↔ check.sh 实际项数。
// 计数类教法（54 skills 等）不进护栏（容忍手工，见 artisan R1-7 分层策略）。
function checkDocRefs() {
  const problems = [];
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, '..', 'package.json'), 'utf8'));
    const expectedPlg = pkg.dependencies['@opencode-ai/plugin'];
    const readme = fs.readFileSync(path.join(ROOT, '..', 'README.md'), 'utf8');
    const m = readme.match(/@opencode-ai\/plugin (\d+\.\d+\.\d+)/);
    if (!m) problems.push('README 未找到 @opencode-ai/plugin 三段版本号');
    else if (m[1] !== expectedPlg) problems.push(`README plugin ${m[1]} ≠ package.json ${expectedPlg}`);
  } catch (e) { problems.push('package.json/README 读取失败: ' + e.message); }
  try {
    const checkSh = fs.readFileSync(path.join(ROOT, '..', 'scripts', 'check.sh'), 'utf8');
    const nums = [...checkSh.matchAll(/^\s*# -+ (\d+)\./gm)].map((x) => Number(x[1]));
    const itemCount = Math.max(...nums, 0);
    for (const f of ['docs/quickstart.md', 'docs/troubleshooting.md']) {
      const doc = fs.readFileSync(path.join(ROOT, '..', f), 'utf8');
      const m2 = doc.match(/(\d+) 项体检/);
      if (m2 && Number(m2[1]) !== itemCount) problems.push(`${f} 声明 ${m2[1]} 项 ≠ check.sh 实际 ${itemCount} 项`);
    }
  } catch (e) { problems.push('check.sh/docs 读取失败: ' + e.message); }
  return { exists: true, drift: problems.length !== 0, detail: problems.length ? '文档引用漂移: ' + problems.join('; ') : '文档引用一致（plugin 版本 + 体检项数）' };
}


// --- CI 独立模式（Wave4）：GitHub Actions 无生成物/无 dbx.md 场景的静态验证 ---
// 用法：node scripts/check-drift.mjs --verify-templates | --verify-instructions
const argv = process.argv.slice(2);
if (argv.includes('--verify-templates')) {
  // 仅验证两个 template 的 JSONC 语法（失败 exit 1；正常 drift 模式下解析失败被 checkPair catch 不退非零，CI 需硬失败）
  let failed = false;
  for (const f of [omoTemplate, memTemplate]) {
    try {
      JSON.parse(stripComments(fs.readFileSync(f, 'utf8')).replace(/,(\s*[}\]])/g, '$1'));
      console.log('OK ' + path.basename(f) + ' JSONC syntax valid');
    } catch (e) {
      console.log('FAIL ' + path.basename(f) + ' parse error: ' + e.message);
      failed = true;
    }
  }
  process.exit(failed ? 1 : 0);
} else if (argv.includes('--verify-instructions')) {
  // 引用完整性 CI 版：豁免 dbx.md（gitignore 生产 host，不在 checkout 内）
  const r = checkInstructions();
  const missing = r.missing.filter((p) => !p.endsWith('dbx.md'));
  if (missing.length) { console.log('FAIL missing refs: ' + missing.join(', ')); process.exit(1); }
  console.log('OK instructions refs complete (dbx.md exempt: gitignored)');
  process.exit(0);
} else if (argv.includes('--verify-docrefs')) {
  // 文档引用一致性 CI 版：README plugin 版本 ↔ package.json、docs 体检项数 ↔ check.sh（堵 hook 旁路时的文档漂移）
  const r = checkDocRefs();
  if (r.drift) { console.log('FAIL ' + r.detail); process.exit(1); }
  console.log('OK ' + r.detail);
  process.exit(0);
}

const result = {
  omo: checkPair(omoTemplate, omoGenerated, 'omo.jsonc', ['_migrations']),
  mem: checkPair(memTemplate, memGenerated, 'opencode-mem.jsonc'),
  instructions: checkInstructions(),
  pluginSpec: checkPluginSpec(),
  docRefs: checkDocRefs(),
};
console.log(JSON.stringify(result));
