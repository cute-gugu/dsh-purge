import { installedCommunityPackage } from "./installed-package.js";
// Installer-only migration of package references. Never evaluates YAML tags or
// edits prompt text, permissions, plugin options, or the user's other plugins.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const ids = new Map([
  ['dsh-purge', ''], ['dsh-purge-redteam', '/redteam'],
  ['dsh-purge-presets', '/presets-plugin'],
  ['dsh-purge-redteam-store', '/redteam/store'],
  ['dsh-purge-redteam-ui', '/redteam/ui'],
]);

// 2.0.0：正式包名是 dsh-purge；dsh-purge-community 是被合并进来的旧包名。
// 因此迁移方向从「dsh-purge → dsh-purge-community」反转为「dsh-purge-community → dsh-purge」，
// 否则安装器会把刚写对的引用改成已经不存在的包名。
const PACKAGE = 'dsh-purge';
const LEGACY_PACKAGE = 'dsh-purge-community';

// Manual snapshots have no install-specific migration journal. Restore only
// known package references when the snapshot explicitly selected the old alias.
export function aliasRollbackReferences() {
  return [...ids].map(([id, suffix]) => ({id, from: LEGACY_PACKAGE + suffix, to: PACKAGE + suffix}));
}

const isKnownDirection = (id, r) => {
  const suffix = ids.get(id);
  return (r.from === LEGACY_PACKAGE + suffix && r.to === PACKAGE + suffix)
      || (r.from === PACKAGE + suffix && r.to === LEGACY_PACKAGE + suffix);
};

export function migrateReferences(text, yaml, reverse = []) {
  if (!Array.isArray(reverse) || reverse.some(r => !ids.has(r.id) || !isKnownDirection(r.id, r)))
    throw Error('迁移记录无效；未修改配置');
  const doc = yaml.parseDocument(text);
  if (doc.errors.length) throw Error('迁移前配置 YAML 无法解析：' + doc.errors[0].message);
  if (!yaml.isSeq(doc.contents)) {
    if (!text.trim()) return { text, changes: [] };
    throw Error('迁移要求 cordis.patch.yml 为补丁列表；原配置保留');
  }
  const edits = [], changes = [];
  const inspect = (row, inserted = false) => {
    if (!yaml.isMap(row)) return;
    const name = row.get('name', true), id = row.get('id');
    if (yaml.isScalar(name) && typeof name.value === 'string') {
      const suffix = ids.get(id);
      const value = name.value;
      const isLegacy = value === LEGACY_PACKAGE || value.startsWith(LEGACY_PACKAGE + '/');
      const isCurrent = value === PACKAGE || value.startsWith(PACKAGE + '/');
      if ((isLegacy || isCurrent) && suffix === undefined && !reverse.length)
        throw Error('发现自定义旧包入口，无法自动判定对应关系；原配置和备份保留，请核对入口 ID');
      if (isLegacy && !reverse.length && value !== LEGACY_PACKAGE + suffix)
        throw Error('旧包入口与 ID 不匹配；原配置保留');
      // 正向：旧包名 → 新包名。反向（回滚）：新包名 → 旧包名。
      let replacement = null;
      if (reverse.length) {
        const journal = reverse.find(r => r.id === id);
        if (journal) {
          if (value === journal.to) replacement = journal.from;
          else if (value === journal.from) replacement = journal.to;
        }
      } else if (isLegacy && value === LEGACY_PACKAGE + suffix) {
        replacement = PACKAGE + suffix;
      }
      if (replacement) {
        // An insert may be a manually registered entry, not an override of a
        // bundle. Do not silently create duplicate IDs or remove its options.
        if (inserted) throw Error('发现手动 insert 的旧包入口，需先核对与 bundle 的重复 ID；未删除或禁用入口，原配置保留');
        if (name.tag || !name.range) throw Error('动态包入口不能自动迁移；原配置保留');
        edits.push({ start: name.range[0], end: name.range[1], value: JSON.stringify(replacement) });
        changes.push({ id, from: value, to: replacement });
      }
    }
    const insert = row.get('insert', true);
    if (yaml.isSeq(insert)) for (const child of insert.items) inspect(child, true);
  };
  for (const row of doc.contents.items) inspect(row);
  for (const e of edits.sort((a,b) => b.start-a.start)) text = text.slice(0,e.start) + e.value + text.slice(e.end);
  return { text, changes };
}

export function installedYaml(profile, options) {
  // Bootstrap has no node_modules yet. Resolve the parser only AFTER DSH has
  // installed the verified candidate and its declared dependencies.
  const require = createRequire(installedCommunityPackage(profile, options).file);
  return require('yaml');
}

export function readProfilePatch(profile) {
  const file = path.join(profile, 'cordis.patch.yml');
  try { return { file, text: fs.readFileSync(file, 'utf8') }; }
  catch (e) { if (e.code === 'ENOENT') return {file, text: ''}; throw e; }
}
