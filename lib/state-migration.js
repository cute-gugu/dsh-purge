// 状态目录迁移：$DSH_HOME/dsh-purge-community → $DSH_HOME/dsh-purge
//
// 为什么需要它：2.0.0 把包名从 dsh-purge-community 改成 dsh-purge，
// 于是所有落盘状态（审计、快照、对象库、预设迁移备份）在代码里都指到了新根。
// 旧根里的东西不能丢：审计是用户的操作史，preset-migrations 是用户预设的
// 私有备份，backups/objects 是回滚唯一的依据。
//
// 原则：
// - 幂等：做完写标记文件，第二次直接返回 { skipped: true }。
// - 不覆盖：目标已存在的同名条目一律保留目标，旧文件另存 .legacy-<时间戳>。
// - 不致命：任何异常都吞掉并记进报告，绝不让插件在 activate 阶段挂掉。
// - 跨卷时 rename 会 EXDEV，退化为逐层复制后再删源。

import fs from "node:fs";
import path from "node:path";

export const LEGACY_DIR_NAME = "dsh-purge-community";
export const CURRENT_DIR_NAME = "dsh-purge";
export const MARKER_FILE = ".merged-from-dsh-purge-community";

// audit.jsonl 是追加型日志，能安全拼接；其余一律不合并内容。
const APPENDABLE = new Set(["audit.jsonl"]);

function stamp() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function movePath(from, to) {
  try {
    fs.renameSync(from, to);
    return "moved";
  } catch (error) {
    if (error?.code !== "EXDEV") throw error;
    fs.cpSync(from, to, { recursive: true, errorOnExist: false, force: false });
    fs.rmSync(from, { recursive: true, force: true });
    return "copied";
  }
}

function mergeDir(fromDir, toDir, report) {
  fs.mkdirSync(toDir, { recursive: true });
  let entries = [];
  try {
    entries = fs.readdirSync(fromDir, { withFileTypes: true });
  } catch (error) {
    report.errors.push(`${fromDir}: ${error?.message || error}`);
    return;
  }
  for (const entry of entries) {
    const from = path.join(fromDir, entry.name);
    const to = path.join(toDir, entry.name);
    try {
      if (!fs.existsSync(to)) {
        const how = movePath(from, to);
        report.moved.push(`${path.relative(fromDir, from)} (${how})`);
        continue;
      }
      if (entry.isDirectory()) {
        mergeDir(from, to, report);
        try {
          if (fs.readdirSync(from).length === 0) fs.rmdirSync(from);
        } catch { /* 非空或已被删，忽略 */ }
        continue;
      }
      if (APPENDABLE.has(entry.name)) {
        const legacy = fs.readFileSync(from, "utf8");
        if (legacy.trim()) {
          fs.appendFileSync(to, legacy.endsWith("\n") ? legacy : `${legacy}\n`, "utf8");
        }
        fs.rmSync(from, { force: true });
        report.appended.push(entry.name);
        continue;
      }
      const keep = `${to}.legacy-${stamp()}`;
      movePath(from, keep);
      report.kept.push(`${path.relative(toDir, to)} → ${path.basename(keep)}`);
    } catch (error) {
      report.errors.push(`${from}: ${error?.message || error}`);
    }
  }
}

/**
 * 一次性把旧状态根并进新状态根。
 * @param {string} home  DSH_HOME
 * @returns {{skipped?:boolean, legacy?:string, target?:string, moved?:string[], appended?:string[], kept?:string[], errors?:string[]}}
 */
export function migrateLegacyState(home) {
  const report = { moved: [], appended: [], kept: [], errors: [] };
  if (!home || typeof home !== "string") return { skipped: true, reason: "no-home", ...report };
  const legacy = path.join(home, LEGACY_DIR_NAME);
  const target = path.join(home, CURRENT_DIR_NAME);
  try {
    if (!fs.existsSync(legacy)) return { skipped: true, reason: "no-legacy-dir", legacy, target, ...report };
    if (fs.existsSync(path.join(target, MARKER_FILE))) {
      return { skipped: true, reason: "already-merged", legacy, target, ...report };
    }
    fs.mkdirSync(target, { recursive: true });
    mergeDir(legacy, target, report);
    const note = [
      `merged_at: ${new Date().toISOString()}`,
      `from: ${legacy}`,
      `moved: ${report.moved.length}`,
      `appended: ${report.appended.join(", ") || "(none)"}`,
      `kept: ${report.kept.length}`,
      `errors: ${report.errors.length}`,
      "",
    ].join("\n");
    fs.writeFileSync(path.join(target, MARKER_FILE), note, "utf8");
    try {
      if (fs.readdirSync(legacy).length === 0) fs.rmdirSync(legacy);
    } catch { /* 还有残留就留着，用户能看到 */ }
    return { legacy, target, ...report };
  } catch (error) {
    report.errors.push(String(error?.message || error));
    return { legacy, target, ...report };
  }
}
