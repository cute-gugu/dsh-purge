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
