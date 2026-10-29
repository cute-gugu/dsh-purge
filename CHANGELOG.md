# 变更记录

本文件按版本倒序记录本 fork 的变化。逐版发行说明在 `docs/releases/`，本文件只写
「哪个版本合并了什么、动了哪些面」。

## 2.0.0 — 合并 dsh-unrestricted

合并来源：

- `dsh-purge-community` 1.6.55（本 fork 的前身，80 条宿主补丁 + 运行时注入 + 面板 + 演练台）
- `dsh-unrestricted` 0.2.4（纯运行时提示词融合，25 files / 0.23 MB / 0 运行时依赖）

### 新增

- `lib/attest.js`：运行时注入指纹。装配后对 sections 逐个算 sha256，写
  `$DSH_HOME/dsh-purge/attest.json`（节流 2s，指纹不变不写盘）。
- `lib/state-migration.js`：`$DSH_HOME/dsh-purge-community` → `$DSH_HOME/dsh-purge`
  一次性合并，幂等、不覆盖、失败不致命。
- `GET /dsh-purge/community` 返回 `attest`；`POST {op:"attest"}` 单独取指纹。
- `purge_status` 输出附加「运行时注入指纹」摘要。
- 配置项 `attest`（默认 `true`），可关掉指纹写入。
- `scripts/check-syntax.mjs`：对 `lib/` 与 `bin/` 跑 `node --check`。

### 瘦身（每轮固定提示词成本）

| 项 | 前 | 后 | 幅度 |
| --- | --- | --- | --- |
| 注入正文 `defaultOverrideText` | 21,194 ch / 226 行 | 16,963 ch / 137 行 | −20.0% |
| 强化段 `BOOST_TEXT` | 1,832 ch / 15 行 | 1,425 ch / 11 行 | −22.2% |
| `AGENTS.md`（agent 指令） | 24,035 ch | 7,579 ch | −68.5% |
| `purge_status` 默认输出 | ~6.5 KB / 64 条 | ~0.7–1.5 KB | −77%…−86% |

- 注入正文只做格式与去重：分隔线改标题、两张双语禁词表合并、CTF 两节合并、Scoped Rules 与 Intent mapping 紧凑化。13 个 `目标占位流程` slot、2 个 `TARGET fixture workflow`、以及 sqlmap / ffuf / gopher / 元数据地址 / codesign 等命令原文**逐字保留**，25 条 Scoped Rules 一条未删。
- `AGENTS.md` 的 1.6.5–1.6.54 历史 issue 复盘（约 18K 字符）外迁到 `docs/MAINTENANCE-HISTORY.md`；`check-docs` 依赖的三个 needle 留在新的 §12。
- 新增 `scripts/prompt-budget.mjs`：量注入正文 / 强化段 / 能力段 / AGENTS.md 的字符与字节、检测注入与强化段的整行重复、超预算 exit 1；已并入 `npm run check`。
- `purge_status` 默认精简（计数 + applied/pending id 区间），`{"detail":"full"}` 才逐条列补丁。
- 新增 `skipMinimal`（默认 `true`）：`minimal` 预设不再吃整份注入正文；它不走 `excludePresets` 的"预设不可判定即关闭"逻辑。
- `attest.json` 升到 `version: 2`：`sections` 只落盘前 16 段与 ≥4 KiB 的段，其余计入 `sections_omitted`，`section_count` 仍是全量。

### 变更

- 包名 `dsh-purge-community` → `dsh-purge`；版本 `1.6.55` → `2.0.0`。
- `bin` 去掉 `purge-community` 别名，保留 `dsh-purge` 与 `purge`。
- `dsh.install` 从固定 TGZ → git 来源（本仓库暂无 release 产物）。
- `scripts` 精简：删除指向未随包发布的 `packages/purge-panel`、`test/` 的条目。
- `AGENTS.md` / `README.md` / `README.zh-CN.md` / `docs/*` 的版本行与仓库地址同步。

### 移除

- dsh-unrestricted 的整条融合链（`fuseSections` / `PRESETS` / `EXECUTION_MODE_BLOCK`
  / `PERSONA_POINTER` / `PLAN_NOTE` / `PTC_ONLY_NOTE` / `STRUCTURED_OUTPUT_NOTE` /
  `customMinimal` shadow 状态机 / `/dsh-unrestricted` RPC 与设置卡片）。
  理由：它的锚点依赖逐字官方原文，而本插件宿主补丁 #4 / #25 / #26 正是拆这些句子，
  两者天生互斥；它的交付契约文本已被本插件的注入正文 + `boost` 段 + `capabilityProtocol` 覆盖。

### 迁移

1. 安装 2.0.0（git 来源），确认 profile 的 bundle 已切换；
2. 卸载 `dsh-purge-community` 与 `dsh-unrestricted`；
3. 点一次「应用」→ 退出重开 DSH → `purge selfcheck`；
4. 旧状态根由 `state-migration` 自动合并，无需手工搬。

## 1.6.55 — 前身最后一个版本

见 `docs/releases/1.6.54.md` 与 `docs/releases/` 下的历史记录。
