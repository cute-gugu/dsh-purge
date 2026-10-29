// Disk evidence is per profile; the running copy cannot stand in for all installs.
import fs from 'node:fs';
import path from 'node:path';
import { versionIsNewer } from './update-state.js';
// 2.0.0 起正式包名是 dsh-purge；旧包名 dsh-purge-community 在迁移期仍算本插件。
const ACCEPTED_PACKAGE_NAMES = new Set(['dsh-purge', 'dsh-purge-community']);
export function profileVersions(sites, targetVersion) {
  return sites.map(site => {
    let version = '', error = '';
    try {
      const pkg = JSON.parse(fs.readFileSync(path.join(site.dir, 'package.json'), 'utf8'));
      if (!ACCEPTED_PACKAGE_NAMES.has(pkg.name) || !pkg.version) throw Error('安装包标识或版本缺失');
      version = String(pkg.version);
    } catch (e) { error = e.message; }
    return { ...site, version, error, needsUpdate: !version || versionIsNewer(targetVersion, version) };
  });
}
export function summarizeProfileUpdates(targets, fallbackHasUpdate = false) {
  const pending = targets.filter(t => t.needsUpdate);
  return {
    targets,
    hasUpdate: targets.length ? pending.length > 0 : fallbackHasUpdate,
    // Bypass only the pending-restart guard for repair of a split installation.
    retryIncomplete: pending.length > 0 && targets.some(t => !t.needsUpdate),
  };
}
