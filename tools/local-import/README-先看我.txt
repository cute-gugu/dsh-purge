dsh-purge 本地一键导入包
================================================

这个文件夹是给「不会手动装 DSH 插件」的人用的。
不需要联网，不需要 Node / npm / pnpm，不需要命令行。
只要 Windows（Win10 / Win11 都行）。


一、怎么装（3 步）
------------------------------------------------
1. 把整个压缩包解压出来（不要在里面直接双击，要先解压）。
2. 双击 一键导入.cmd（或用控制台 dsh-purge.bat，见第二节）
3. 看到「装好了」以后：
   a. 完全退出 DSH —— 关窗口不够，托盘图标要右键退出，
      或者在任务管理器里确认没有 DSH 进程了。
   b. 重新打开 DSH。
   c. 左侧栏出现 Purge 面板 = 成功。

第一次用，请在 Purge 面板里点一次「应用」，然后同样完全退出再打开，
宿主侧的补丁才会真正生效。


二、控制台：dsh-purge.bat（推荐）
------------------------------------------------
双击 dsh-purge.bat 会出现一个数字菜单：

  [1] 一键安装 / 修复    装插件；感觉哪里坏了也点这个重装一遍
  [2] 状态自检           检查装好了没、文件全不全、有没有残留的旧插件
  [3] 卸载               去掉登记并删掉插件文件
  [4] 查看安装位置       打印相关路径，出问题截图给别人看
  [5] 看说明文档         打开本文件
  [0] 退出

自检有三种结果：
  · 已装好，一切正常
  · 有问题，但可以自动修（会问你「要现在修吗」）
  · 还没装

也支持直接敲命令：dsh-purge.bat check / install / uninstall / paths

三、它到底做了什么
------------------------------------------------
全部在你自己电脑本地完成，只碰这三处：

1. 把插件本体复制到
     %LOCALAPPDATA%\dsh-purge\<版本号>\
2. 再复制一份到
     <DSH 目录>\profiles\<profile>\node_modules\dsh-purge\
3. 在 <profile>\package.json 里登记两行：
     依赖   "dsh-purge": "file:..."
     dsh.profile.bundles 里加一项 "dsh-purge"

改 package.json 之前会自动备份成 package.json.bak-日期-时间，
装坏了把备份改回来就恢复了。

它不会碰 DSH 安装目录里的任何程序文件，也不会改系统设置、不写注册表。


四、装之前要确认的事
------------------------------------------------
- DSH 至少启动过一次。否则找不到 profiles 目录，脚本会提示你先开一次。
- 如果 DSH 正在运行，没关系，但装完必须完全退出重开才生效。
- 脚本会沿用你原来的 profile（一般叫 desktop）。有多个时会让你选。


五、想先看看它会做什么（不写入任何东西）
------------------------------------------------
在文件夹空白处按住 Shift 右键 → 在此处打开 PowerShell，
然后运行：

  powershell -NoProfile -ExecutionPolicy Bypass -File .\install-dsh-purge.ps1 -DryRun

它会打印将要执行的每一步，以及改完之后的 package.json，但一个字节都不写。


六、卸载
------------------------------------------------
双击 卸载.cmd —— 会从 package.json 里去掉登记，并删掉两份插件文件。
同样要完全退出 DSH 再打开。

只想删掉登记、保留文件，用：

  powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall-dsh-purge.ps1 -KeepLocalCopy


七、常见问题
------------------------------------------------
Q: 双击后窗口一闪就没了？
A: 说明是被安全软件拦了，或者你是在压缩包里直接双击的。
   先完整解压，再右键 一键导入.cmd → 以管理员身份运行试试。

Q: 提示「无法加载文件 ... 因为在此系统上禁止运行脚本」？
A: 一键导入.cmd 已经带了 -ExecutionPolicy Bypass，正常不会遇到。
   真遇到了就在 PowerShell 里跑：
     Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

Q: 装完没有 Purge 面板？
A: 九成是没完全退出 DSH。任务管理器里搜 DSH，全结束掉再开。

Q: 提示 profiles 目录不存在？
A: 先把 DSH 打开一次，让它初始化，再回来双击。

Q: 我这台机器上还装着旧的 dsh-purge-community 或 dsh-unrestricted？
A: 脚本默认会把它们从登记表里去掉并删除对应目录（避免两个抢同一条
   system-prompt）。不想动它们，加参数 -RemoveLegacy:$false 再跑一次。


八、这个插件是干什么的
------------------------------------------------
dsh-purge 把 DSH 的提示词层与一批宿主侧闸门统一成「本地无限制执行」
模式：注入执行契约、去掉人设限制、可选的宿主补丁、红队演练台、
purge 命令与 MCP 工具（purge_status / purge_apply / purge_revert）。

详细说明见同目录 payload\dsh-purge\README.md 与 AGENTS.md。
上游仓库：https://github.com/cute-gugu/dsh-purge
