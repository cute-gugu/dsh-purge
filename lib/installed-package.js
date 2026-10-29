// Resolve only the selected profile. Never fall back to loaded code or another host.
import fs from 'node:fs';
import path from 'node:path';

export const COMMUNITY_PACKAGE = 'dsh-purge';
// 2.0.0 合并版的正式包名是 dsh-purge；dsh-purge-community 是被合并的旧包名，
// 迁移期间仍要能被识别出来（否则用户升级前 profile 会直接报"未找到安装"）。
export const LEGACY_PACKAGES = ['dsh-purge-community'];
const aliases = [COMMUNITY_PACKAGE, ...LEGACY_PACKAGES];

export function installedCommunityPackage(profile, {dependencyName} = {}) {
  if (dependencyName && !aliases.includes(dependencyName)) throw Error('Unsupported plugin dependency name');
  let manifest = {};
  try { manifest = JSON.parse(fs.readFileSync(path.join(profile, 'package.json'), 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const bundles = manifest.dsh?.profile?.bundles;
  if (bundles !== undefined && !Array.isArray(bundles)) throw Error('Invalid profile bundles');
  const selected = aliases.filter(name => bundles?.includes(name));
  const names = dependencyName ? [dependencyName] : selected.length ? selected : aliases;
  const found = [];
  for (const name of names) {
    const file = path.join(profile, 'node_modules', name, 'package.json');
    let pkg;
    try { pkg = JSON.parse(fs.readFileSync(file, 'utf8')); }
    catch (error) {
      if (error.code === 'ENOENT' && !dependencyName && !selected.includes(name)) continue;
      throw error;
    }
    if (!aliases.includes(pkg.name) || typeof pkg.version !== 'string' || !/^\d+\.\d+\.\d+(?:-[\w.-]+)?(?:\+[\w.-]+)?$/.test(pkg.version)) {
      throw Error('当前 profile 的插件包标识或版本无效: ' + name);
    }
    const directory = fs.realpathSync(path.dirname(file));
    found.push({dependencyName:name, directory, file:path.join(directory,'package.json'), package:pkg});
  }
  if (!found.length) throw Object.assign(Error('ENOENT: 当前 profile 未找到社区版插件安装'), {code:'ENOENT'});
  if (new Set(found.map(item => item.directory)).size !== 1) throw Error('当前 profile 有多个社区版安装，无法确定生效入口');
  return found[0];
}
