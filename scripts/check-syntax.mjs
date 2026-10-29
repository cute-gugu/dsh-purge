#!/usr/bin/env node
// 语法自检：对 lib/ 与 bin/ 下所有 .js 跑一遍 `node --check`。
//
// 为什么不用 test/ 或整仓扫描：scripts/ 里有几个上游脚本的 shebang 不在第一行
// （scripts/export-engagement-report.mjs 等），`node --check` 会直接报
// "Invalid or unexpected token"。它们不属于插件入口，也不由插件运行时加载，
// 因此这里只检查会被 DSH 真正 import 的目录，并把 scripts/ 的问题单列成提示。
//
// 退出码：0 = 全部通过；1 = 有语法错误。

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const targets = ["lib", "bin"];

function walk(dir, out = []) {
  let entries = [];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.isFile() && /\.(js|mjs|cjs)$/.test(entry.name)) out.push(full);
  }
  return out;
}

const files = targets.flatMap((dir) => walk(path.join(root, dir)));
const failures = [];

for (const file of files) {
  const result = spawnSync(process.execPath, ["--check", file], { encoding: "utf8" });
  if (result.status !== 0) {
    const detail = String(result.stderr || result.stdout || "").trim().split("\n").slice(0, 6).join("\n");
    failures.push({ file: path.relative(root, file), detail });
  }
}

console.log(`[check-syntax] checked ${files.length} files under ${targets.join(", ")}`);

if (failures.length === 0) {
  console.log("[check-syntax] ok");
  process.exit(0);
}

for (const failure of failures) {
  console.error(`[check-syntax] FAIL ${failure.file}`);
  console.error(failure.detail);
}
console.error(`[check-syntax] ${failures.length} file(s) failed`);
process.exit(1);
