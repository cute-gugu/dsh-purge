// 每轮固定注入成本体检：注入正文 / 强化段 / 能力段 / AGENTS.md。
//
// 目的不是"越小越好"，而是让"这一轮到底贴了多少字符"变成可测的数字，并且
// 在超出预算时让 CI 直接失败——否则瘦身成果会在下一次功能追加里悄悄涨回去。
//
// 用法：
//   node scripts/prompt-budget.mjs          报告 + 超预算则 exit 1
//   node scripts/prompt-budget.mjs --json   机器可读
//   node scripts/prompt-budget.mjs --quiet  只报超预算的项

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");

// 预算是硬门槛：超过即 CI 失败。数值基于 2.0.0 瘦身后的实测，留了约 10% 余量。
export const BUDGET = {
  "注入正文 (defaultOverrideText)": 18500,
  "强化段 (BOOST_TEXT)": 1600,
  "能力段 (capability)": 1400,
  "AGENTS.md (agent 指令)": 8500,
};

const args = new Set(process.argv.slice(2));
const asJson = args.has("--json");
const quiet = args.has("--quiet");

function chars(text) {
  return [...String(text ?? "")].length;
}

function delimited(text) {
  const t = String(text ?? "");
  return {
    ch: chars(t),
    bytes: Buffer.byteLength(t, "utf8"),
    lines: t ? t.split("\n").length : 0,
  };
}

async function loadModules() {
  const out = {};
  try {
    const core = await import(pathToFileURL(path.join(root, "lib", "core.js")).href);
    out.inject = typeof core.defaultOverrideText === "function" ? core.defaultOverrideText() : "";
  } catch (err) {
    out.injectError = String(err && err.message ? err.message : err);
    out.inject = "";
  }
  try {
    const boost = await import(pathToFileURL(path.join(root, "lib", "boost.js")).href);
    out.boost = String(boost.BOOST_TEXT || "");
  } catch {
    out.boost = "";
  }
  try {
    const cap = await import(pathToFileURL(path.join(root, "lib", "capability-protocol.js")).href);
    out.capability = String(
      (typeof cap.capabilityProtocolText === 'function' ? cap.capabilityProtocolText() : '')
      || Object.values(cap).find((v) => typeof v === "string" && v.length > 200)
      || "",
    );
  } catch {
    out.capability = "";
  }
  try {
    out.agents = fs.readFileSync(path.join(root, "AGENTS.md"), "utf8");
  } catch {
    out.agents = "";
  }
  return out;
}

/** 注入正文与强化段里"同一句约束"的重复度：按行长 ≥60 的整行比对。 */
function duplication(a, b) {
  const split = (t) => String(t || "").split("\n").map((l) => l.trim()).filter((l) => l.length >= 60);
  const right = new Set(split(b));
  return split(a).filter((l) => right.has(l));
}

const text = await loadModules();
const rows = [
  ["注入正文 (defaultOverrideText)", text.inject],
  ["强化段 (BOOST_TEXT)", text.boost],
  ["能力段 (capability)", text.capability],
  ["AGENTS.md (agent 指令)", text.agents],
].map(([label, body]) => ({ label, ...delimited(body) }));

const dup = duplication(text.inject, text.boost);
const over = rows.filter((row) => row.ch > BUDGET[row.label]);
const totalInject = rows
  .filter((row) => row.label !== "AGENTS.md (agent 指令)")
  .reduce((sum, row) => sum + row.ch, 0);

if (asJson) {
  console.log(JSON.stringify({
    rows,
    budget: BUDGET,
    over: over.map((row) => ({ label: row.label, ch: row.ch, budget: BUDGET[row.label] })),
    injection_total_ch: totalInject,
    duplicate_lines: dup.length,
    inject_error: text.injectError || null,
  }, null, 2));
} else if (!quiet) {
  console.log("每轮固定提示词成本 / per-turn prompt budget\n");
  for (const row of rows) {
    const cap = BUDGET[row.label];
    const mark = cap == null ? "·" : row.ch > cap ? "✗" : "✓";
    const ratio = cap ? ` (${((row.ch / cap) * 100).toFixed(0)}% of ${cap})` : "";
    console.log(`${mark} ${row.label.padEnd(34)} ${String(row.ch).padStart(6)} ch  ${String(row.bytes).padStart(6)} B  ${String(row.lines).padStart(4)} lines${ratio}`);
  }
  console.log(`\n注入三件套合计: ${totalInject} ch`);
  console.log(`注入正文 × 强化段 完全重复行: ${dup.length}`);
  if (text.injectError) console.log(`注入正文读取失败: ${text.injectError}`);
}

if (over.length) {
  console.error("\n超出预算:");
  for (const row of over) console.error(`- ${row.label}: ${row.ch} > ${BUDGET[row.label]}`);
  process.exit(1);
}
if (!asJson && !quiet) console.log("\n预算内 / ok");
