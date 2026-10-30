// 构建「本地一键导入」交付包
//   node tools/local-import/build.mjs
// 产出：<repo>/dist/dsh-purge-import/<文件> 与 <repo>/dist/dsh-purge-import-<version>.zip
//
// 思路：把插件仓库自身（排除 .git / 开发残留）复制成 payload\dsh-purge，
// 连同两份 PowerShell 脚本与说明一起打包，朋友双击 一键导入.cmd 即可离线安装。

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url)); // <repo>/tools/local-import
const SRC = path.resolve(HERE, "..", "..");                 // <repo>
const REPO_PARENT = path.resolve(SRC, "..");
const OUT = path.join(REPO_PARENT, "_dist");
const NAME = "dsh-purge-import";
const DIST = path.join(OUT, NAME);
const PAYLOAD = path.join(DIST, "payload", "dsh-purge");

const pkg = JSON.parse(fs.readFileSync(path.join(SRC, "package.json"), "utf8"));
const VERSION = pkg.version;

function log(m) { console.log(m); }

const SKIP_DIRS = new Set([
  ".git", ".github", ".vscode", "_tmp", "_dist", "_dist-src", "_smoke", "_backup",
  "node_modules", "coverage", "dist",
]);
const SKIP_FILES = new Set(["package-lock.json", "pnpm-lock.yaml", "lib/default-prompt-inject.orig.md"]);

let copied = 0;
function copyTree(from, to, rel = "") {
  fs.mkdirSync(to, { recursive: true });
  for (const ent of fs.readdirSync(from, { withFileTypes: true })) {
    const relPath = rel ? `${rel}/${ent.name}` : ent.name;
    if (ent.isDirectory()) {
      if (SKIP_DIRS.has(ent.name)) continue;
      copyTree(path.join(from, ent.name), path.join(to, ent.name), relPath);
    } else if (ent.isFile()) {
      if (SKIP_FILES.has(relPath)) continue;
      if (ent.name.endsWith(".tgz") || ent.name.endsWith(".log")) continue;
      fs.copyFileSync(path.join(from, ent.name), path.join(to, ent.name));
      copied++;
    }
  }
}

// fs.cpSync 在本机 Windows 上复制 node_modules 时会以 0xC0000409 fail-fast 崩溃，
// 这里用逐文件的递归复制替代（与 copyTree 同一条路径，已验证稳定）。
function copyDirPlain(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const ent of fs.readdirSync(from, { withFileTypes: true })) {
    const src = path.join(from, ent.name);
    const dst = path.join(to, ent.name);
    if (ent.isDirectory()) copyDirPlain(src, dst);
    else if (ent.isFile()) fs.copyFileSync(src, dst);
  }
}

function writeUtf8Bom(target, text) {
  const crlf = text.replace(/\r\n/g, "\n").replace(/\n/g, "\r\n");
  fs.writeFileSync(target, Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(crlf, "utf8")]));
  log(`  + ${path.basename(target)} (UTF-8 BOM, CRLF, ${crlf.length} ch)`);
}
function writeAscii(target, text) {
  const crlf = text.replace(/\r\n/g, "\n").replace(/\n/g, "\r\n");
  fs.writeFileSync(target, Buffer.from(crlf, "ascii"));
  log(`  + ${path.basename(target)} (ASCII, CRLF, ${crlf.length} ch)`);
}
// .bat 里的中文必须用系统 ANSI（中文 Windows = 936/GBK），UTF-8 会被 cmd 读成乱码
function writeGbk(target, text) {
  const crlf = text.replace(/\r\n/g, "\n").replace(/\n/g, "\r\n");
  const tmp = path.join(DIST, `.tmp-${path.basename(target)}`);
  fs.writeFileSync(tmp, crlf, "utf8");
  const q = (s) => s.replace(/'/g, "''");
  const out = execFileSync("powershell", [
    "-NoProfile", "-Command",
    `$t = [System.IO.File]::ReadAllText('${q(tmp)}', [System.Text.Encoding]::UTF8); ` +
    `[System.IO.File]::WriteAllText('${q(target)}', $t, [System.Text.Encoding]::GetEncoding(936)); ` +
    `$b = [System.IO.File]::ReadAllText('${q(target)}', [System.Text.Encoding]::GetEncoding(936)); ` +
    `if ($b -ceq $t) { 'ROUNDTRIP-OK' } else { 'ROUNDTRIP-FAIL' }`,
  ], { encoding: "utf8" }).trim();
  fs.rmSync(tmp, { force: true });
  if (!out.includes("ROUNDTRIP-OK")) {
    console.error(`  ! ${path.basename(target)} GBK 往返不一致，中文可能有字符不在 GBK 内：${out}`);
    process.exit(1);
  }
  log(`  + ${path.basename(target)} (GBK/936, CRLF, ${crlf.length} ch)`);
}
function sizeOf(p) {
  let total = 0, files = 0;
  const walk = (d) => {
    for (const ent of fs.readdirSync(d, { withFileTypes: true })) {
      const f = path.join(d, ent.name);
      if (ent.isDirectory()) walk(f);
      else { total += fs.statSync(f).size; files++; }
    }
  };
  walk(p);
  return { total, files };
}

// ---------------------------------------------------------------- 1. payload
fs.rmSync(DIST, { recursive: true, force: true, maxRetries: 3 });
fs.mkdirSync(DIST, { recursive: true });
log(`payload ← ${SRC}`);
copyTree(SRC, PAYLOAD);
log(`  复制 ${copied} 个文件`);

// node_modules: 只带 yaml（@deepseek-ai/* 是宿主提供的 peer，带进去会遮蔽宿主版本）
const yamlSrc = path.join(SRC, "node_modules", "yaml");
if (!fs.existsSync(yamlSrc)) {
  console.error(`缺 yaml 依赖：${yamlSrc} —— 先在仓库里跑 npm install --omit=dev`);
  process.exit(1);
}
fs.mkdirSync(path.join(PAYLOAD, "node_modules"), { recursive: true });
copyDirPlain(yamlSrc, path.join(PAYLOAD, "node_modules", "yaml"));
for (const junk of ["package-lock.json", ".package-lock.json"]) {
  const p = path.join(PAYLOAD, "node_modules", junk);
  if (fs.existsSync(p)) fs.rmSync(p, { force: true });
}
log("  携带 node_modules/yaml");

// ---------------------------------------------------------------- 1.5 一致性门禁
// 2026-10-29 事故：2.0.0 从 dsh-purge-community 改名后，client.js 仍把自己注册成旧 id，
// 宿主按 entry id 取不到客户端模块 → web boot: 1 entry did not activate + import failed → 恢复模式。
// 这里把"包名 == 客户端注册 id == 各处 name 前缀"钉死，打包阶段就拦住同类问题。
const LEGACY_NAMES = ["dsh-purge-community", "dsh-purge-panel"];
const gate = [];

function readUtf8(p) { return fs.readFileSync(p, "utf8"); }

const clientFile = path.join(PAYLOAD, "client.js");
if (!fs.existsSync(clientFile)) {
  gate.push("payload 缺 client.js");
} else {
  const src = readUtf8(clientFile);
  const m = src.match(/__ModuleLoader__\.load\(\s*\{\s*id\s*:\s*["']([^"']+)["']/);
  if (!m) {
    gate.push("client.js 里找不到 __ModuleLoader__.load({id:...})，无法校验注册 id");
  } else if (m[1] !== pkg.name) {
    gate.push(`client.js 注册 id 是 "${m[1]}"，与包名 "${pkg.name}" 不一致 —— 宿主会 import failed 并进恢复模式`);
  }
  for (const legacy of LEGACY_NAMES) {
    if (src.includes(`"${legacy}"`) || src.includes(`'${legacy}'`)) {
      gate.push(`client.js 里还有旧名 "${legacy}"（面板命名空间 / 注册 id 未改净）`);
    }
  }
}

// bundle 补丁与预设里的 name 行若指向旧包子路径，宿主校验 peer 依赖时会 ENOENT 并禁用该行
const ymlFiles = [];
(function walkYml(dir) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const f = path.join(dir, ent.name);
    if (ent.isDirectory()) { if (ent.name !== "node_modules") walkYml(f); }
    else if (/\.ya?ml$/i.test(ent.name)) ymlFiles.push(f);
  }
})(PAYLOAD);

for (const f of ymlFiles) {
  readUtf8(f).split(/\r?\n/).forEach((line, i) => {
    const m = line.match(/^\s*name\s*:\s*['"]?([^\s'"]+)['"]?\s*$/);
    if (!m) return;
    const head = m[1].split("/")[0];
    if (LEGACY_NAMES.includes(head)) {
      gate.push(`${path.relative(PAYLOAD, f)}:${i + 1} 的 name 仍指向旧包 "${m[1]}" —— 宿主会 ENOENT 并禁用该行`);
    }
  });
}

if (gate.length) {
  console.error("\n打包中止：产物一致性门禁未通过");
  for (const g of gate) console.error(`  ✗ ${g}`);
  console.error(`\n包名 = ${pkg.name}；改完重跑 node tools/local-import/build.mjs`);
  process.exit(1);
}
log(`  一致性门禁通过（包名 ${pkg.name} = client 注册 id，yml 无旧包引用）`);

// ---------------------------------------------------------------- 2. 脚本
writeUtf8Bom(path.join(DIST, "install-dsh-purge.ps1"), fs.readFileSync(path.join(HERE, "install-dsh-purge.ps1"), "utf8"));
writeUtf8Bom(path.join(DIST, "uninstall-dsh-purge.ps1"), fs.readFileSync(path.join(HERE, "uninstall-dsh-purge.ps1"), "utf8"));
writeUtf8Bom(path.join(DIST, "check-dsh-purge.ps1"), fs.readFileSync(path.join(HERE, "check-dsh-purge.ps1"), "utf8"));
writeAscii(path.join(DIST, "一键导入.cmd"), fs.readFileSync(path.join(HERE, "一键导入.cmd"), "utf8"));
writeAscii(path.join(DIST, "卸载.cmd"), fs.readFileSync(path.join(HERE, "卸载.cmd"), "utf8"));
writeGbk(path.join(DIST, "dsh-purge.bat"), fs.readFileSync(path.join(HERE, "dsh-purge.bat"), "utf8"));
writeUtf8Bom(path.join(DIST, "README-先看我.txt"), fs.readFileSync(path.join(HERE, "README-先看我.txt"), "utf8"));

// ---------------------------------------------------------------- 3. 体积/打包
const s = sizeOf(DIST);
log(`\n${NAME} v${VERSION}: ${s.files} 文件, ${(s.total / 1048576).toFixed(2)} MB`);
fs.writeFileSync(path.join(OUT, "build-info.txt"),
  `name=${NAME}\nversion=${VERSION}\npackage=${pkg.name}\nclient-id=${pkg.name}\ngate=ok\nfiles=${s.files}\nbytes=${s.total}\nbuilt=${new Date().toISOString()}\n`);

const zipPath = path.join(OUT, `${NAME}-${VERSION}.zip`);
if (fs.existsSync(zipPath)) fs.rmSync(zipPath, { force: true });
log(`\n打包 ${zipPath}`);
execFileSync("powershell", [
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
  `Compress-Archive -LiteralPath '${DIST}' -DestinationPath '${zipPath}' -CompressionLevel Optimal -Force`,
], { stdio: "inherit" });
log(`zip: ${(fs.statSync(zipPath).size / 1048576).toFixed(2)} MB`);
log("done");
