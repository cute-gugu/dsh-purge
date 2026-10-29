@echo off
chcp 936 >nul 2>&1
title dsh-purge 控制台
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "PS=powershell -NoProfile -ExecutionPolicy Bypass -File"
set "PSC=powershell -NoProfile -ExecutionPolicy Bypass -Command"
set "DIRECT="
if not exist "%~dp0payload\dsh-purge\package.json" (
    echo.
    echo   [错误] 找不到 payload\dsh-purge\package.json
    echo          整个文件夹要完整解压，不能只在压缩包里双击。
    echo.
    pause
    exit /b 1
)

rem ---- 参数直通（供脚本调用，跑完直接退出，不进菜单）----
if /i "%~1"=="install"   goto d_install
if /i "%~1"=="repair"    goto d_install
if /i "%~1"=="check"     goto d_check
if /i "%~1"=="status"    goto d_check
if /i "%~1"=="uninstall" goto d_uninstall
if /i "%~1"=="remove"    goto d_uninstall
if /i "%~1"=="paths"     goto d_paths
if /i "%~1"=="help"      goto d_help
goto menu

:menu
cls
echo.
echo   ==========================================================
echo     dsh-purge 本地控制台
echo   ==========================================================
echo.
echo     [1]  一键安装 / 修复          装上新版，或把坏掉的修好
echo     [2]  状态自检                 只看不改，报告哪里不对劲
echo     [3]  卸载                     从 DSH 里摘掉，文件也清掉
echo     [4]  查看安装位置             把 DSH_HOME / profile 打印出来
echo     [5]  看说明文档               打开 README-先看我.txt
echo.
echo     [0]  退出
echo.
echo   ----------------------------------------------------------
set "CH="
set /p "CH=  请输入编号后按回车： "
if "%CH%"=="1" goto do_install
if "%CH%"=="2" goto do_check
if "%CH%"=="3" goto do_uninstall
if "%CH%"=="4" goto do_paths
if "%CH%"=="5" goto do_readme
if "%CH%"=="0" goto bye
echo.
echo   没看懂这个编号，重来一次。
timeout /t 1 >nul 2>&1
goto menu

:do_install
echo.
%PS% "%~dp0install-dsh-purge.ps1" %2 %3 %4 %5
echo.
if defined DIRECT exit /b 0
pause
goto menu

:do_check
echo.
%PS% "%~dp0check-dsh-purge.ps1" %2 %3 %4 %5
echo.
if errorlevel 1 (
    echo   ----------------------------------------------------------
    echo   自检发现问题。要现在修吗？
    echo     [1] 修（跑一次安装/修复）
    echo     [0] 先算了
    echo.
    set "FIX="
    set /p "FIX=  请输入编号后按回车： "
    if "!FIX!"=="1" (
        echo.
        %PS% "%~dp0install-dsh-purge.ps1"
    )
)
if defined DIRECT exit /b 0
pause
goto menu

:do_uninstall
echo.
set "SURE="
set /p "SURE=  确定要从 DSH 里卸载 dsh-purge 吗？输入 y 回车确认： "
if /i "!SURE!"=="y" goto u_go
echo   已取消。
if defined DIRECT exit /b 1
pause
goto menu

:u_go
echo.
%PS% "%~dp0uninstall-dsh-purge.ps1" %2 %3 %4 %5
echo.
if defined DIRECT exit /b 0
pause
goto menu

:do_paths
echo.
%PSC% ^
 "$h = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' };" ^
 "Write-Host ('  DSH_HOME : ' + $h);" ^
 "Get-ChildItem -LiteralPath (Join-Path $h 'profiles') -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'package.json') } | ForEach-Object { Write-Host ('  profile  : ' + $_.Name); $p = Join-Path $_.FullName 'package.json'; if (Test-Path $p) { $j = Get-Content -Raw -Encoding UTF8 $p | ConvertFrom-Json; $d = $j.dependencies.'dsh-purge'; if ($d) { Write-Host ('     dsh-purge -> ' + $d) } else { Write-Host '     dsh-purge -> (未登记)' } } };" ^
 "Write-Host ('  母本目录 : ' + (Join-Path $env:LOCALAPPDATA 'dsh-purge'));" ^
 "Write-Host ('  状态目录 : ' + (Join-Path $h 'dsh-purge'));"
echo.
if defined DIRECT exit /b 0
pause
goto menu

:do_readme
if exist "%~dp0README-先看我.txt" (
    start "" notepad "%~dp0README-先看我.txt"
) else (
    echo   没找到 README-先看我.txt
    pause
)
if defined DIRECT exit /b 0
goto menu

:do_help
echo.
echo   用法： dsh-purge.bat [install ^| check ^| uninstall ^| paths]
echo          不带参数 = 打开菜单；带参数跑完直接退出。
echo.
pause
exit /b 0

:bye
exit /b 0

rem ---- 直通入口：置位 DIRECT 后跳到对应的交互分支 ----
:d_install
set "DIRECT=1"
goto do_install

:d_check
set "DIRECT=1"
goto do_check

:d_uninstall
set "DIRECT=1"
goto do_uninstall

:d_paths
set "DIRECT=1"
goto do_paths

:d_help
set "DIRECT=1"
goto do_help
