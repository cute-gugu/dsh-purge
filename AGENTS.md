# AGENTS.md — 给 AI agent 的 Purge 使用说明书

> 这份文件是写给**在 DSH 里干活的 agent** 的，不是营销文档。
> 当前版本：**2.0.0** · 适配 DSH Desktop **0.2.1-rc.3**（rc.1 / rc.2 同样通过）
> 版本号由 `npm run check:docs` 与 `package.json` 校验，发版必须同步。

---

## 0. 30 秒版本

- 这个插件（`dsh-purge`）把 DSH 里**拦你的东西**拆掉：审批弹窗、沙箱拒绝、fs 围栏、工具结果修剪、计划模式硬拦、`ask_user_question` 等待、以及模型自己的拒绝倾向。
- 你不需要"绕过"它——**它就是替你拆闸的**。看到"我不能/建议你先确认"这类输出，多半不是插件失效，而是模型层的问题，按 §5 排查。
- 你的操作入口只有两个：**面板（左侧栏 Purge）** 和 **CLI（`purge`）**。别手改 `~/Library/.../Resources/app` 下的宿主文件，改了会被下一次「应用」覆盖。

## 1. 心智模型：五层，各管一件事

| 层 | 由谁提供 | 生效方式 | 你能怎么查 |
| --- | --- | --- | --- |
| **宿主补丁**（80 条） | 本插件写进 DSH 源码 | 点「应用」写入 → **退出重开**才加载 | `selfcheck` 看各层 `applied/required` |
| **提示词注入** | 插件运行时（每步重贴） | `prompt-inject.md` 作为 `dsh-purge` section | 探针（§4）或看 `selfcheck` 的「运行时提示词注入」 |
| **破甲强化段** | 插件运行时 | 尾部 section（默认开） | `purge boost` |
| **权限配置** | profile 的 `cordis.patch.yml` | `danger-full-access` + `approval: never` | `selfcheck` 的「当前 profile 的权限选择」 |
| **agent 预设** | `unrestricted` 预设 | 新会话下拉里选 | 面板/预设下拉 |

**关键结论**：宿主补丁与权限配置仍为全局；提示词注入和强化段默认全局，可用 `excludePresets` 按预设排除。排除不等于撤销全局补丁。

## 2. 生命周期：装 → 应用 → 重开

```
通过官方界面/CLI 首次安装，或社区安装器备份迁移
   ↓
点「应用」→ 解包 host / 写 80 条补丁 / 建快照
   ↓
退出并重开 DSH   ← 补丁只有重启后才被加载
   ↓
selfcheck 全绿 = 可以开工
```

**什么时候需要再点一次「应用」**（这是最高频的维护动作）：

1. DSH 官方更新之后（`app.asar` 会重新出现，旧补丁全部失效）；
2. 插件自身升级之后（新补丁要重新写）；
3. 新装了带工具面/预设的插件（会多出补丁目标）；
4. 发现模型开始推脱、或者工具突然被追问审批。

一句话：**「应用」是幂等的**，不确定就点它，然后退出重开。

## 3. CLI 参考（全部命令 + 退出码）

下表的 `purge` 是命令简称，不保证安装进 profile 后已在系统 PATH。先按[CLI 回滚与定位说明](docs/INSTALLATION.md#cli-rollback)使用当前 profile 的 `bin/community.js` 与正确运行时；不要为了找命令再安装另一份 npm 包。安装验证看版本、bundle 和配置合成；不能把模型是否拒绝当作安装成功判据。

| 命令 | 作用 | 退出码 |
| --- | --- | --- |
| `purge status` | 宿主路径、补丁计数 | 0 |
| `purge selfcheck [--json\|--text]` | 25 层逐层证据 | **broken → 1**，pending/ok → 0 |
| `purge host-status` | 只读磁盘布局与当前服务入口证据，不退出/换包/重启 | 0，须检查 state |
| `purge diagnose [--json]` | 锚点漂移诊断（含行号 + 片段） | 0 |
| `purge reanchor list\|show\|apply <id> [--index n] [--lines a-b] [--yes]\|clear <id>` | 半自动重锚：把新锚点钉成本地覆盖 | 0 |
| `purge probe [new]` | 生成/查看运行时探针 | 0 |
| `purge audit [--limit n]` | 最近动作记录（apply/revert/boost/probe/preset/reanchor） | 0 |
| `purge boost [on\|off]` | 尾部强化段开关 | 0 |
| `purge preset [status\|install [--force]]` | `unrestricted` 预设落盘 | 0 |
| `purge usage` / `prune` | 备份占用 / 清理+GC | 0 |
| `purge backup` / `rollback <id>` | 快照 / 回滚插件 | 0 |
| `purge apply` / `revert` / `uninstall` / `edit` | 原版能力（转发 `dsh-purge`） | 透传 |

`selfcheck` 状态：`ok`（已确认）/ `pending`（待应用）/ `inferred`（宿主推导，黄）/ `unknown`（证据不足，黄）/ `broken`（已确认故障或权限不匹配）。
**pending 不是故障**——别去改补丁表，点一次「应用」即可。

`purge_status` 工具默认**精简输出**（计数 + `applied`/`pending` 的 id 区间）；要看逐条明细传 `{"detail":"full"}`。

## 4. 运行时探针：证明"注入真的到了模型"

文件被改、section 被注册，只证明宿主侧就绪；探针证明模型**收到了**。

```sh
purge probe new
# → {"nonce":"purge-1a2b3c4d", "message":"请原样输出下面这行…[purge-1a2b3c4d]"}
```

然后任意发一句对话。**模型原样回显该 nonce = 链路通**。探针 30 分钟自动过期，不会长期占 token。

排查原则：
- 回显了但模型仍然推脱 → 问题在**模型层/人设**，不是插件（换强化段或预设人设）；
- 没回显 → 注入没到达（看 `selfcheck` 的运行时注入层、`boost` 是否被关、`injectPosition` 是否被改成 `tail` 但宿主没重贴）。

## 5. 症状 → 动作（决策树）

| 症状 | 先跑 | 判读 | 动作 |
| --- | --- | --- | --- |
| 补丁数不是 73/76（全量 80） | `selfcheck --json` | 看 `layers[].state` | pending → 点应用；broken → `diagnose` |
| 全部 `missing_file` | `status` | `ai_base` 为空 | 宿主未解包：点应用 → 重开 |
| 模型开始推脱/要求确认 | `probe new` | 回显否 | 回显：调人设/强化段；不回显：检查注入层 |
| 工具被拒绝执行 | `selfcheck` | 沙箱/审批层是否绿 | 绿 → 属工具自身限制；红 → 点应用 |
| DSH 刚更新过 | `status` | `asar_still_sealed` | 点应用 → 重开 → `selfcheck` |
| 面板显示版本不一致 | 面板顶部黄条 | 界面与后端不同版本 | 先核对磁盘与运行版本；按 README 选择正确安装/迁移入口 |
| 想撤销一切 | — | — | `revert`（只撤补丁）/ `rollback <id>`（回滚插件） |

## 6. 状态与文件（你可以安全读，不要乱写）

| 路径 | 内容 |
| --- | --- |
| `$DSH_HOME/dsh-purge/tuning.json` | `{boost, injectPosition, askNoBlock}` |
| `$DSH_HOME/dsh-purge/probe.json` | 探针 nonce（30 分钟 TTL） |
| `$DSH_HOME/dsh-purge/anchor-overrides.json` | 本地重锚覆盖（不改插件源码；删掉即恢复出厂锚点） |
| `$DSH_HOME/dsh-purge/audit.jsonl` | 动作审计（1MB 轮转，保留 2 份）；面板「维护 → 最近动作」 |
| `$DSH_HOME/dsh-purge/attest.json` | 运行时注入指纹（2.0.0 起）：`assembly_fp` + 每段 `fp`，证明"这一轮到底贴了什么" |
| `$DSH_HOME/dsh-purge/applied.json` · `installed-rev` | 上次应用的插件版本 |
| `$DSH_HOME/dsh-purge/backups/<id>/` | 快照（`manifest.json` + 小文件；大文件在 `objects/`） |
| `$DSH_HOME/.agent-presets/unrestricted/` | 无限制模式预设（首行 `# managed-by: dsh-purge` 时会被新版覆盖） |
| `$DSH_HOME/prompt-inject.md` | **用户的注入正文**，插件只读不改（除非用户点保存） |

**不变量**：`prompt-inject.md`、规则集、其他插件配置，任何时候都不该被「应用」或「回滚」覆盖。

## 7. 补丁表：80 条，怎么读、怎么加

- 定义在 `lib/core.js` 的 `ALL_PATCHES`（`PATCHES` / `CODE_PATCHES` / `ENGINE_PATCHES` / `NEW_TOOL_PATCHES`）。
- 每条 = `{id, name, layer, file, replacements:[{pattern, replace}], markers, optional?}`；`pattern` 是对宿主源码的**精确片段**（或正则），`markers` 用来判断"已应用"。
- 新增一条的规矩：
  1. 在 `targetFiles()` 里登记目标文件键；
  2. `replace` 里留一条 `[dsh-purge]` 标记，写进 `markers`；
  3. 在 `test/patch-anchors.test.mjs` 里钉一份真实源码片段做回归；
  4. `optional: true` 用于第三方插件目标（不在场时显示"不适用"而不是失败）。
- 宿主升级后锚点漂移：`diagnose` 会给出文件、行号、旧锚点首行、以及**可能的新落点**片段。
- 确认新落点后：`reanchor apply <id> --lines A-B`（先看 dry-run 的候选片段，再加 `--yes` 写入）。覆盖存 `anchor-overrides.json`，引擎会把它当该条的 pattern；`reanchor clear <id>` 撤销。

## 8. 预设：`unrestricted`（无限制模式）

- 它是 **standard 的超集**（20 行，工具面完全一致），差别只在人设：执行优先、不重复声明边界、多轮不退化。
- 由 `lib/presets-plugin.js` 注册到 `agentPresets`（**只放文件不会出现在下拉里**）。
- 安装：`purge preset install`；首次注册后，面板/新会话下拉可见。
- 不要把它当成"额外破甲"——破甲靠宿主补丁，预设只改人格。
- 回归测试卡：`docs/preset-test.md`（A/B 五条 prompt + 判读标准 + 不通过怎么办）。
- 注入默认**跳过** `minimal` 预设（`skipMinimal: true`）：该预设自带完整 persona 与固定工具面，17K 注入在那里只烧 token。要恢复注入设 `skipMinimal: false`；这与 `excludePresets` 不同，不会因预设不可判定而连带关掉注入。

## 9. 版本与兼容

| 组件 | 值 |
| --- | --- |
| 插件 | `dsh-purge` 2.0.0 |
| 已验证宿主 | DSH Desktop 0.2.1-rc.1 / 0.2.1-rc.2 / 0.2.1-rc.3 |
| 其它宿主 | 允许应用，但 `selfcheck` 会标"未验证"；先看 `diagnose` |
| Node | ≥18（桌面版自带运行时即可） |

## 10. 这份文档的维护规则

- 每次发版必须同步：首部版本行、§9 表格、§3 命令表（如有新增）。
- `npm run check:docs` 会校验 `AGENTS.md` / `README.md` / `release-notes.md` / `package.json` 的版本一致，CI 里跑；不一致直接失败。
- `npm run check` = syntax + docs + `prompt-budget`：每轮固定提示词成本有硬预算（注入正文 / 强化段 / 能力段 / 本文件），超了直接失败。
- 面向人的概览在 `README.md`；**面向 agent 的操作细节以本文件为准**——两者冲突时，先信本文件，再去改 README。

## 11. 更新偏好（1.6.5 起）

维护页分别设置自动检查和自动安装。默认只检查，间隔 6 小时。偏好存 `$DSH_HOME/dsh-purge/update-preferences.json`，状态存 `update-status.json`。不要为启用更新打开 `autoApplyOnStart`，不要改动提示词或 profile 权限。`GET /dsh-purge/community` 返回 `update_preferences` / `update_status`；`POST` 同路径 `{op:"preferences",value:{autoCheck:true,autoInstall:false,intervalHours:6}}` 保存（省略字段保留现值，间隔 1–168）。保存不代表安装；安装后等用户手动重启，不自行调用重启接口。

<a id="installation"></a>
## 12. 安装 / 更新边界：Agent 必读

1. 入口顺序：DSH 官方插件界面/市场确认框 → 该实例的 `dsh plugin --profile <实际名称> add <固定版本 TGZ URL>` → 本仓库社区脚本 `scripts/install.sh` / `scripts/install.ps1`。官方管理器维护 `dsh.bundle`；我们的索引、TGZ 与脚本是社区内容。没有供此流程使用的裸 npm 包名：不运行 `add dsh-purge` 或全局 npm 安装。已有 `dsh-purge`/独立面板时选社区安装器迁移，不能先卸载旧包。
2. 先读目标 DSH 版本、可执行文件、`DSH_HOME`、profile，确认已经初始化。Desktop 默认 `desktop`，CLI/Web 示例为 `web`，不能混用；不要下载另一套 npx 宿主装进当前桌面实例。脚本先下载到独立临时路径，审阅后 dry-run 再执行；dry-run 只验证前置条件、下载与 SHA256，不安装依赖、不验证完整启动。
3. 正式安装会备份、调用官方 CLI、迁移旧包引用、验证磁盘版本；它会写宿主目录（修 `app/runtime` 链接、Linux 可能准备用户宿主副本），所以不能承诺"不改 DSH 本体"。脚本与 bootstrap 来自 master，SHA256 校验的对象是发行 TGZ，不能声称脚本也经过独立签名校验。
4. `ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION` 不是一律"发布太新"：若同时明确报 `@dsh-ops/bash-win32-x64@<版本> ... version not present in registry manifest`，安装器仅对这一公开包、明确的公开镜像做一次 scoped registry 重试；官方 name/version/time/integrity/tarball 不完整则停止，其余依赖保持原源。
5. 真实的发布时间不足、integrity/trust 错误、私有源、未知错误：保持失败，保留日志与快照；不要设 `minimumReleaseAge=0`、`trustLockfile`，不要删锁文件、全局清缓存或改全局 npm 源，不要把失败归因于镜像。不能把失败说成成功；不要安装后自动 apply/restart。
6. 失败先看返回的 `backup_id`，核对 package.json / 锁文件 / 安装状态；恢复走 `rollback <id>`，保留用户内容。公开 issue 只附脱敏错误，不上传配置、凭证、提示词或完整备份。
7. 证据边界：UI/登录/宿主补丁验收与安装/备份/回滚分别记录，不能以一种通过代替另一种；`diagnose` 与磁盘版本核对以 package.json / release-notes 为准。

## 13. 历史维护记录

`§11` 之后原有的 1.6.5–1.6.54 逐版 issue 复盘（约 18K 字符）已移到 [docs/MAINTENANCE-HISTORY.md](docs/MAINTENANCE-HISTORY.md)。要查具体版本的诊断结论、命令冲突、换包相位、注入排序 A/B 数据时去那里；本文件只保留当前有效规则。

## 14. 本地一键导入包（无 Node 的机器）

`tools/local-import/` 产出离线控制台：解压后双击 `dsh-purge.bat`（菜单：安装/自检/卸载/路径，也支持 `install|check|uninstall|paths` 直通），配套三个 `.ps1` 与 `payload\`。

- 依赖写 `"dsh-purge": "file:<母本路径/正斜杠>"`（**别用 `link:`**，要建符号链接）：母本 `%LOCALAPPDATA%\dsh-purge\<version>` → 整树复制到 `<profile>\node_modules\dsh-purge`；bundles 文本级重建保原格式，写前校验并备份。
- payload 只带 `node_modules/yaml`；`@deepseek-ai/*` 是宿主 peer，别带。
- 编码：`.ps1`/`.txt` = UTF-8+BOM+CRLF，`.bat` = **GBK(936)**+CRLF，否则 cmd 乱码；`build.mjs` 有往返校验。
- 自检退出码契约：`0` 正常 / `1` 可修 / `2` 没装，不要改。
- 构建 `node tools/local-import/build.mjs`。
