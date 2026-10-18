@echo off
chcp 65001 > nul
echo ============================================================
echo   一键下载比特流至安路 EG4S20 板卡 (JTAG 模式)
echo ============================================================
echo.

if not exist "lock_Runs\phy_1\lock.bit" (
    echo [错误] 未找到比特流文件 lock_Runs\phy_1\lock.bit！
    pause
    exit /b 1
)

echo [1/2] 正在连接下载器并烧录 lock.bit ...
"D:\TD\bin\td_commands_prompt.exe" tools\download.tcl

if %ERRORLEVEL% equ 0 (
    echo.
    echo ============================================================
    echo [成功] 比特流下载完成！板载 LED0 心跳灯与数码管将立即点亮！
    echo ============================================================
) else (
    echo.
    echo [失败] 烧录未成功，请检查 JTAG USB 驱动或排线接触！
)

echo.
pause
