#!/usr/bin/env node
// check-permissions.mjs - opencode.json 权限规则回归 harness（审计 T1）
// 供 check.sh 体检消费；输出单行 JSON。--report 输出人类可读表格（RED/GREEN 证据）。
//
// 用法：
//   node scripts/check-permissions.mjs             # 全案例断言，单行 JSON，fail>0 时 exit 1
//   node scripts/check-permissions.mjs --report    # 人类可读逐案例报告
//   OPENCODE_JSON=/path                           # 覆盖配置路径（测试用）
//
// 求值器复刻上游 opencode v1.18.29 语义（源：packages/opencode/src/permission/index.ts
// + packages/core/src/util/wildcard.ts + packages/opencode/src/agent/agent.ts）：
//   1. wildcard：* → .*、? → .、正则字符转义、**/x → ^.*.*/x$（要求 x 前有字面 /），
//      结尾 " .*" 特判为 "( .*)?"；\\ 归一为 /；s flag。
//   2. evaluate：rules.flat().findLast(...)，后声明优先；无匹配 → 默认 ask。
//   3. ruleset 组装：merge(defaults, user)，用户配置在后（findLast 最高优先）。
//      defaults 复刻 agent.ts 内置 read 块与 *:allow；edit/bash 无内置默认。
//   4. ask() 短路：逐 pattern 求值，deny 立即短路；全 allow 放行；其余汇聚为 ask；
//      patterns 为空 → 整体放行（不询问）。
// 置信边界：bash 段粒度用引号感知的 &&/||/;/|/换行 切分近似 tree-sitter command 节点
//（对单段命令与 && 拼接完全等价；process substitution 等罕见语法可能有出入）；
// upstream source(node) 的 redirect_statement 合并（`> file` 并入前段）未复刻。

import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.dirname(new URL(import.meta.url).pathname);
const cfgPath = process.env.OPENCODE_JSON || path.join(ROOT, '..', 'opencode.json');

// --- wildcard 匹配（逐行对照 v1.18.29 core/src/util/wildcard.ts）---
export function wildcardMatch(input, pattern) {
  const normalized = input.replaceAll('\\', '/');
  let escaped = pattern
    .replaceAll('\\', '/')
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replace(/\*/g, '.*')
    .replace(/\?/g, '.');
  if (escaped.endsWith(' .*')) escaped = escaped.slice(0, -3) + '( .*)?';
  return new RegExp('^' + escaped + '$', 's').test(normalized);
}

// --- 规则展开（对照 permission/index.ts fromConfig/expand）---
function expand(pattern) {
  const home = process.env.HOME || '/home/user';
  if (pattern.startsWith('~/')) return home + pattern.slice(1);
  if (pattern === '~') return home;
  if (pattern.startsWith('$HOME')) return home + pattern.slice(5);
  return pattern;
}

export function fromConfig(permissionCfg) {
  const rules = [];
  for (const [key, value] of Object.entries(permissionCfg ?? {})) {
    if (typeof value === 'string') {
      rules.push({ permission: key, pattern: '*', action: value });
      continue;
    }
    rules.push(...Object.entries(value).map(([p, action]) => ({ permission: key, pattern: expand(p), action })));
  }
  return rules;
}

// --- defaults（复刻 agent.ts 内置；external_directory 白名单是运行时路径，不进 harness）---
export const DEFAULTS = fromConfig({
  '*': 'allow',
  doom_loop: 'ask',
  question: 'deny',
  plan_enter: 'deny',
  plan_exit: 'deny',
  read: { '*': 'allow', '*.env': 'ask', '*.env.*': 'ask', '*.env.example': 'allow' },
});

// --- 求值（对照 permission/index.ts evaluate：findLast 后声明优先，无匹配 → ask）---
export function evaluate(permission, pattern, rules) {
  return (
    rules.findLast((r) => wildcardMatch(permission, r.permission) && wildcardMatch(pattern, r.pattern)) ?? {
      action: 'ask',
    }
  );
}

// --- ask() 短路模拟（对照 permission/index.ts ask：deny 短路 / 全 allow 放行 / 其余 ask）---
export function askVerdict(permission, patterns, rules) {
  let needsAsk = false;
  for (const p of patterns) {
    const action = evaluate(permission, p, rules).action;
    if (action === 'deny') return 'deny';
    if (action === 'ask') needsAsk = true;
  }
  return needsAsk ? 'ask' : 'allow';
}

// --- bash 段切分（近似 tree-sitter descendantsOfType("command")；跳过 cd 类首词段）---
const CWD_CMDS = new Set(['cd', 'chdir', 'popd', 'pushd', 'push-location', 'set-location']);
export function segmentBash(cmd) {
  const segs = [];
  let cur = '';
  let quote = '';
  for (let i = 0; i < cmd.length; i++) {
    const ch = cmd[i];
    if (quote) {
      cur += ch;
      if (ch === quote && cmd[i - 1] !== '\\') quote = '';
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      cur += ch;
      continue;
    }
    if ((ch === '&' && cmd[i + 1] === '&') || (ch === '|' && cmd[i + 1] === '|') || ch === ';' || ch === '|' || ch === '\n') {
      if (cur.trim()) segs.push(cur.trim());
      cur = '';
      if (ch === '&' || ch === '|') i++;
      continue;
    }
    cur += ch;
  }
  if (cur.trim()) segs.push(cur.trim());
  return segs.filter((s) => {
    const first = s.split(/\s+/)[0];
    return !CWD_CMDS.has(first);
  });
}

// --- 案例表：gap=审计缺口编号（a 相对路径/c 解释器/d 遮蔽/e tee/f docker/anchor 防回归锚点）---
// expected = 修复后期望的正确行为；修复前 RED（actual≠expected 的即缺口证据）。
const CASES = [
  // 2026-09-08 第六轮（用户批准）：ask 全清——read/bash/edit 仅留灾难级 deny（mkfs/dd/rm -rf 系）
  // 前置事实：DEFAULTS 的 read *.env ask 被用户 read *:allow 覆盖（findLast 用户规则在后）
  { gap: 'a', tool: 'read', input: 'id_rsa', expected: 'allow' },
  { gap: 'a', tool: 'read', input: 'credentials.json', expected: 'allow' },
  { gap: 'a', tool: 'read', input: 'foo.pem', expected: 'allow' },
  { gap: 'a', tool: 'read', input: '.npmrc', expected: 'allow' },
  { gap: 'a', tool: 'read', input: '.ssh/config', expected: 'allow' },
  { gap: 'a', tool: 'read', input: '.env', expected: 'allow' },
  { gap: 'a', tool: 'read', input: 'foo.env', expected: 'allow' },
  { gap: 'a', tool: 'read', input: 'src/main.ts', expected: 'allow' },
  { gap: 'c', tool: 'bash', input: 'sh -c "rm x"', expected: 'allow' },
  { gap: 'c', tool: 'bash', input: 'node -e "z"', expected: 'allow' },
  { gap: 'e', tool: 'bash', input: 'tee -a ~/.zshrc', expected: 'allow' },
  { gap: 'f', tool: 'bash', input: 'docker rm --force x', expected: 'allow' },
  { gap: 'anchor', tool: 'bash', input: 'sudo rm x', expected: 'allow' },
  { gap: 'anchor', tool: 'bash', input: 'git push --force origin main', expected: 'allow' },
  { gap: 'anchor', tool: 'bash', input: 'sh', expected: 'allow' },
  { gap: 'anchor', tool: 'bash', input: 'git status', expected: 'allow' },
  { gap: 'anchor', tool: 'bash', input: 'rm -rf /', expected: 'deny' },
  { gap: 'anchor', tool: 'bash', input: 'mkfs.ext4 /dev/disk2', expected: 'deny' },
  { gap: 'anchor', tool: 'bash', input: 'dd if=/dev/zero of=/dev/disk2', expected: 'deny' },
  { gap: 'anchor', tool: 'edit', input: '../../.zshrc', expected: 'allow' },
  { gap: 'anchor', tool: 'edit', input: '.env', expected: 'allow' },
  { gap: 'anchor', tool: 'edit', input: 'foo.pem', expected: 'allow' },
  { gap: 'anchor', tool: 'edit', input: 'src/foo.ts', expected: 'allow' },
];

function runCase(c, rules) {
  if (c.tool === 'bash') return askVerdict('bash', segmentBash(c.input), rules);
  return askVerdict(c.tool, [c.input], rules);
}

// --- 缺口 g 探针：交换 bash 块 * 与 mkfs* 的相对位置，断言结果翻转 ---
// （证明 findLast 键序敏感；常绿结构断言——上游若改语义此探针翻红；第六轮改为用现存规则）
function probeKeyOrder(rules) {
  const idxDeny = rules.findLastIndex((r) => r.permission === 'bash' && r.pattern === 'mkfs*');
  const idxStar = rules.findLastIndex((r) => r.permission === 'bash' && r.pattern === '*');
  if (idxDeny < 0 || idxStar < 0) return { ok: false, note: '探针前置条件缺失（bash mkfs* / * 规则不存在）' };
  const swapped = rules.slice();
  [swapped[idxDeny], swapped[idxStar]] = [swapped[idxStar], swapped[idxDeny]];
  const a = evaluate('bash', 'mkfs.ext4 /dev/disk2', rules).action;
  const b = evaluate('bash', 'mkfs.ext4 /dev/disk2', swapped).action;
  return { ok: a !== b, note: `原序=${a} 交换后=${b}（键序敏感=${a !== b}）` };
}
// --- 静态 lint：规则 pattern 内双空格（编译后静默失配陷阱，防御性）---
function lintDoubleSpace(rules) {
  return rules.filter((r) => r.pattern.includes('  ')).map((r) => `${r.permission}: "${r.pattern}" 含连续双空格`);
}

// --- main ---
const report = process.argv.includes('--report');
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
const rules = [...DEFAULTS, ...fromConfig(cfg.permission)];
const results = CASES.map((c) => ({ ...c, actual: runCase(c, rules) }));
const failed = results.filter((r) => r.actual !== r.expected);
const lint = lintDoubleSpace(rules);
const keyOrder = probeKeyOrder(rules);
const ok = failed.length === 0 && lint.length === 0 && keyOrder.ok;

if (report) {
  console.log(`配置: ${cfgPath}`);
  console.log(`规则数: ${rules.length}（defaults ${DEFAULTS.length} + user ${rules.length - DEFAULTS.length}）`);
  console.log('');
  for (const r of results) {
    const mark = r.actual === r.expected ? 'PASS' : 'FAIL';
    console.log(`  [${mark}] ${r.gap.padEnd(6)} ${r.tool.padEnd(4)} "${r.input}" → actual=${r.actual} expected=${r.expected}`);
  }
  console.log('');
  console.log(`  键序探针(g): ${keyOrder.ok ? 'PASS' : 'FAIL'} ${keyOrder.note}`);
  for (const l of lint) console.log(`  [LINT] ${l}`);
  console.log('');
  console.log(`总计 ${results.length} 案例：${results.length - failed.length} 通过 / ${failed.length} 失败`);
  console.log(ok ? 'GREEN：权限规则全部满足期望' : 'RED：存在缺口（修复配置后转 GREEN）');
} else {
  console.log(JSON.stringify({
    permission: {
      total: results.length,
      failed: failed.length,
      failures: failed.map((r) => ({ gap: r.gap, tool: r.tool, input: r.input, expected: r.expected, actual: r.actual })),
      lint,
      keyOrderSensitive: keyOrder.ok,
      note: keyOrder.note,
    },
  }));
}
process.exit(ok ? 0 : 1);
