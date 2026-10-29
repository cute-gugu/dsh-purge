# 2.0.0

首个合并版。把 **dsh-purge-community 1.6.55** 与 **dsh-unrestricted 0.2.4** 合成一个插件，包名统一为 `dsh-purge`。

## 为什么要合并

两个插件做的是同一件事的两个层次，装在一起反而互相拆台：

- 它们都挂在宿主的 `system-prompt/assemble` waterfall 上改写 sections；
- 它们都往系统提示里塞「执行契约 / 无限制模式」正文；
- 它们都提供一个叫 `unrestricted` 的命名空间（一个当预设 id，一个当 settings 命名空间）；
- 更关键的是，dsh-unrestricted 的融合逻辑逐字锚定官方原文
  `You are an AI agent powered by DeepSeek Harness.` 与
  `You are a coding agent powered by the {{model}} model.`，
  而 dsh-purge 的宿主补丁 #25 `HARNESS_IDENTITY_STRIP`、#4 `SYSTEM_PROMPT_PERSONA`、
  #26 `MINIMAL_PERSONA_PURGE` 干的正是拆掉这些句子。
  补丁一旦落下，unrestricted 的锚点校验就失败，它按设计**静默降级为不生效**——
  面板上只显示一行 invariant 失效，用户以为开着，实际什么都没上去。

## 吸收了什么

只保留 dsh-unrestricted 里有独立价值的三样，其余丢弃：

1. **运行时注入指纹（attest）**：`lib/attest.js`。每次装配后对实际送进模型的 sections
   逐个算 sha256（name / order / 字节数 / 前 16 hex），再算一个全装配指纹，
   写 `$DSH_HOME/dsh-purge/attest.json`（2 秒节流、指纹没变不写）。
   它回答的是探针回答不了的问题：这一轮到底送了哪些段、头段在不在、强化段在不在。
2. **状态端点形状**：`GET /dsh-purge/community` 增加 `attest` 字段；
   `POST {"op":"attest"}` 返回指纹 + 一行摘要；`purge_status` 输出附加指纹摘要。
3. **minimal 预设处理**：dsh-purge 早有 `adaptInjectForMinimalPreset()` 与
   `deployment:persona-prefix` shadow 路径，因此这里只是确认口径一致，没有搬代码。

## 状态迁移

包名从 `dsh-purge-community` 改成 `dsh-purge`，落盘状态根随之改变。
`lib/state-migration.js` 在启动时做一次性合并：

- 旧的 `$DSH_HOME/dsh-purge-community/` 并入 `$DSH_HOME/dsh-purge/`；
- `audit.jsonl` 追加合并，其余同名条目保留新根、旧文件另存 `.legacy-<时间戳>`；
- 完成后写 `.merged-from-dsh-purge-community` 标记，第二次启动直接跳过；
- 任何异常只记日志，不影响插件启动。

## 命令行

- `purge-community` 别名去掉，统一为 `purge`；
- `dsh.install` 改为 git 来源（本仓库暂无 release 产物）。

## 2.0.0 的瘦身

2.0.0 除了合并，还把「每轮固定提示词成本」压了一轮：注入正文 −20%、强化段 −22%、`AGENTS.md`（会被当 agent 指令读）−68.5%、`purge_status` 默认输出 −77%～86%。规则一条没删——压的是格式、重复与已归档的历史条目。`npm run check` 现在多跑一项 `prompt-budget`，成本涨回预算外会让 CI 直接失败。

## 升级注意

- 先装 2.0.0，再卸载 `dsh-purge-community` 与 `dsh-unrestricted`；
- 宿主补丁需要重新点一次「应用」并退出重开才加载；
- 用户提示词 `prompt-inject.md`、tuning、权限配置一律不动。
