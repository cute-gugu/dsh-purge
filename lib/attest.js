// 运行时注入指纹（attest）—— 合并自 dsh-unrestricted 0.2.4 的 contractFingerprint()
//
// 目的只有一个：证明「这一轮真正送到模型手里的 sections」长什么样。
// 磁盘上的补丁、注册过的 section、面板上的绿点都只证明宿主侧就绪；
// 只有把装配后的实际段落算成指纹，才能回答"注入有没有到达模型"。
//
// 设计约束：
// - 纯读 + 一个节流写，绝不抛错打断组装（任何异常都吞掉）。
// - 只写 $DSH_HOME/dsh-purge/attest.json，不碰用户提示词、不碰宿主包。
// - 指纹口径：单段 sha256（前 16 hex）+ 全装配 sha256（前 16 hex）。

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const ATTEST_FILE = "attest.json";
const WRITE_THROTTLE_MS = 2000;
const MAX_SECTION_FP_BYTES = 64 * 1024;

let lastWriteAt = 0;
let lastAssemblyFp = "";

export function attestHome() {
  const home = process.env.DSH_HOME || path.join(os.homedir(), ".dsh");
  return path.join(home, "dsh-purge");
}

function sha16(text) {
  try {
    return crypto.createHash("sha256").update(text ?? "", "utf8").digest("hex").slice(0, 16);
  } catch {
    return "";
  }
}

function sectionText(section) {
  const raw = section?.text;
  if (typeof raw === "string") return raw;
  if (raw == null) return "";
  try {
    return String(raw);
  } catch {
    return "";
  }
}

/** 单段摘要：name / order / 字节数 / 前 64KiB 的 sha256 前 16 hex。 */
export function fingerprintSections(sections) {
  const list = Array.isArray(sections) ? sections : [];
  return list.map((section) => {
    const text = sectionText(section);
    const head = text.length > MAX_SECTION_FP_BYTES * 4 ? text.slice(0, MAX_SECTION_FP_BYTES) : text;
    return {
      name: String(section?.name ?? ""),
      order: Number.isFinite(section?.order) ? section.order : null,
      bytes: Buffer.byteLength(text, "utf8"),
      fp: sha16(head),
    };
  });
}

/** 全装配指纹：对「name:order:fp」序列再算一次 sha256。 */
export function assemblyFingerprint(rows) {
  const list = Array.isArray(rows) ? rows : [];
  const joined = list.map((r) => `${r.name}:${r.order}:${r.fp}`).join("\n");
  return sha16(joined);
}

/**
 * 记录一次装配。节流 2s，且全装配指纹没变就不写盘。
 * @returns {{assembly_fp:string, changed:boolean, written:boolean, sections:Array}}
 */
export function recordAttest(rewritten, meta = {}) {
  let rows = [];
  let fp = "";
  try {
    rows = fingerprintSections(rewritten?.sections);
    fp = assemblyFingerprint(rows);
  } catch {
    return { assembly_fp: "", changed: false, written: false, sections: [] };
  }
  const changed = fp !== lastAssemblyFp;
  lastAssemblyFp = fp;
  const now = Date.now();
  if (!changed && now - lastWriteAt < WRITE_THROTTLE_MS) {
    return { assembly_fp: fp, changed, written: false, sections: rows };
  }
  if (now - lastWriteAt < WRITE_THROTTLE_MS) {
    return { assembly_fp: fp, changed, written: false, sections: rows };
  }
  lastWriteAt = now;
  const payload = {
    version: 1,
    assembly_fp: fp,
    at: new Date(now).toISOString(),
    preset: meta.preset ?? null,
    enabled: meta.enabled !== false,
    inject_head: meta.injectHead === true,
    inject_bytes: Number.isFinite(meta.injectBytes) ? meta.injectBytes : null,
    policy: meta.policy ?? null,
    redteam: meta.redteam === true,
    section_count: rows.length,
    sections: rows,
  };
  let written = false;
  try {
    const dir = attestHome();
    fs.mkdirSync(dir, { recursive: true });
    const target = path.join(dir, ATTEST_FILE);
    const tmp = `${target}.${process.pid}.${Math.random().toString(16).slice(2, 8)}.tmp`;
    fs.writeFileSync(tmp, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
    fs.renameSync(tmp, target);
    written = true;
  } catch {
    written = false;
  }
  return { assembly_fp: fp, changed, written, sections: rows };
}

/** 读回上一次记录的装配指纹（读不到就 null）。 */
export function readAttest() {
  try {
    const raw = fs.readFileSync(path.join(attestHome(), ATTEST_FILE), "utf8");
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") return null;
    return parsed;
  } catch {
    return null;
  }
}

/** 状态页 / purge_status 用的一行摘要。 */
export function attestSummary() {
  const record = readAttest();
  if (!record) return "运行时注入指纹: 尚无记录（本进程还没装配过提示词）";
  const names = Array.isArray(record.sections) ? record.sections.map((s) => s.name).filter(Boolean) : [];
  const hasPurge = names.includes("dsh-purge");
  const boost = names.find((n) => n.startsWith("dsh-purge-boost")) || null;
  const parts = [
    `运行时注入指纹: ${record.assembly_fp} @ ${record.at}`,
    `段落数=${record.section_count} 注入头段=${hasPurge ? "是" : "否"} 强化段=${boost || "无"}`,
    `预设=${record.preset || "unknown"} policy=${record.policy || "unknown"}`,
  ];
  return parts.join("\n");
}
